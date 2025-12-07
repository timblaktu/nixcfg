# CRITICAL CORRECTION: tomd Implementation Fix Required

## ⚠️ CRITICAL ISSUE IDENTIFIED (2025-12-06)

The current tomd implementation has **INCORRECTLY** made PyMuPDF4LLM the default/fallback processor. This violates explicit user requirements.

## ❌ WHAT WENT WRONG

1. **PyMuPDF4LLM was added as fallback** in `process_docling.py` (lines 24-29, 153-186)
2. **Silent fallback to PyMuPDF** when Docling unavailable (line 197)
3. **Testing was done with wrong engine** - all tests used PyMuPDF instead of marker-pdf
4. **Documentation created for wrong implementation** - describes PyMuPDF as "default"

## ✅ CORRECT ARCHITECTURE (User Requirements)

### Engine Priority:
1. **PRIMARY**: Docling (when available) - Superior structure extraction
2. **FALLBACK**: marker-pdf - Full-featured OCR and layout analysis
3. **NEVER USE**: PyMuPDF/PyMuPDF4LLM - Poor performance, explicitly rejected

### Why This Matters:
- **PyMuPDF**: Basic text extraction, poor formatting, no OCR, bad performance
- **marker-pdf**: ML-based, handles complex layouts, full OCR, production-ready
- **Docling**: Best structure preservation (blocked by build issues)

## 📋 REQUIRED FIXES

### 1. Remove ALL PyMuPDF References
- [ ] Delete PyMuPDF imports from `process_docling.py`
- [ ] Remove `process_with_pymupdf_fallback()` function entirely
- [ ] Remove pymupdf/pymupdf4llm from Python environment in `default.nix`
- [ ] Update all fallback logic to use marker-pdf instead

### 2. Fix Default Engine Logic
- [ ] Change `tomd` wrapper default from "docling" to "marker" until Docling available
- [ ] Update `determine_engine()` to return "marker" for all formats when Docling unavailable
- [ ] Remove misleading "docling" engine option until it actually works

### 3. Correct the Implementation
```python
# process_docling.py should be:
if not HAS_DOCLING:
    print("ERROR: Docling not available. Use --engine=marker instead.", file=sys.stderr)
    sys.exit(1)
# NO PYMUPDF FALLBACK!
```

### 4. Fix Documentation
- [ ] Update `docs/tools/tomd-usage-guide.md` - Remove all PyMuPDF references
- [ ] Clearly state marker-pdf is the ONLY working engine currently
- [ ] Remove incorrect "default" engine claims

### 5. Re-test Everything
- [ ] Test with marker-pdf as primary engine
- [ ] Verify OCR functionality works
- [ ] Confirm NO PyMuPDF code paths remain

## 🎯 CORRECT BEHAVIOR

### Current (Until Docling Fixed):
```bash
# This should use marker-pdf, NOT PyMuPDF
tomd document.pdf output.md

# Explicitly specify marker (redundant but clear)
tomd document.pdf output.md --engine=marker
```

### Future (When Docling Available):
```bash
# Auto-select best engine
tomd document.pdf output.md  # Uses Docling

# Force marker for OCR
tomd scanned.pdf output.md --engine=marker
```

## 📝 IMPLEMENTATION NOTES

### Why marker-pdf Only:
1. **It's working and tested** (see marker-pdf chunking implementation)
2. **Handles all document types** (PDF, images, with OCR)
3. **Production-ready** with memory management
4. **User explicitly approved** this approach

### What About Non-PDF Formats?
- **HTML/DOCX/PPTX**: Convert to PDF first, then use marker-pdf
- **Images**: marker-pdf handles directly with OCR
- **Alternative**: Fail cleanly with "Awaiting Docling support" message

## 🚨 INSTRUCTIONS FOR NEXT SESSION

1. **DO NOT USE PyMuPDF** - It was explicitly rejected for poor performance
2. **marker-pdf is the ONLY engine** until Docling is fixed
3. **Remove ALL PyMuPDF code** - It should not exist in the codebase
4. **Update all documentation** to reflect marker-pdf as primary
5. **Test with actual marker-pdf** not PyMuPDF fallback

## 📂 Files Requiring Changes

1. `/home/tim/src/nixcfg/pkgs/tomd/default.nix`
   - Remove pymupdf/pymupdf4llm from pythonEnv
   - Change default engine to "marker"
   - Update help text

2. `/home/tim/src/nixcfg/pkgs/tomd/process_docling.py`
   - Remove ALL PyMuPDF imports and functions
   - Make it error if Docling not available
   - OR rename to process_future_docling.py

3. `/home/tim/src/nixcfg/docs/tools/tomd-usage-guide.md`
   - Remove PyMuPDF4LLM sections
   - Update to show marker-pdf as primary
   - Fix incorrect claims about defaults

4. `/home/tim/src/nixcfg/CLAUDE.md`
   - Update to reflect correct implementation
   - Note that PyMuPDF was wrongly added
   - Clarify marker-pdf is the solution

## ✅ SUCCESS CRITERIA

1. `grep -r "pymupdf" pkgs/tomd/` returns NOTHING
2. `tomd test.pdf out.md` uses marker-pdf by default
3. Documentation accurately describes marker-pdf as primary engine
4. No misleading "fallback" behavior - explicit failures instead

## 💬 SAMPLE PROMPT FOR NEW SESSION

```
The tomd implementation has a critical error: it's using PyMuPDF4LLM as the default/fallback
processor, but this was explicitly rejected for poor performance. The correct implementation
should use ONLY marker-pdf until Docling is available.

Please fix the implementation by:
1. Removing ALL PyMuPDF/PyMuPDF4LLM code from tomd
2. Making marker-pdf the default and only engine
3. Updating documentation to reflect this
4. Re-testing with the correct marker-pdf engine

See /home/tim/src/nixcfg/docs/tomd-correction-prompt-2025-12-06.md for detailed requirements.

The user was very clear: PyMuPDF has poor performance and should NOT be used.
marker-pdf is the approved solution.
```

---

*Generated: 2025-12-06*
*Critical Issue: Wrong engine implementation*
*Required Action: Remove PyMuPDF, use marker-pdf only*