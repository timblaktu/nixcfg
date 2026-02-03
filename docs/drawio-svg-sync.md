# Draw.io SVG Sync

Re-render `.drawio.svg` files when embedded XML is modified.

**Flake**: [github:timblaktu/drawio-svg-sync](https://github.com/timblaktu/drawio-svg-sync)

## Problem

When editing `.drawio.svg` files, the embedded `mxGraphModel` XML is the source of truth, but the visible SVG body becomes out of sync when XML is edited directly (e.g., by Claude Code).

## Quick Start (No Flake Changes)

```bash
# Render a single file
nix run 'github:timblaktu/drawio-svg-sync' -- docs/diagram.drawio.svg

# Render all .drawio.svg files recursively
nix run 'github:timblaktu/drawio-svg-sync' -- -a

# Dry run (show what would change)
nix run 'github:timblaktu/drawio-svg-sync' -- -d -a
```

## Adding to Your Flake

### 1. Add Input

```nix
# flake.nix
{
  inputs.drawio-svg-sync.url = "github:timblaktu/drawio-svg-sync";
}
```

### 2. Expose as App (Optional)

```nix
apps.${system}.drawio-svg-sync = inputs.drawio-svg-sync.apps.${system}.default;
```

Then: `nix run '.#drawio-svg-sync' -- path/to/file.drawio.svg`

### 3. Add to Dev Shell (Optional)

```nix
devShells.default = pkgs.mkShell {
  packages = [ inputs.drawio-svg-sync.packages.${system}.default ];
};
```

Then: `nix develop` and use `drawio-svg-sync` directly.

### 4. Allow Unfree (Required)

```nix
nixpkgs.config.allowUnfree = true;
```

## Workflow

1. **Edit XML**: Modify the embedded `mxGraphModel` in `.drawio.svg`
2. **Render**: `nix run 'github:timblaktu/drawio-svg-sync' -- path/to/file.drawio.svg`
3. **Verify**: View SVG in browser/editor
4. **Commit**: Stage both XML and rendered changes

## File Convention

- Extension: `.drawio.svg` (not `.svg` or `.drawio`)
- Source of truth: Embedded `mxGraphModel` XML
- Alternative edit method: Open in Draw.io desktop app

## Claude Code Integration

Use the **diagram skill** (`/diagram`) to create and edit diagrams directly in Claude Code. The skill handles:
- Choosing the right format (Mermaid vs DrawIO based on complexity)
- Compression format for embedded XML (URL encode → raw deflate → Base64)
- Rendering via drawio-svg-sync

### Example Workflow

```
User: Create a 3-tier architecture diagram
Claude: [Invokes diagram skill, creates .drawio.svg, renders]
```

## WSL2 Notes

Draw.io exports work in WSL2 despite GPU/Vulkan warning messages:
```
WARNING: dzn is not a conformant Vulkan implementation
ERROR: Exiting GPU process due to errors during initialization
```

These warnings are **cosmetic** - exports succeed regardless. The tool automatically uses:
- WSLg's native X11 when `DISPLAY` is available
- `xvfb-run` fallback for headless environments

## License Note

`drawio` has an unfree license (`asl20 unfreeRedistributable`).
