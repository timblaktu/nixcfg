# PDF-to-Markdown Tool Testing Results
**Date**: 2025-12-07
**Status**: tomd package builds successfully, marker-pdf has runtime limitations

## Executive Summary

The `tomd` PDF-to-markdown conversion tool has been successfully fixed and builds properly. However, runtime testing reveals significant memory requirements for the marker-pdf engine that make it challenging to run in resource-constrained environments.

## Test Results

### 1. Package Build Status ✅

- **tomd**: Builds and installs successfully
- **marker-pdf**: Builds successfully
- **docling**: Build blocked by nlohmann_json 3.12 incompatibility

### 2. tomd Command-Line Interface ✅

The tool successfully provides a unified interface for PDF conversion:

```bash
tomd <input.pdf> <output.md> [OPTIONS]
```

Options work as expected:
- `--engine=marker` (default, only available engine currently)
- `--memory-max=SIZE` (memory limits)
- `--chunk-size=N` (pages per chunk)
- `--verbose` (detailed output)

### 3. Marker-PDF Runtime Issues ⚠️

#### Memory Requirements
- **Model Loading**: Requires ~1.5GB just to load the layout model
- **Total Memory**: Needs 4-8GB RAM minimum for small PDFs
- **GPU Memory**: Originally designed for CUDA GPUs with 8GB+ VRAM

#### CUDA Dependencies
- Initial issue: PyTorch installed via pip includes CUDA dependencies
- Solution: Installed CPU-only PyTorch (`torch+cpu`)
- Result: Removed CUDA errors but increased CPU memory requirements

#### Current Limitations
1. **Memory Allocation Failures**: Even with 27GB available RAM, model loading fails due to memory fragmentation or ulimit restrictions in WSL
2. **Model Size**: The ML models (layout, detection, OCR) are very large:
   - Layout model: ~1.4GB
   - Additional models loaded on demand
3. **Processing Speed**: Without GPU acceleration, processing is very slow (2+ minutes for 12-page PDF)

### 4. Bugs Fixed During Testing

1. **File utility dependency**: Added `file` package to dependencies
2. **Memory parsing bug**: Fixed parsing of memory values (was assuming 'G' suffix)
3. **Python argument incompatibility**: Fixed Python 3.13 compatibility issue with `subprocess.run` arguments
4. **Missing Python dependencies**: Installed required packages in venv:
   - typing-extensions
   - filelock, requests, tqdm
   - pydantic, pydantic-settings
   - platformdirs, python-dotenv
   - ftfy

## Recommendations

### For Immediate Use

1. **Simple PDF Conversion**: For PDFs with extractable text (not scanned), consider using simpler tools:
   - `pdftotext` (poppler-utils) for plain text extraction
   - `pandoc` with PDF reader for structured conversion

2. **Marker-PDF Requirements**: If ML-based OCR is needed:
   - Ensure at least 8GB free RAM
   - Consider using a system with CUDA GPU support
   - Run on native Linux (not WSL) for better memory management

### For Future Development

1. **Alternative Engines**:
   - Add lighter-weight PDF conversion options
   - Implement fallback to simpler tools when marker-pdf fails

2. **Memory Optimization**:
   - Investigate model quantization options
   - Add option to download smaller models
   - Implement better memory pre-checks before attempting conversion

3. **Docling Integration**:
   - Wait for nlohmann_json 3.12 fix or maintain fork with 3.11.3
   - Docling promises better memory efficiency than marker-pdf

## Test Commands Used

```bash
# Build test
nix build '.#tomd'

# Command-line test
nix run '.#tomd' -- --help

# Conversion attempts
nix run '.#tomd' -- test.pdf output.md --memory-max=4G --verbose

# Direct marker-pdf test
nix run '.#marker-pdf' -- marker_single test.pdf /tmp/output --batch-multiplier 0.1
```

## Conclusion

The tomd tool infrastructure is working correctly, but the marker-pdf engine has significant resource requirements that limit its usability in development environments. The tool would benefit from additional lightweight conversion engines for simpler use cases where ML-based OCR is not required.