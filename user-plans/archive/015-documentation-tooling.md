# Plan 015: Documentation Tooling

**Status**: COMPLETE
**Created**: 2026-02-01
**Branch**: opencode

---

## Overview

Documentation infrastructure improvements for diagram generation, PDF conversion, and markdown tooling across projects.

---

## Tasks

| Task | Status | Description |
|------|--------|-------------|
| A1 | COMPLETE | Draw.io SVG sync automation |

---

## A1: Draw.io SVG Sync Automation

**Source**: Migrated from n3x Plan 019 C0a (2026-02-01)
**Completed**: 2026-02-01
**Standalone Flake**: [github:timblaktu/drawio-svg-sync](https://github.com/timblaktu/drawio-svg-sync)

### Problem

When editing `.drawio.svg` files, the embedded `mxGraphModel` XML is the source of truth, but the visible SVG body becomes out of sync when XML is edited directly (e.g., by Claude Code).

### Solution Implemented

**Package**: `drawio-headless` (unfree license: `asl20 unfreeRedistributable`)

**Files Modified**:
- `flake-modules/dev-shells.nix` - Added `drawio-headless` to dev shell and `drawio-render` app

### Usage

```bash
# Re-render a single file
nix run '.#drawio-render' -- docs/diagram.drawio.svg

# Re-render all .drawio.svg files recursively
nix run '.#drawio-render' -- -a

# Dry run (show what would be rendered)
nix run '.#drawio-render' -- -d -a

# In dev shell, drawio command is available directly
nix develop
drawio -x -f svg -o output.svg input.drawio.svg
```

### Workflow for Diagram Updates

1. **Edit XML**: Modify the embedded `mxGraphModel` XML in `.drawio.svg` (Claude Code or text editor)
2. **Render**: Run `nix run '.#drawio-render' -- path/to/diagram.drawio.svg`
3. **Verify**: View the SVG in browser/editor to confirm rendering
4. **Commit**: Stage both XML changes and rendered output

**Alternative (GUI)**: Open `.drawio.svg` directly in Draw.io desktop app

### Acceptance Criteria

- [x] `mxGraphModel` XML is authoritative source
- [x] SVG body can be regenerated deterministically from XML
- [x] Process is documented and scriptable
- [x] Works across projects (nixcfg, n3x, converix-hsw, etc.)

### Context from n3x

The n3x project decided to use `.drawio.svg` files exclusively for diagrams:
- **File extension**: Always `.drawio.svg` (not `.svg` or `.drawio` or `.drawio.png`)
- **Source of truth**: Embedded `mxGraphModel` XML within the SVG file
- **Edit method**: Modify the embedded XML directly (Claude Code) or open in Draw.io
- **Rendering**: SVG body should reflect the diagram (may be out of sync with XML temporarily)

### License Note

`drawio` has an unfree license (`asl20 unfreeRedistributable`). The nixcfg flake already has `allowUnfree = true` globally, so no additional configuration is needed.

---

## Cross-Repo Usage Guide

To use `drawio-svg-sync` in any Nix flake project:

### 1. Add Flake Input

```nix
# flake.nix
{
  inputs = {
    drawio-svg-sync.url = "github:timblaktu/drawio-svg-sync";
    # ... other inputs
  };
}
```

### 2. Expose as App (Optional)

```nix
# flake.nix outputs
apps.${system}.drawio-svg-sync = inputs.drawio-svg-sync.apps.${system}.default;
```

### 3. Add to Dev Shell (Optional)

```nix
# In your devShell packages
devShells.default = pkgs.mkShell {
  packages = [
    inputs.drawio-svg-sync.packages.${system}.default
  ];
};
```

### 4. Allow Unfree (Required)

```nix
# In your flake.nix or nixpkgs overlay
nixpkgs.config.allowUnfree = true;
# Or specific: nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "drawio" ];
```

### Usage After Integration

```bash
# Render single file (in-place update)
nix run '.#drawio-svg-sync' -- docs/architecture.drawio.svg

# Render all .drawio.svg files recursively
nix run '.#drawio-svg-sync' -- -a

# Dry run (show what would change)
nix run '.#drawio-svg-sync' -- -d -a

# Or run directly from github (no flake changes needed)
nix run 'github:timblaktu/drawio-svg-sync' -- docs/diagram.drawio.svg
```

### Claude Workflow Prompt

After editing `.drawio.svg` XML:
> Re-render the diagram: `nix run 'github:timblaktu/drawio-svg-sync' -- path/to/diagram.drawio.svg`

---

## Future: Mikrotik Skill Integration

This will eventually become part of a documentation skill. For now, Claude can:
1. Detect `.drawio.svg` files in the project
2. Edit the embedded `mxGraphModel` XML directly
3. Run `drawio-svg-sync` to regenerate the SVG body
4. Commit both XML and rendered changes together

---

## Related Work

- n3x Plan 019 C0: Diagram approach decision (chose .drawio.svg)
- PDF conversion tooling: `docs/pdf-conversion-overview-2024-12-05.md`
- [Draw.io CLI documentation](https://tomd.xyz/how-i-use-drawio/)
- [GitHub issue #1805 - SVG export discussion](https://github.com/jgraph/drawio-desktop/issues/1805)
