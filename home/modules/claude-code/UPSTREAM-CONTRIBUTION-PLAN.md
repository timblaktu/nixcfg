# Claude Code Enhanced: Upstream Contribution Plan

## Background

This document outlines the strategy for contributing features from `programs.claude-code-enhanced`
to the upstream `home-manager` module (`programs.claude-code`).

### Why We Renamed

The upstream home-manager repository added a `programs.claude-code` module that conflicts with our
custom implementation. Both modules:
- Use the same namespace (`programs.claude-code`)
- Have incompatible option types (e.g., `hooks` is a flat `attrsOf lines` upstream vs. structured categories here)
- Manage the same configuration files (`.claude/settings.json`, `.mcp.json`)

To avoid evaluation failures, we renamed our module to `programs.claude-code-enhanced`.

### Technical Analysis

**Upstream Module Features** (~7 features):
1. Package management with wrapper injection (`--mcp-config` flag)
2. Basic `settings.json` generation
3. Simple MCP server configuration
4. Flexible agent definitions
5. Flexible slash command definitions
6. Flexible skills definitions
7. Claude.md file management

**Our Enhanced Module Features** (~15 features):
1. Multi-account support (max, pro, default switching)
2. Categorized hooks (9 categories: formatting, security, linting, testing, git, logging, notifications, validation, custom)
3. 5 statusline styles (minimal, compact, powerline, emoji, nerd-font)
4. WSL integration (Windows path detection, cross-OS compatibility)
5. Session management shell functions
6. Pre-configured MCP server helpers (context7, sequential-thinking, nixos, serena, etc.)
7. Runtime directory management with `mkOutOfStoreSymlink`
8. Enterprise settings path support
9. Custom memory commands (`/nixmemory`, `/nixremember`)
10. Sub-agent definitions with structured templates
11. Slash command categories (documentation, security, refactoring, context)
12. Permission profiles (allow, deny, ask lists)
13. Environment variable injection
14. Debug mode propagation
15. Static commands mode (eliminates git churn)

## Contribution Strategy

### Phase 1: Immediate (Completed)
**Status**: DONE

- [x] Renamed module to `programs.claude-code-enhanced`
- [x] Updated all sub-modules and host configurations
- [x] Validated with `nix flake check`
- [x] Documented the architectural decision

### Phase 2: Short-term (Next 2-4 Weeks)
**Goal**: Prepare standalone features for upstream contribution

#### Priority 1: Statusline Styles
**Why first**: Self-contained, high-polish, no dependencies on other features.

**Files to contribute**:
- Statusline style implementations (bash scripts)
- Option definitions for `statusLine.style` enum
- Test coverage for each style

**PR Approach**:
```nix
# Proposed upstream addition
programs.claude-code.settings.statusLine = {
  type = "command";
  command = mkOption {
    type = types.str;
    default = "echo ''";
    description = "Command to generate statusline";
  };
};

programs.claude-code.statusline = {
  enable = mkEnableOption "Claude Code statusline";
  style = mkOption {
    type = types.enum [ "minimal" "compact" "powerline" "emoji" "nerd-font" ];
    default = "minimal";
    description = "Statusline style to use";
  };
};
```

**Estimated effort**: 8-12 hours including tests and documentation

#### Priority 2: Pre-configured MCP Server Helpers
**Why second**: Very useful, reduces boilerplate, easy to review.

**PR Approach**:
```nix
# Proposed upstream addition - extend existing mcpServers with helpers
programs.claude-code.mcpServers = {
  context7.enable = mkEnableOption "Context7 MCP server";
  sequentialThinking.enable = mkEnableOption "Sequential thinking MCP server";
  nixos.enable = mkEnableOption "NixOS search MCP server";
  # ... etc
};
```

**Estimated effort**: 4-6 hours

### Phase 3: Medium-term (1-2 Months)
**Goal**: Propose architectural changes for larger features

#### Priority 3: Categorized Hooks
**Challenge**: Upstream uses flat `attrsOf lines`, we use structured categories.

**Proposed solution**: Add optional structured hooks alongside flat hooks:
```nix
# Backward compatible addition
programs.claude-code.hooks = {
  # Existing flat hooks (upstream)
  PreToolUse = mkOption { type = types.listOf types.attrs; };
  PostToolUse = mkOption { type = types.listOf types.attrs; };

  # New: Structured hook categories (our addition)
  categories = {
    formatting.enable = mkEnableOption "formatting hooks";
    security.enable = mkEnableOption "security hooks";
    # ... etc
  };
};
```

**Estimated effort**: 16-24 hours

### Phase 4: Long-term (Next Quarter)
**Goal**: RFC/Discussion for architectural features

#### Priority 4: Multi-Account Support
**Challenge**: This is the most impactful but also most complex feature.

**Required upstream changes**:
1. Support multiple configuration directories
2. Account switching mechanism
3. Shell function integration

**Approach**: Open RFC discussion first, gauge community interest.

**RFC Topics**:
- Use cases for multi-account (work/personal, different API keys, etc.)
- Configuration directory structure
- Integration with shell environment

## Features to Keep Local (Not Worth Upstreaming)

These features are too opinionated or environment-specific:

1. **WSL wrapper complexity** - Too specific to our environment
2. **Enterprise settings path** - Niche use case
3. **Runtime directory management** - Depends on our nixcfg structure
4. **Session management shell functions** - Integration with our tmux setup
5. **Memory commands** - Specific to our Nix-managed workflow

## Migration Path for Users

If upstream accepts our contributions, users can migrate:

```nix
# From (current):
programs.claude-code-enhanced = {
  enable = true;
  statusline.style = "powerline";
  mcpServers.context7.enable = true;
};

# To (future, if accepted upstream):
programs.claude-code = {
  enable = true;
  statusline.style = "powerline";
  mcpServers.context7.enable = true;
};
```

## Timeline Summary

| Phase | Timeframe | Features | Status |
|-------|-----------|----------|--------|
| 1 | Done | Rename to `claude-code-enhanced` | Completed |
| 2 | 2-4 weeks | Statusline styles, MCP helpers | Pending |
| 3 | 1-2 months | Categorized hooks | Pending |
| 4 | Next quarter | Multi-account RFC | Pending |

## References

- **Upstream module**: `home-manager/modules/programs/claude-code.nix`
- **Our module**: `nixcfg/home/modules/claude-code.nix`
- **Analysis document**: `nixcfg/docs/claude-code-home-manager-program-analysis.md`
- **Home Manager Contributing Guide**: https://github.com/nix-community/home-manager/blob/master/CONTRIBUTING.md
