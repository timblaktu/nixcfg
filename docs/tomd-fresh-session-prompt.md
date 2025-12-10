# Fresh Session Prompt for tomd Enhancement

## Context
The basic `tomd` universal document-to-markdown converter has been implemented and is working with PyMuPDF as a fallback. The infrastructure is in place, but the full vision from `docs/tomd-converter-design.md` needs to be realized by fixing engine integrations.

## Current State (2024-12-04)
- **Branch**: `claude/tomd-implementation` (committed, working)
- **Package Location**: `pkgs/tomd/` (complete Nix derivation)
- **Status**: Basic PDF conversion working via PyMuPDF fallback
- **Design Document**: `docs/tomd-converter-design.md` (full architecture)

### What's Working
- ✅ CLI interface with format detection and engine routing
- ✅ PyMuPDF-based PDF to markdown conversion
- ✅ WSL-compatible memory limiting (ulimit/systemd-run auto-detection)
- ✅ Package builds successfully and passes flake check
- ✅ Tested with simple PDF conversion

### What's Not Working
- ❌ **Docling**: `docling-parse` 4.5.0 fails C++ compilation in nixpkgs
- ❌ **marker-pdf**: Not packaged in nixpkgs (needs custom derivation)
- ❌ **Smart Chunking**: Requires Docling for structure analysis
- ❌ **Format Support**: DOCX/PPTX/HTML need Docling to work

## Technical Issues Discovered

### 1. Docling Build Failure
```
error: Cannot build '/nix/store/p1bcgd431wfi4dzjq5bdp86xipy27iyg-python3.13-docling-parse-4.5.0.drv'
subprocess.CalledProcessError: Command '['.../python3.13', 'build.py']' returned non-zero exit status 1
```
- CMake/C++ compilation issue during wheel build
- Consider using `docling-serve` (1.5.1) as alternative
- Or pin to older working version of docling

### 2. marker-pdf Packaging Needed
- Not available in nixpkgs
- Requires: PyTorch, transformers, surya-ocr, huggingface-hub
- Previous work exists in marker-pdf memory fix implementation
- Complex CUDA dependencies for GPU acceleration

## Priority Next Steps

### Option A: Fix Docling Integration (Recommended)
1. Debug docling-parse compilation issue
   - Check CMake dependencies
   - Try older docling version
   - Or use docling-serve instead
2. Once working, implement:
   - Document structure analysis
   - Smart chunking based on TOC/sections
   - DOCX/PPTX/HTML support

### Option B: Package marker-pdf First
1. Create proper Nix package for marker-pdf
   - Reuse existing work from memory fixes
   - Include all ML dependencies
   - Test GPU acceleration
2. Implement OCR engine routing
3. Test with scanned PDFs

### Option C: Enhance Current Implementation
1. Improve PyMuPDF processing
   - Add better text extraction
   - Implement basic structure detection
   - Add table extraction
2. Create temporary chunking solution
3. Add basic format support without Docling

## Testing Resources
- Test PDF creation script: Can use PyMuPDF to create test documents
- Existing test successful: `/tmp/test.pdf` → `/tmp/output.md`
- Memory limiting verified working in WSL2

## Files to Review
- `pkgs/tomd/default.nix` - Main package definition
- `pkgs/tomd/process_docling.py` - Docling processor (with PyMuPDF fallback)
- `pkgs/tomd/process_marker.py` - Marker processor (stub)
- `docs/tomd-converter-design.md` - Full architecture vision

## Additional Context
- GPU: RTX 2000 Ada with 8GB VRAM
- Environment: WSL2 (ulimit memory limiting works)
- Previous marker-pdf work has memory control solutions

Please continue by either fixing the Docling integration or packaging marker-pdf properly to achieve the full vision of the universal document converter.