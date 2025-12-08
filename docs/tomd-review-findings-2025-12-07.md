# tomd Pipeline Review Findings - 2025-12-07

## Executive Summary
Comprehensive review of the PDF-to-markdown conversion pipeline (tomd, marker-pdf, docling) conducted while waiting for docling package build. The pipeline architecture is solid but has several implementation issues and missing features.

## Current Status
- **marker-pdf**: ✅ Working, tested with PDF files, OCR functional but slow
- **docling**: 🔧 Builds with nlohmann_json 3.11.3, runtime testing pending
- **tomd**: 📦 Package defined, build pending due to heavy dependencies
- **nixpkgs fork**: `docling-parse-fix` branch with nlohmann_json downgrade

## Critical Issues Found

### 1. Dependency Issues
- **Missing `file` utility**: Line 204 in default.nix uses `file` command but not in dependencies
- **Docling package not integrated**: pythonEnv doesn't conditionally include docling

### 2. Implementation Bugs
- **Memory calculation bug** (line 254): Assumes 'G' suffix, fails for "512M" or "16384"
- **Python argument parsing**: Inconsistent boolean handling between shell and Python
- **Path resolution**: Python scripts may not resolve paths correctly at runtime

### 3. Incomplete Features
- **Chunking not implemented**: process_docling.py has stub code, doesn't actually chunk
- **No batch processing**: Can't process multiple files
- **No progress indication**: Long conversions have no feedback

## Architecture Review

### Strengths
- Clean separation of concerns (wrapper + processor scripts)
- Good memory management (WSL vs native Linux detection)
- Proper error handling and fallback mechanisms
- Comprehensive documentation

### Weaknesses
- Not truly pluggable (hardcoded engine list)
- No configuration persistence
- No caching or resume capability
- Missing validation of conversion quality

## Recommended Fixes

### Immediate (Before Release)
```nix
# Add to buildInputs in default.nix
buildInputs = [
  # ... existing inputs ...
  file  # Required for MIME type detection
];
```

```python
# Fix Python argument parsing
parser.add_argument("--verbose", action='store_true', help="Verbose output")
```

```bash
# Fix memory parsing to handle units
parse_memory_limit() {
  local mem="$1"
  if [[ "$mem" =~ ^([0-9]+)([KMG]?)$ ]]; then
    local value="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]:-G}"
    case "$unit" in
      K) echo $((value));;
      M) echo $((value * 1024));;
      G) echo $((value * 1024 * 1024));;
    esac
  fi
}
```

### Short-term
1. Complete docling chunking implementation
2. Add conditional docling package inclusion
3. Improve path handling in Python scripts
4. Add basic progress indication

### Long-term
1. Plugin architecture for processors
2. Configuration file support
3. Batch processing with glob patterns
4. Quality validation and testing suite

## Testing Plan

### When docling build completes:
1. Test docling Python import and basic functionality
2. Test tomd wrapper with both engines
3. Compare marker vs docling output quality
4. Benchmark performance and memory usage
5. Test chunking with large PDFs
6. Verify all file format support

### Test Cases Needed:
- Small text PDF (< 10 pages)
- Large text PDF (> 100 pages)
- Scanned PDF requiring OCR
- PDF with complex tables
- DOCX, PPTX, HTML files
- Images (PNG, JPG)
- Files with spaces in names
- Concurrent processing

## Next Steps

1. **Fix critical bugs** (file dependency, memory parsing, argument handling)
2. **Complete docling testing** once build finishes
3. **Implement chunking** properly in docling processor
4. **Create test suite** with sample documents
5. **Document limitations** clearly in README
6. **Consider upstream PR** for nlohmann_json issue

## Implementation Notes

### Working marker-pdf invocation:
```bash
nix run '.#marker-pdf' -- marker_single input.pdf output_dir
```

### Docling integration pattern:
```python
from docling.document_converter import DocumentConverter
converter = DocumentConverter()
result = converter.convert(str(doc_path))
markdown = result.document.export_to_markdown()
```

### Memory limits in WSL:
- ulimit -v works in WSL
- systemd-run doesn't enforce limits in WSL
- Need to detect WSL and use appropriate method

## PR Status
- **docling-parse PR #184**: Should be closed (approach is flawed)
- **nixpkgs fork**: Keep `docling-parse-fix` branch until upstream fixes nlohmann_json
- **Consider**: Upstream PR to nixpkgs to downgrade nlohmann_json to 3.11.3

## Files Modified
- `/home/tim/src/nixcfg/pkgs/tomd/default.nix` - Main package definition
- `/home/tim/src/nixcfg/pkgs/tomd/process_marker.py` - Marker processor
- `/home/tim/src/nixcfg/pkgs/tomd/process_docling.py` - Docling processor
- `/home/tim/src/nixcfg/docs/nlohmann-json-3.12-incompatibility.md` - Issue documentation
- `/home/tim/src/nixcfg/CLAUDE.md` - Project status update