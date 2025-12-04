# Fresh Session Prompt for tomd Implementation

## Context
I need to implement the `tomd` universal document-to-markdown converter based on the comprehensive design document at `docs/tomd-converter-design.md`. This refactors the existing `marker-pdf` package into a more general tool that leverages both Docling (for document structure) and marker-pdf (for OCR).

## Current State
- **Design Complete**: Full architecture documented in `docs/tomd-converter-design.md`
- **marker-pdf Working**: Memory controls, batch sizing, and WSL2 fixes all operational
- **Problem Identified**: Current `--auto-chunk` flag is misleading (no smart chunking)
- **Docling Available**: Version 2.47.1 in nixpkgs, ready to integrate

## Key Requirements
1. Create new `pkgs/tomd/` package that combines Docling and marker-pdf
2. Use Docling for document structure analysis and smart chunking
3. Route to appropriate engine based on document type
4. Support PDF, DOCX, PPTX, HTML, and images
5. Maintain backward compatibility with alias from `marker-pdf-env` to `tomd`

## First Task
Start implementing the tomd package structure in `pkgs/tomd/default.nix` following the architecture in the design document. Begin with:

1. Basic package structure with both docling and marker-pdf as dependencies
2. Simple routing logic (start with format detection)
3. CLI interface that accepts various document types
4. Test with a simple PDF to verify basic functionality

The existing marker-pdf wrapper at `pkgs/marker-pdf/default.nix` provides a good template for the wrapper script structure, but we'll be extending it significantly.

## Additional Context
- GPU: RTX 2000 Ada with 8GB VRAM
- Environment: WSL2 (consider ulimit vs systemd-run for memory limits)
- Branch: Work on branch `claude/tomd-implementation` (create from main)

Please start by creating the basic package structure and initial routing logic.