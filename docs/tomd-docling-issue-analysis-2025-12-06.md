# tomd Docling Integration Issue Analysis
**Date**: 2025-12-06
**Status**: Root cause identified, workaround proposed

## Executive Summary

The tomd universal document converter was designed to use both Docling (for structure extraction) and marker-pdf (for OCR) in an intelligent pipeline. However, Docling support got dropped due to a build failure in nixpkgs. This document analyzes the issue and proposes solutions.

## Problem Statement

**Original Vision**: tomd should leverage:
- **Docling**: Superior document structure analysis, DOCX/PPTX/HTML support, table extraction
- **marker-pdf**: Excellent OCR capabilities for scanned documents

**Current Reality**:
- Only marker-pdf is working
- Docling integration code exists but is non-functional
- Default engine hardcoded to "marker" instead of intelligent routing

## Root Cause Analysis

### 1. Build Failure in docling-parse

The core issue is that `docling-parse` (version 4.5.0) fails to build in nixpkgs:

```
error: Cannot build '/nix/store/2gnqw0n9w3y9ywa639bfqm5fa6vl24h3-python3.12-docling-parse-4.5.0.drv'
cmake --build /build/source/build --target=install -j 4
make: *** [Makefile:136: all] Error 2
```

This is a C++ compilation error in the cmake build step. The `docling-parse` package is a dependency of the main `docling` package, making it impossible to use Docling through nixpkgs.

### 2. Why This Matters

Without Docling, tomd loses:
- **Format Support**: No native DOCX, PPTX, HTML processing
- **Structure Analysis**: No intelligent document structure detection
- **Smart Chunking**: Falls back to dumb page-based splitting
- **Table Extraction**: Loses Docling's superior table recognition
- **Processing Speed**: Docling is 40% faster on clean PDFs (0.49 vs 0.86 sec/page)

### 3. Current Workarounds

The current implementation:
1. Removed Docling from pythonEnv dependencies
2. Changed default engine from "auto" to "marker"
3. Process scripts check for Docling import and error with message about build issues
4. All documents processed through marker-pdf regardless of type

## Proposed Solutions

### Solution 1: Hybrid venv Approach (Recommended)

Similar to how marker-pdf uses a venv for PyTorch/CUDA dependencies, we can:

1. **Install Docling via pip in a venv**
   - Bypass nixpkgs build issues
   - Use pre-built wheels from PyPI
   - Control versions independently

2. **Implementation Details**:
   - Create `docling-venv-setup` script
   - Install docling without docling-parse if needed
   - Fall back to basic PDF extraction libraries
   - See `default-with-docling.nix` for reference implementation

3. **Advantages**:
   - Works around nixpkgs build issues
   - Maintains separation between engines
   - Can update Docling independently

4. **Disadvantages**:
   - Not pure Nix (uses pip)
   - Requires first-time setup
   - May have version conflicts

### Solution 2: Fix docling-parse in nixpkgs

1. **Investigate the C++ build error**
   - Likely an API incompatibility with nlohmann_json
   - May need patches or different build flags
   - Could require upstream fix

2. **Submit PR to nixpkgs**
   - Once fixed, pure Nix solution works
   - Benefits entire Nix community

3. **Timeline**: Unknown, depends on complexity of fix

### Solution 3: Use docling-serve API

1. **Run Docling as a service**
   - `docling-serve` provides REST API
   - Can run in Docker or separate process
   - Avoids build issues entirely

2. **Implementation**:
   - Modify `process_docling_serve.py` to use API
   - Add service management to tomd wrapper

3. **Trade-offs**:
   - Requires running service
   - Network overhead
   - More complex deployment

### Solution 4: Alternative Libraries

Consider alternatives that don't have build issues:
- **pypandoc**: For DOCX/HTML conversion
- **python-pptx**: For PowerPoint processing
- **pdfplumber + pypdfium2**: Basic PDF extraction

These lack Docling's advanced features but work today.

## Recommendation

**Short-term** (Immediate):
1. Implement Solution 1 (hybrid venv approach)
2. Test with various document types
3. Document setup process clearly

**Medium-term** (1-2 weeks):
1. Investigate docling-parse build failure
2. Try different versions or patches
3. Submit fix to nixpkgs if possible

**Long-term** (1+ month):
1. Once nixpkgs fixed, migrate to pure Nix
2. Maintain venv approach as fallback
3. Consider docling-serve for production use

## Implementation Checklist

- [x] Identify root cause of Docling failure
- [x] Create hybrid venv solution (`default-with-docling.nix`)
- [ ] Test venv-based Docling installation
- [ ] Update process_docling.py for venv compatibility
- [ ] Add intelligent engine routing (auto mode)
- [ ] Test with DOCX, PPTX, HTML files
- [ ] Update documentation
- [ ] Consider submitting nixpkgs fix

## Testing Requirements

Once Docling is working, test:

1. **Format Support**:
   - PDF (clean and scanned)
   - DOCX (with tables and images)
   - PPTX (slides to sections)
   - HTML (with proper structure)

2. **Engine Selection**:
   - Auto-detection based on format
   - OCR detection for scanned PDFs
   - Manual override options

3. **Smart Chunking**:
   - Section-based splitting
   - TOC extraction
   - Fallback to page-based

4. **Performance**:
   - Compare speed: Docling vs marker-pdf
   - Memory usage with both engines
   - Quality of output

## Conclusion

The Docling integration is blocked by a nixpkgs build issue, not a fundamental incompatibility. The hybrid venv approach provides an immediate workaround while we work on a proper fix. This will restore tomd's intended functionality as a universal document converter with intelligent engine selection.

The priority should be getting Docling working through any means necessary, as it provides critical functionality that marker-pdf cannot replicate (DOCX/PPTX support, structure analysis, smart chunking).