# tomd - Universal Document to Markdown Converter

## Overview

`tomd` is a comprehensive document-to-markdown converter that intelligently processes various document formats including PDF, DOCX, PPTX, HTML, and images. It provides automatic engine selection, memory management, and smart chunking capabilities.

## Current Status (2025-12-06)

### Working Components
- **PyMuPDF4LLM Engine**: ✅ Operational for PDFs and HTML files
  - Fast processing
  - Good text extraction
  - Basic formatting preservation
  - Suitable for most text-based documents

- **marker-pdf Integration**: ✅ Complete (requires marker-pdf in environment)
  - Full OCR support for scanned PDFs and images
  - ML-based layout understanding
  - Memory management and chunking
  - Progress indicators

### Pending Components
- **Docling Engine**: ⏳ Blocked by docling-parse 4.5.0 build issues
  - Superior document structure extraction
  - Better table and list handling
  - Advanced formatting preservation
  - Will be preferred engine when available

## Installation

```bash
# In nixcfg flake environment
nix build .#tomd

# Or add to home.packages in your home-manager configuration
home.packages = with pkgs; [
  (callPackage ../../pkgs/tomd { })
];
```

## Basic Usage

### Simple Conversion
```bash
# Convert PDF to markdown
tomd document.pdf document.md

# Convert HTML to markdown
tomd webpage.html output.md

# Process with verbose output
tomd document.pdf output.md --verbose
```

### Engine Selection

tomd automatically selects the best engine based on file type:
- **PDFs**: Uses PyMuPDF4LLM (Docling when available)
- **HTML**: Uses PyMuPDF4LLM (Docling when available)
- **DOCX/PPTX**: Will use Docling when available
- **Images**: Requires marker engine for OCR

Force a specific engine:
```bash
# Force marker engine for OCR processing
tomd scanned.pdf output.md --engine=marker

# Force docling engine (when available)
tomd document.pdf output.md --engine=docling
```

### Memory Management

Control memory usage for large documents:
```bash
# Set memory limits
tomd large.pdf output.md --memory-max=16G --memory-high=14G

# Process with smaller chunks
tomd huge.pdf output.md --chunk-size=50

# Enable auto-chunking for large files
tomd large.pdf output.md --auto-chunk
```

### Chunking Options

```bash
# Use smart chunking based on document structure (default)
tomd document.pdf output.md --smart-chunks

# Process without chunking (may use lots of memory)
tomd small.pdf output.md --no-chunks

# Set custom chunk size
tomd document.pdf output.md --chunk-size=25
```

## Engine Capabilities

### PyMuPDF4LLM (Default/Fallback)
**Strengths:**
- Fast processing
- Reliable text extraction
- Low memory usage
- Works with most PDF versions

**Limitations:**
- Basic formatting only
- No OCR support
- Limited structure recognition
- Tables may lose formatting

**Best for:**
- Quick conversions
- Text-heavy documents
- When speed is priority
- Documents with simple layouts

### marker-pdf (OCR Engine)
**Strengths:**
- Full OCR for scanned documents
- ML-based layout analysis
- Handles complex visual layouts
- Extracts images and diagrams

**Limitations:**
- High memory usage (can use 20GB+ for large PDFs)
- Slower processing
- Requires GPU for best performance
- May struggle with very large files

**Best for:**
- Scanned PDFs
- Documents with images
- Complex layouts
- When OCR is needed

### Docling (When Available)
**Strengths:**
- Superior structure extraction
- Excellent table preservation
- Smart heading detection
- Maintains formatting

**Limitations:**
- Currently blocked by build issues
- Moderate memory usage
- Processing speed varies

**Best for:**
- Documents with complex structure
- Scientific papers
- Reports with tables
- When formatting is critical

## Memory Considerations

### WSL2 Environment
- Uses `ulimit` for memory limiting
- Automatic detection of WSL environment
- Fallback mechanisms for memory management

### Native Linux
- Uses systemd-run with cgroups v2
- More precise memory control
- Better process isolation

