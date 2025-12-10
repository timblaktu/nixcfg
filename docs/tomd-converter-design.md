# tomd: Universal Document to Markdown Converter
## Design Document & Refactoring Proposal

**Date**: 2024-12-04
**Author**: System Architecture Team
**Status**: Proposal
**Current Implementation**: marker-pdf package in nixcfg

## Executive Summary

This document proposes refactoring the current `marker-pdf` package into a more general-purpose tool called `tomd` (to markdown). The new tool will leverage the strengths of both **Docling** (IBM's document structure analysis) and **marker-pdf** (OCR and visual extraction) to create a best-in-class document-to-markdown converter.

## Current State Analysis

### Problems with Current Implementation

1. **Misleading Flag Design**
   - `--auto-chunk` doesn't do automatic/smart chunking - just enables chunking
   - `--chunk-size` is always used regardless of `--auto-chunk`
   - Users must specify both flags for chunking to work

2. **No Intelligent Document Analysis**
   - `extract_toc_chunks()` is a stub that always returns failure
   - Only does dumb page-based splitting (lines 91-105 of default.nix)
   - No section boundary detection
   - No understanding of document structure

3. **Memory Management Issues**
   - Known memory leaks in marker-pdf upstream
   - 750-page PDF consumes 20GB+ RAM
   - WSL2-specific workarounds needed (ulimit vs systemd-run)
   - Requires manual chunking to avoid OOM

4. **Limited Format Support**
   - Only handles PDFs
   - No support for DOCX, PPTX, HTML, images, etc.

### Current Strengths

1. **Excellent OCR Capabilities**
   - marker-pdf excels at OCR for scanned PDFs
   - GPU-accelerated via PyTorch/CUDA
   - Good accuracy on complex layouts

2. **Memory Control Infrastructure**
   - Batch size multiplier for VRAM control
   - PyTorch memory optimization settings
   - Chunking infrastructure (though not smart)
   - WSL2 compatibility with ulimit fallback

## Proposed Architecture: tomd

### Core Concept

**tomd** will be a unified document-to-markdown converter that:
- Uses **Docling** for document structure analysis and non-OCR conversions
- Uses **marker-pdf** for OCR-heavy tasks and scanned documents
- Intelligently routes documents to the appropriate engine
- Provides smart chunking based on actual document structure

### Component Responsibilities

#### Docling (Primary Engine)
- **Document Structure Analysis**: Headers, sections, chapters, TOC extraction
- **Format Support**: DOCX, PPTX, HTML, images, AsciiDoc, existing Markdown
- **Table Extraction**: Superior table structure recognition
- **Smart Chunking**: Determine optimal split points based on document structure
- **Fast Processing**: 0.49 sec/page for standard documents
- **Metadata Extraction**: Title, authors, references, language

#### marker-pdf (OCR Engine)
- **Scanned PDFs**: When OCR is required
- **Complex Visual Layouts**: When visual understanding is critical
- **GPU Acceleration**: For heavy ML processing
- **Fallback Engine**: When Docling fails or produces poor results

### Architecture Diagram

```
┌─────────────────────────────────────────┐
│             tomd CLI                     │
│         Main Entry Point                 │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│         Document Analyzer                │
│    (Powered by Docling)                 │
│                                          │
│  • Detect format                        │
│  • Analyze structure                    │
│  • Identify if OCR needed               │
│  • Extract section boundaries           │
└─────────────┬───────────────────────────┘
              │
              ▼
        ┌─────┴─────┐
        │ Router    │
        └─────┬─────┘
              │
    ┌─────────┴──────────┐
    ▼                     ▼
┌─────────────┐    ┌─────────────┐
│   Docling   │    │ marker-pdf  │
│   Engine    │    │   Engine    │
│             │    │             │
│ • DOCX/PPTX │    │ • Scanned   │
│ • HTML      │    │   PDFs      │
│ • Clean PDFs│    │ • Complex   │
│ • Images    │    │   visuals   │
└──────┬──────┘    └──────┬──────┘
       │                   │
       └─────────┬─────────┘
                 │
                 ▼
    ┌────────────────────────┐
    │   Post-Processor       │
    │ • Merge chunks         │
    │ • Clean formatting     │
    │ • Validate output      │
    └────────────────────────┘
                 │
                 ▼
         [Output: .md file]
```

## Implementation Plan

### Phase 1: Package Structure Refactoring

```nix
# pkgs/tomd/default.nix
{ lib
, stdenv
, python3
, writeShellScriptBin
, docling          # Structure analysis
, marker-pdf       # OCR engine (as internal dep)
, qpdf            # PDF manipulation
, systemd         # Memory management
, jq              # JSON processing
, gawk            # Calculations
}:
```

### Phase 2: Intelligent Routing Logic

```python
# tomd-router.py (simplified pseudo-code)
def analyze_document(input_file):
    """Determine best processing strategy"""

    # Use Docling to analyze structure
    doc = docling.analyze(input_file)

    # Decision matrix
    if doc.format in ['docx', 'pptx', 'html']:
        return 'docling'  # These formats work best with Docling

    if doc.is_scanned or doc.ocr_confidence < 0.7:
        return 'marker'  # Need OCR capabilities

    if doc.has_complex_tables and not doc.is_scanned:
        return 'docling'  # Better table extraction

    if doc.page_count > 100:
        return 'hybrid'  # Use Docling for structure, process chunks with marker

    return 'docling'  # Default to faster engine
```

### Phase 3: Smart Chunking Implementation

```python
# smart-chunking.py
def create_smart_chunks(input_pdf, max_chunk_size=100):
    """Create chunks based on document structure"""

    # Step 1: Extract structure with Docling
    structure = docling.extract_structure(input_pdf)

    # Step 2: Identify natural boundaries
    boundaries = []
    for element in structure.elements:
        if element.type in ['chapter', 'section', 'h1', 'h2']:
            boundaries.append({
                'page': element.page,
                'title': element.text,
                'level': element.level
            })

    # Step 3: Create chunks respecting max_chunk_size
    chunks = []
    current_chunk = {'start': 1, 'pages': []}

    for boundary in boundaries:
        if len(current_chunk['pages']) >= max_chunk_size:
            # Chunk is too large, split here
            chunks.append(current_chunk)
            current_chunk = {
                'start': boundary['page'],
                'title': boundary['title'],
                'pages': []
            }
        current_chunk['pages'].append(boundary['page'])

    # Step 4: Fall back to page-based if no structure
    if not chunks:
        return create_page_chunks(input_pdf, max_chunk_size)

    return chunks
```

### Phase 4: CLI Interface Design

```bash
# New unified interface
tomd <input> <output> [OPTIONS]

# Smart defaults - no confusing flags
tomd document.pdf document.md
# Automatically:
# - Analyzes with Docling
# - Chunks if >50 pages
# - Uses marker for OCR if needed
# - Optimizes memory usage

# Force specific engine
tomd document.pdf document.md --engine=marker  # Force OCR engine
tomd document.pdf document.md --engine=docling # Force structure engine

# Control chunking
tomd large.pdf output.md --chunk-size=100      # Fixed size chunks
tomd large.pdf output.md --smart-chunks        # Use section boundaries (default)
tomd large.pdf output.md --no-chunks           # Process as single file

# Memory controls (same as before)
tomd large.pdf output.md --memory-max=20G
tomd large.pdf output.md --batch-multiplier=0.25

# Format-specific options
tomd spreadsheet.xlsx data.md --preserve-formulas
tomd presentation.pptx slides.md --slides-as-sections

# Quality options
tomd scanned.pdf text.md --ocr-quality=high    # Slower, better OCR
tomd clean.pdf text.md --fast                  # Skip OCR checks
```

## Feature Comparison Matrix

| Feature | Current (marker-pdf) | Proposed (tomd) |
|---------|---------------------|-----------------|
| **PDF Support** | ✅ Excellent | ✅ Excellent |
| **DOCX/PPTX Support** | ❌ | ✅ Via Docling |
| **HTML Support** | ❌ | ✅ Via Docling |
| **Image Support** | ❌ | ✅ Via Docling |
| **OCR Quality** | ✅ Excellent | ✅ Excellent (via marker) |
| **Table Extraction** | 🔶 Good | ✅ Excellent (via Docling) |
| **Structure Detection** | ❌ None | ✅ Excellent (via Docling) |
| **Smart Chunking** | ❌ Page-based only | ✅ Section-based |
| **Processing Speed** | 🔶 0.86 sec/page | ✅ 0.49 sec/page (Docling) |
| **Memory Efficiency** | 🔶 With workarounds | ✅ Improved with smart routing |
| **Metadata Extraction** | ❌ | ✅ Via Docling |

## Migration Strategy

### Phase 1: Foundation (Week 1)
1. Create new `pkgs/tomd/` directory
2. Set up Python environment with both docling and marker-pdf
3. Implement basic routing logic
4. Maintain backward compatibility via alias: `marker-pdf-env` → `tomd`

### Phase 2: Integration (Week 2)
1. Implement Docling-based structure analysis
2. Create smart chunking algorithm
3. Add format detection and routing
4. Test with various document types

### Phase 3: Optimization (Week 3)
1. Fine-tune routing heuristics
2. Optimize memory usage patterns
3. Add caching for structure analysis
4. Implement parallel processing where applicable

### Phase 4: Polish (Week 4)
1. Comprehensive testing suite
2. Documentation and examples
3. Performance benchmarking
4. User feedback integration

## Configuration Schema

```nix
# home/modules/tomd.nix
{
  programs.tomd = {
    enable = true;

    # Default engine preferences
    defaultEngine = "auto";  # auto, docling, marker

    # Memory settings
    memory = {
      maxMemory = "24G";
      highMemory = "20G";
      batchMultiplier = 0.5;  # For GPU operations
    };

    # Chunking preferences
    chunking = {
      enabled = true;
      smartChunks = true;  # Use structure-based chunking
      maxChunkSize = 100;  # Pages per chunk
      minChunkSize = 10;   # Don't create tiny chunks
    };

    # Engine-specific settings
    engines = {
      docling = {
        enable = true;
        modelCache = "~/.cache/docling-models";
        timeout = 300;  # seconds
      };

      marker = {
        enable = true;
        cudaSupport = true;
        vramLimit = 7;  # GB
        ocrQuality = "balanced";  # fast, balanced, high
      };
    };

    # Output preferences
    output = {
      preserveFormatting = true;
      includeMetadata = true;
      cleanEmptyLines = true;
      tableFormat = "github";  # github, simple, grid
    };
  };
}
```

## Performance Expectations

### Processing Speed (per page)
- **Simple PDFs**: 0.3-0.5 seconds (Docling)
- **Complex PDFs**: 0.5-0.9 seconds (Docling)
- **Scanned PDFs**: 1.0-2.0 seconds (marker-pdf with OCR)
- **Mixed documents**: 0.6-1.2 seconds (hybrid approach)

### Memory Usage
- **Small docs (<50 pages)**: 2-4GB RAM
- **Medium docs (50-200 pages)**: 4-8GB RAM (with chunking)
- **Large docs (200+ pages)**: 6-12GB RAM (with smart chunking)
- **GPU VRAM**: 2-7GB depending on batch size

### Quality Metrics
- **Text Extraction**: 98%+ accuracy on clean documents
- **Table Preservation**: 95%+ structure accuracy
- **Section Detection**: 90%+ accuracy on structured documents
- **OCR Accuracy**: 95%+ on good quality scans

## Risk Analysis & Mitigations

### Risks
1. **Dependency Complexity**: Two large ML frameworks
   - *Mitigation*: Lazy loading, only initialize needed engine

2. **Version Conflicts**: PyTorch versions between tools
   - *Mitigation*: Use separate venvs if needed

3. **Model Download Size**: Docling models are large
   - *Mitigation*: Cache models, provide lightweight mode

4. **Processing Time**: Some docs may take longer
   - *Mitigation*: Progress indicators, ability to cancel

5. **Memory Spikes**: Combined tools may use more RAM
   - *Mitigation*: Exclusive engine use, not parallel

## Success Criteria

1. **Functional Requirements**
   - ✅ Support for PDF, DOCX, PPTX, HTML, images
   - ✅ Smart section-based chunking
   - ✅ Automatic engine selection
   - ✅ Memory limits enforced

2. **Performance Requirements**
   - ✅ Faster than marker-pdf alone for clean PDFs
   - ✅ No slower than marker-pdf for OCR tasks
   - ✅ Memory usage predictable and bounded

3. **User Experience**
   - ✅ Single command for all document types
   - ✅ No confusing flag combinations
   - ✅ Clear progress feedback
   - ✅ Helpful error messages

## Conclusion

The refactoring from `marker-pdf` to `tomd` represents a significant improvement in functionality, usability, and performance. By combining the strengths of Docling (structure analysis) and marker-pdf (OCR), we create a tool that handles a wider range of documents more intelligently.

The key improvements:
- **10x better format support** (PDF → PDF, DOCX, PPTX, HTML, etc.)
- **True smart chunking** based on document structure
- **40% faster processing** for standard documents
- **Cleaner CLI interface** without confusing flags
- **Better memory management** through intelligent routing

This positions `tomd` as a comprehensive document-to-markdown solution suitable for any document processing pipeline.

## Appendix: Current Implementation Issues

### Evidence from default.nix (lines 91-105)
```bash
extract_toc_chunks() {
  local input_pdf="$1"
  local chunk_size="$2"

  # Try to extract TOC using qpdf
  local toc_json
  if toc_json=$(${qpdf}/bin/qpdf "$input_pdf" --json --json-key=outlines 2>/dev/null); then
    # Parse TOC and create chapter-based chunks
    # For now, fall back to page-based chunking (TOC parsing is complex)
    # TODO: Implement full TOC parsing in future iteration
    return 1  # ALWAYS RETURNS FAILURE!
  else
    return 1  # ALSO RETURNS FAILURE!
  fi
}
```

This function is called but never succeeds, making `--auto-chunk` meaningless for "smart" chunking.