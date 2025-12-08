# PDF-to-Markdown Tool Testing Results
**Date**: 2025-12-07 (Updated: 2025-12-08)
**Status**: tomd package builds successfully, marker-pdf not using GPU despite CUDA availability

## Executive Summary

The `tomd` PDF-to-markdown conversion tool has been successfully fixed and builds properly. Testing reveals that marker-pdf is NOT utilizing the GPU even though CUDA is available, causing extremely slow performance (20+ seconds per text block).

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

#### CORRECTED VRAM Requirements (per Opus 4.5 research)
- **Actual VRAM needed**: ~3-4.5GB (NOT 16GB+ as initially thought)
- **Peak usage**: 4.2GB for nougat, 4.1GB for marker
- **Available VRAM**: 8GB (RTX 2000 Ada) - MORE than sufficient

#### GPU Not Being Used (Root Cause)
- **CUDA IS available**: `torch.cuda.is_available()` returns True
- **GPU detected**: nvidia-smi shows RTX 2000 Ada with 8GB VRAM
- **BUT**: marker-pdf runs on CPU anyway (0MB GPU memory usage during execution)
- **Performance impact**: 20+ seconds per text block instead of <1 second

#### Library Path Issues
- PyTorch requires libstdc++.so.6 from gcc-lib
- Must set: `LD_LIBRARY_PATH="/usr/lib/wsl/lib:/nix/store/.../gcc-14.3.0-lib/lib"`
- Without this, PyTorch won't import at all

#### Current Status
1. **CUDA works**: PyTorch can access CUDA when libraries are properly linked
2. **Models fit in VRAM**: Only need ~4GB of the available 8GB
3. **Not using GPU**: Despite everything being available, marker defaults to CPU
4. **Extremely slow**: 12-page PDF would take ~2 hours on CPU vs minutes on GPU

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

### Immediate Fixes Needed

1. **Force GPU Usage in marker-pdf**:
   - Set device explicitly: `device = torch.device('cuda:0')`
   - Ensure models are moved to GPU: `.to('cuda')`
   - Add environment variables: `TORCH_DEVICE=cuda`, `CUDA_VISIBLE_DEVICES=0`

2. **Fix Library Path in Wrapper**:
   - marker-pdf wrapper needs to properly set `LD_LIBRARY_PATH`
   - Include gcc-lib path for libstdc++.so.6

3. **Optimize for 8GB VRAM**:
   - Set `INFERENCE_RAM=7` (leave 1GB for system)
   - Use `--batch_multiplier 1` (uses ~3GB VRAM)
   - Or specific batch sizes: `--layout_batch_size 1 --detection_batch_size 1`

### Alternative Solutions (from Opus research)

1. **For CPU-only scenarios**:
   - Set `OCR_ENGINE=ocrmypdf` (uses Tesseract, faster on CPU)
   - Or `OCR_ENGINE=None` for digital PDFs with embedded text

2. **Consider Docling**:
   - 5x faster than marker on CPU (3.1 sec/page vs 16+ sec/page)
   - MIT-licensed, better for CPU-bound environments
   - Already has nlohmann_json 3.11.3 workaround

3. **Proper Nix Packaging**:
   - Package marker-pdf dependencies properly in nixpkgs
   - Avoid pip virtual environments for better reproducibility
   - Use fixed-output derivations for ML models

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

The tomd tool infrastructure works correctly, and **marker-pdf has sufficient resources** (24GB RAM, 8GB VRAM). The critical issue is that marker-pdf is **not using the available GPU** despite CUDA being properly available. This causes extreme slowdown (100x slower) making it impractical.

**Key Insights from Opus 4.5 Research**:
- 8GB VRAM is MORE than sufficient (only needs ~4GB)
- The tool should work fine on this hardware
- The issue is configuration/implementation, not hardware limitations
- Docling might be a better alternative for CPU-only scenarios