### Recommendations by Document Size
| Document Size | Memory Max | Memory High | Chunk Size |
|--------------|------------|-------------|------------|
| < 50 pages   | 8G         | 6G          | No chunking |
| 50-200 pages | 16G        | 14G         | 100 pages   |
| 200-500 pages| 20G        | 18G         | 50 pages    |
| > 500 pages  | 24G        | 20G         | 25 pages    |

## Troubleshooting

### Common Issues

#### "marker-pdf not available"
- marker-pdf package needs to be installed
- Add to home.packages or nix-shell
- Check with: `which marker-pdf-env`

#### Out of Memory Errors
- Reduce chunk size: `--chunk-size=25`
- Lower memory limits: `--memory-max=8G`
- Enable auto-chunking: `--auto-chunk`
- Use PyMuPDF engine instead of marker

#### Poor Output Quality
- Try different engines
- For scanned PDFs, use marker engine
- For structured documents, wait for Docling
- Check if document has text layer with `pdftotext`

#### Processing Hangs
- Large files may take several minutes
- Use `--verbose` to see progress
- Monitor system resources with `htop`
- Consider chunking for files > 100MB

### Debug Commands

```bash
# Check available engines
tomd --help

# Test with verbose output
tomd test.pdf test.md --verbose

# Check if PDF has text layer
pdftotext -l 1 document.pdf - | head

# Monitor memory usage
watch -n 1 free -h

# Check for marker-pdf
find /nix/store -name "marker-pdf-env" -type f
```

## Best Practices

1. **Start Conservative**: Begin with default settings, adjust if needed
2. **Use Verbose Mode**: When debugging, always use `--verbose`
3. **Monitor Resources**: Keep an eye on RAM usage for large files
4. **Choose Right Engine**:
   - Quick extraction: PyMuPDF
   - Scanned docs: marker
   - Complex structure: Docling (when available)
5. **Chunk Large Files**: Files > 100MB should use chunking
6. **Test Small First**: Try a few pages before processing entire document

## Future Improvements

### In Development
- Docling integration (blocked by upstream)
- Better progress indicators
- Benchmark mode for engine comparison
- Batch processing support

### Planned Features
- Automatic engine selection based on content analysis
- Resume capability for interrupted processing
- Output format options (GFM, CommonMark, etc.)
- Configuration file support
- Multi-file processing

## Examples

### Process a Research Paper
```bash
# Research papers often have complex structure
tomd research.pdf output.md \
  --engine=docling \  # When available
  --smart-chunks \
  --chunk-size=50
```

### Convert Scanned Book
```bash
# Scanned books need OCR
tomd scanned-book.pdf book.md \
  --engine=marker \
  --auto-chunk \
  --memory-max=20G \
  --verbose
```

### Quick Text Extraction
```bash
# Fast extraction, formatting not critical
tomd report.pdf report.md \
  --no-chunks \
  --memory-max=4G
```

### Batch Processing (Manual)
```bash
# Process multiple files
for pdf in *.pdf; do
  tomd "$pdf" "${pdf%.pdf}.md" --memory-max=8G
done
```

## Technical Details

### Architecture
- **Wrapper Script**: Shell script handling argument parsing and routing
- **Python Processors**: Separate modules for each engine
- **Memory Management**: WSL/Linux detection with appropriate limits
- **File Detection**: Extension and MIME type based

### Dependencies
- Python 3.x with packages:
  - pymupdf
  - pymupdf4llm
  - pdfplumber
  - pypdfium2
  - pillow
  - filetype
  - httpx
- System tools:
  - qpdf (chunking)
  - pdftotext (OCR detection)
  - systemd (Linux memory management)

### File Locations
- Package: `/home/tim/src/nixcfg/pkgs/tomd/`
- Processors:
  - `process_docling.py`
  - `process_marker.py`
  - `process_docling_serve.py`

## Support

For issues or questions:
1. Check this documentation
2. Use `--verbose` for debugging
3. Review CLAUDE.md for development status
4. Check nixpkgs for docling-parse updates

---

*Last updated: 2025-12-06*