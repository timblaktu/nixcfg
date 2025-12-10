# Iterative Prompt for Docling-Parse Fix Work

Use this prompt ITERATIVELY in new Claude Code sessions after clearing context to continue the docling-parse fix work.

## THE PROMPT:

Continue working on the docling-parse nlohmann_json 3.12 compatibility fix.

Review:
- Project memory at CLAUDE.md section "PDF-to-Markdown Conversion Tools"
- Documentation: docs/docling-parse-bool-conversion-fix-2025-12-07.md
- Documentation: docs/docling-parse-nlohmann-json-fix.md
- Existing patch: pkgs/patches/docling-parse-nlohmann-json-3.12.patch

Current fork strategy:
1. Fork DS4SD/docling-parse to timblaktu/docling-parse (if not done)
2. Apply comprehensive bool conversion fixes to all affected files
3. Fork NixOS/nixpkgs to timblaktu/nixpkgs (if not done)
4. Override docling-parse in nixcfg to use our fork
5. Test the fix thoroughly
6. Submit PRs to both upstreams

All fork working trees should be in /home/tim/src/.

Check current status and proceed with next steps. Use gh CLI (authenticated as timblaktu).

## VARIATION PROMPTS (based on progress):

### If forks not created:
"Create the GitHub forks for docling-parse fix as documented in CLAUDE.md. Use gh CLI to fork DS4SD/docling-parse and set up working tree in /home/tim/src/."

### If working on C++ fixes:
"Continue applying the bool conversion fixes to docling-parse fork. The affected files are src/v2/qpdf/to_json.h, src/v2/pdf_resources/page_cell.h, and src/v2/pdf_sanitators/cells.h. Use the parse workaround documented in docs/docling-parse-bool-conversion-fix-2025-12-07.md."

### If testing the fix:
"Test the docling-parse fix by building it in nixpkgs. Override the docling-parse package to use github.com/timblaktu/docling-parse and verify it compiles with nlohmann_json 3.12.0."

### If preparing PRs:
"Prepare pull requests for both DS4SD/docling-parse and NixOS/nixpkgs. Document the nlohmann_json 3.12 compatibility issue and our solution."

## KEY PRINCIPLES:
- Work incrementally, commit often
- Test each change before proceeding
- Document findings in appropriate files
- Keep CLAUDE.md updated with progress
- All development in /home/tim/src/
- Use branch names: fix/nlohmann-json-3.12-bool-conversion