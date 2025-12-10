# Next Session Prompt for tomd Pipeline Work

## Context Summary
Continue working on PDF-to-markdown conversion pipeline (tomd). Previous session completed comprehensive code review while waiting for docling build to complete. Found critical bugs and architectural issues that need fixing before the pipeline is production-ready.

## Current State
- **Branch**: `claude/review-pa161878-01BN7oP9qR4p8N6a9YZZufa8` (or whatever branch you're on)
- **nixpkgs fork**: Using `docling-parse-fix` branch with nlohmann_json 3.11.3 downgrade (commit 259687eb0)
- **Build Status**: docling package likely still building or completed - check with `nix build '.#docling' --print-build-logs`

## Critical Bugs to Fix FIRST

### 1. Add missing file utility dependency
```nix
# In pkgs/tomd/default.nix, add to buildInputs:
file  # Required for MIME type detection
```

### 2. Fix memory parsing bug (line 254)
Current code assumes 'G' suffix, need to handle M, K, or no suffix:
```bash
# Replace line 254 with proper unit parsing
local memory_limit_kb
case "${MEMORY_MAX}" in
  *G) memory_limit_kb=$(( ${MEMORY_MAX%G} * 1024 * 1024 ));;
  *M) memory_limit_kb=$(( ${MEMORY_MAX%M} * 1024 ));;
  *K) memory_limit_kb=${MEMORY_MAX%K};;
  *)  memory_limit_kb=$(( ${MEMORY_MAX} * 1024 * 1024 ));;  # Assume GB if no unit
esac
```

### 3. Fix Python argument inconsistency
In both `process_marker.py` and `process_docling.py`:
```python
# Change from:
parser.add_argument("--verbose", type=lambda x: x.lower() == 'true', default=False)
# To:
parser.add_argument("--verbose", action='store_true')
```

## Testing Tasks (if docling build completed)

1. **Test docling import**:
```bash
nix run '.#docling' -- python3 -c "from docling.document_converter import DocumentConverter; print('✅ Docling works')"
```

2. **Test tomd with both engines**:
```bash
# Test with marker-pdf
nix run '.#tomd' -- test.pdf test_marker.md --engine=marker --verbose

# Test with docling (if available)
nix run '.#tomd' -- test.pdf test_docling.md --engine=docling --verbose
```

3. **Compare outputs**:
```bash
diff -u test_marker.md test_docling.md
```

## Next Priority Tasks

1. **Fix the critical bugs** listed above
2. **Complete docling chunking** - Currently stubbed out in `process_docling.py` lines 252-254
3. **Add docling to pythonEnv** conditionally when available
4. **Create test suite** with sample documents of various types
5. **Benchmark performance** between marker and docling

## Key Files to Review
- `/home/tim/src/nixcfg/pkgs/tomd/default.nix` - Main package with bugs
- `/home/tim/src/nixcfg/pkgs/tomd/process_docling.py` - Incomplete chunking
- `/home/tim/src/nixcfg/pkgs/tomd/process_marker.py` - Working but needs arg fix
- `/home/tim/src/nixcfg/docs/tomd-review-findings-2025-12-07.md` - Complete review findings
- `/home/tim/src/nixcfg/docs/nlohmann-json-3.12-incompatibility.md` - Root cause of docling issues

## Architecture Decisions Needed
1. Should we make processors true plugins?
2. Should we add configuration file support?
3. Should we implement caching for processed chunks?
4. Should we support pipeline composition (marker→docling)?

## Remember
- marker-pdf is WORKING but slow with OCR
- docling BUILDS but needs runtime testing
- tomd has BUGS that must be fixed before use
- The nlohmann_json downgrade is temporary until upstream fixes their SAX parser

## Command to Start
```bash
cd /home/tim/src/nixcfg
git status  # Check current branch
nix build '.#docling' --print-build-logs | tail -20  # Check if build completed
```

Then fix the critical bugs in order before proceeding with testing.