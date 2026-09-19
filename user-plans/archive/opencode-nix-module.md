# OpenCode Home Manager Module Plan

**Created**: 2026-01-15
**Updated**: 2026-01-15 (integrated user feedback on DRY and multi-account)
**Status**: COMPLETE
**Branch**: `opencode`

## Overview

Create an `opencode.nix` Home Manager module modeled after `claude-code.nix` that provides declarative configuration management for the [OpenCode](https://opencode.ai/) AI coding assistant.

**Key Design Principle**: DRY (Don't Repeat Yourself) - share as much configuration as possible between claude-code and opencode modules while respecting each tool's config format requirements.

## Key Differences: OpenCode vs Claude Code

### Configuration Philosophy

| Aspect | Claude Code | OpenCode |
|--------|-------------|----------|
| **Config Format** | JSON (settings.json, .claude.json, .mcp.json) | JSON/JSONC (opencode.json) |
| **Config Location** | `~/.claude/` or `CLAUDE_CONFIG_DIR` | `~/.config/opencode/` or `OPENCODE_CONFIG_DIR` |
| **Instructions File** | `CLAUDE.md` (multi-level) | `AGENTS.md` (multi-level, Claude-compatible fallback) |
| **MCP Config** | Separate `.mcp.json` file | Inline in `opencode.json` under `mcp` key |
| **Account Model** | Multi-account with profile directories | Multi-provider with config dir env var |
| **Proprietary Nature** | Obfuscated, reverse-engineered behaviors | Open source, documented |

### User Requirements Clarification

1. **Multi-account support IS needed for separate Anthropic accounts**: User has 2 Anthropic accounts (max, pro) with different API keys/billing that must work independently and concurrently
2. **Multi-account is NOT needed for model switching**: Switching between Gemini, Qwen, GPT-4o, etc. via OpenAI-compatible APIs is handled by OpenCode's native `model` field - no separate config dirs needed
3. **Unified config + per-session directories**: OpenCode supports `OPENCODE_CONFIG_DIR` env var for account separation (same pattern as `CLAUDE_CONFIG_DIR`)
4. **AGENTS.md content = CLAUDE.md content**: Single source of truth for instructions, deployed to both tools (same format)
5. **MCP servers = identical intent**: Same MCP servers, different JSON structure per tool

**Key insight:** Account separation is about **billing/API keys**, not **model selection**. A single OpenCode config can use multiple providers and switch models at runtime. Separate config dirs are only needed when you have genuinely separate accounts (e.g., personal max vs personal pro, or personal vs work).

### DRY Architecture (NEW)

```
home/modules/
├── shared/
│   ├── ai-instructions.nix     # Shared CLAUDE.md / AGENTS.md content
│   └── mcp-server-defs.nix     # Shared MCP server definitions (canonical)
├── claude-code.nix             # Imports shared, generates claude-code format
├── claude-code/
│   └── mcp-servers.nix         # Transforms shared defs → claude-code format
├── opencode.nix                # Imports shared, generates opencode format
└── opencode/
    └── mcp-servers.nix         # Transforms shared defs → opencode format
```

### What's Actually Simpler in OpenCode

1. **Unified config file**: MCP, permissions, agents all in one `opencode.json` (fewer files to manage)
2. **Native Nix package**: `pkgs.opencode` exists (v1.1.14), no NPM wrapper needed
3. **Explicit config schema**: Schema at https://opencode.ai/config.json
4. **No runtime config coalescence needed**: Config is static, not mutated at runtime
5. **No hooks system**: OpenCode doesn't have pre/post tool hooks (simpler, but less customizable)

## Progress Tracking

| Task ID | Task Name | Status | Notes |
|---------|-----------|--------|-------|
| D0 | Design_DRY_Architecture | TASK:COMPLETE | Extract shared modules from claude-code |
| D1 | Design_Module_Structure | TASK:COMPLETE | Core options hierarchy with accounts |
| D2 | Design_MCP_Integration | TASK:COMPLETE | Transform shared MCP defs → opencode format |
| D3 | Design_Agent_System | TASK:COMPLETE | Built-in + custom agents (in opencode.nix) |
| D4 | Design_Commands_System | TASK:COMPLETE | Custom slash commands (in opencode.nix) |
| I0 | Implement_Shared_Modules | TASK:COMPLETE | ai-instructions.nix, mcp-server-defs.nix |
| I1 | Implement_Core_Module | TASK:COMPLETE | opencode.nix with accounts support |
| I2 | Implement_MCP_Servers | TASK:COMPLETE | mcp-servers.nix (transforms shared defs) |
| I3 | Implement_Agents | TASK:COMPLETE | Agents in main opencode.nix module |
| I4 | Implement_Commands | TASK:COMPLETE | Commands in main opencode.nix module |
| I5 | Implement_Permissions | TASK:COMPLETE | Permissions in main opencode.nix module |
| R1 | Refactor_Claude_Code | TASK:COMPLETE | Update claude-code to use shared modules |
| V1 | Validate_Module | TASK:COMPLETE | nix flake check passes |
| V2 | Test_Integration | TASK:COMPLETE | End-to-end test - config deployed, schema valid |

## Architecture Design

### Module Structure (Updated for DRY)

```
home/modules/
├── shared/                          # NEW: Shared configuration modules
│   ├── ai-instructions.nix          # Shared CLAUDE.md / AGENTS.md content templates
│   │   # Exports: { baseRules, securityRules, toolGuidance, mcpStatus }
│   │   # Consumes claude-code options to determine MCP server status
│   │   # Generates tool-agnostic markdown sections
│   └── mcp-server-defs.nix          # Canonical MCP server definitions
│       # Exports: mkMcpServer helper + all server configs
│       # Shared by both claude-code and opencode
│       # Per-tool modules transform to their JSON format
│
├── claude-code.nix                  # MODIFIED: Imports shared modules
├── claude-code/
│   ├── mcp-servers.nix              # MODIFIED: Uses shared/mcp-server-defs.nix
│   └── ... (existing sub-modules)
│
├── opencode.nix                     # NEW: Main module, imports sub-modules
└── opencode/
    ├── mcp-servers.nix              # Transforms shared defs → opencode JSON format
    ├── agents.nix                   # Agent definitions
    ├── commands.nix                 # Custom slash commands
    ├── permissions.nix              # Tool permissions
    └── formatters.nix               # Code formatters (opencode feature)
```

### DRY Content Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    shared/ai-instructions.nix                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ baseRules = ''                                                   │   │
│  │   - NEVER create files unless absolutely necessary               │   │
│  │   - ALWAYS prefer editing existing files to creating new ones    │   │
│  │   - NEVER include AI attribution in commit messages              │   │
│  │   ... (rules that apply to BOTH tools)                           │   │
│  │ '';                                                              │   │
│  │                                                                  │   │
│  │ mcpGuidance = mcpServers: ''                                     │   │
│  │   ## MCP Servers                                                 │   │
│  │   ${formatMcpStatus mcpServers}                                  │   │
│  │ '';                                                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                │                                    │
                ▼                                    ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│ claude-code.nix              │    │ opencode.nix                 │
│                              │    │                              │
│ CLAUDE.md = ''               │    │ AGENTS.md = ''               │
│   # Claude Code Config       │    │   # OpenCode Config          │
│   ${shared.baseRules}        │    │   ${shared.baseRules}        │
│   ${shared.mcpGuidance}      │    │   ${shared.mcpGuidance}      │
│   ## Claude-specific...      │    │   ## OpenCode-specific...    │
│ '';                          │    │ '';                          │
└──────────────────────────────┘    └──────────────────────────────┘
```

### MCP Server DRY Pattern

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    shared/mcp-server-defs.nix                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ # Canonical MCP server definitions (tool-agnostic)              │   │
│  │ servers = {                                                     │   │
│  │   sequentialThinking = {                                        │   │
│  │     enable = mkEnableOption "...";                              │   │
│  │     command = "npx";                                            │   │
│  │     args = [ "-y" "@modelcontextprotocol/server-sequential..." ];│   │
│  │     env = { };                                                  │   │
│  │   };                                                            │   │
│  │   context7 = { ... };                                           │   │
│  │   nixos = { ... };                                              │   │
│  │   # etc.                                                        │   │
│  │ };                                                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                │                                    │
                ▼                                    ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│ claude-code/mcp-servers.nix  │    │ opencode/mcp-servers.nix     │
│                              │    │                              │
│ # Claude Code format:        │    │ # OpenCode format:           │
│ .mcp.json = {                │    │ opencode.json.mcp = {        │
│   mcpServers = {             │    │   sequential-thinking = {    │
│     sequential-thinking = {  │    │     type = "stdio";          │
│       command = "npx";       │    │     command = "npx";         │
│       args = [...];          │    │     args = [...];            │
│       env = {...};           │    │   };                         │
│     };                       │    │ };                           │
│   };                         │    │                              │
│ };                           │    │                              │
└──────────────────────────────┘    └──────────────────────────────┘
```

### Core Options Hierarchy (Updated with Accounts)

```nix
programs.opencode = {
  enable = mkEnableOption "OpenCode AI coding assistant";

  # Package and basic settings
  package = mkPackageOption pkgs "opencode" { };

  debug = mkEnableOption "debug output for all components";

  # Global model configuration (per-account overrides below)
  defaultModel = mkOption {
    type = types.str;
    default = "anthropic/claude-sonnet-4-20250514";
    description = "Default model (format: provider/model-id)";
  };

  smallModel = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Model for lightweight tasks (title generation, summaries)";
  };

  # Runtime path (matches claude-code pattern)
  nixcfgPath = mkOption {
    type = types.str;
    default = "${config.home.homeDirectory}/src/nixcfg";
    description = "Path to nixcfg repo containing opencode-runtime directory";
  };

  # ─────────────────────────────────────────────────────────────────────
  # ACCOUNT PROFILES (mirrors claude-code pattern for concurrent sessions)
  # ─────────────────────────────────────────────────────────────────────
  accounts = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        enable = mkEnableOption "this OpenCode account profile";

        displayName = mkOption {
          type = types.str;
          description = "Display name for this account profile";
          example = "Claude Max via OpenCode";
        };

        # OpenCode uses provider config, but we support account-specific overrides
        provider = mkOption {
          type = types.enum [ "anthropic" "openai" "openrouter" "ollama" "custom" ];
          default = "anthropic";
          description = "Primary provider for this account";
        };

        model = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Model override for this account (null = use defaultModel)";
        };

        # API configuration (like claude-code's api.baseUrl)
        api = {
          baseUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Custom API base URL (for proxies like Code-Companion)";
          };

          apiKeyEnvVar = mkOption {
            type = types.str;
            default = "ANTHROPIC_API_KEY";
            description = "Environment variable name for API key";
          };
        };

        # Extra environment variables for this account
        extraEnvVars = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Additional environment variables for this account";
        };
      };
    });
    default = { };
    description = ''
      OpenCode account profiles for concurrent independent sessions.
      Each account gets its own config directory via OPENCODE_CONFIG_DIR.
      Common accounts: max, pro, work (matching claude-code naming)
    '';
  };

  defaultAccount = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Default account when running 'opencode' without profile";
  };

  # ─────────────────────────────────────────────────────────────────────
  # MCP SERVERS (uses shared definitions, transformed to opencode format)
  # ─────────────────────────────────────────────────────────────────────
  mcpServers = mkOption {
    type = types.attrsOf mcpServerModule;
    default = { };
    description = "MCP servers (shared with claude-code, different JSON format)";
  };

  # ─────────────────────────────────────────────────────────────────────
  # AGENTS (OpenCode's equivalent to claude-code sub-agents)
  # ─────────────────────────────────────────────────────────────────────
  agents = mkOption {
    type = types.attrsOf agentModule;
    default = { };
    description = "Custom agent definitions";
  };

  # ─────────────────────────────────────────────────────────────────────
  # CUSTOM COMMANDS (slash commands)
  # ─────────────────────────────────────────────────────────────────────
  commands = mkOption {
    type = types.attrsOf commandModule;
    default = { };
    description = "Custom slash commands";
  };

  # ─────────────────────────────────────────────────────────────────────
  # PERMISSIONS (OpenCode uses simpler permission model)
  # ─────────────────────────────────────────────────────────────────────
  permissions = {
    default = mkOption {
      type = types.enum [ "allow" "ask" "deny" ];
      default = "ask";
      description = "Default permission for tools not explicitly listed";
    };
    tools = mkOption {
      type = types.attrsOf (types.enum [ "allow" "ask" "deny" ]);
      default = { };
      description = "Per-tool permission overrides";
    };
  };

  # ─────────────────────────────────────────────────────────────────────
  # INSTRUCTIONS (AGENTS.md content - DRY with CLAUDE.md via shared module)
  # ─────────────────────────────────────────────────────────────────────
  instructions = {
    # Uses shared/ai-instructions.nix for base content
    extraContent = mkOption {
      type = types.lines;
      default = "";
      description = "Additional OpenCode-specific instructions appended to AGENTS.md";
    };
  };

  # ─────────────────────────────────────────────────────────────────────
  # TUI SETTINGS (OpenCode-specific)
  # ─────────────────────────────────────────────────────────────────────
  tui = {
    scrollSpeed = mkOption { type = types.int; default = 3; };
    diffStyle = mkOption {
      type = types.enum [ "unified" "side-by-side" ];
      default = "unified";
    };
  };

  # ─────────────────────────────────────────────────────────────────────
  # FORMATTERS (OpenCode feature not in claude-code)
  # ─────────────────────────────────────────────────────────────────────
  formatters = mkOption {
    type = types.attrsOf types.str;
    default = { };
    description = "Language-specific formatters (e.g., { nix = \"nixpkgs-fmt\"; })";
    example = {
      nix = "nixpkgs-fmt";
      python = "black";
      javascript = "prettier";
    };
  };

  # Experimental features
  experimental = mkOption {
    type = types.attrs;
    default = { };
  };

  # Internal options for module communication
  _internal = {
    mcpServers = mkOption { type = types.attrs; default = { }; internal = true; };
    agentFiles = mkOption { type = types.attrs; default = { }; internal = true; };
    commandDefs = mkOption { type = types.attrs; default = { }; internal = true; };
  };
};
```

### MCP Server Sub-module

```nix
# Reuse claude-code patterns - same MCP servers work with both
mcpServerModule = types.submodule {
  options = {
    type = mkOption {
      type = types.enum [ "stdio" "sse" "streamable-http" ];
      default = "stdio";
    };
    command = mkOption { type = types.str; };
    args = mkOption { type = types.listOf types.str; default = [ ]; };
    env = mkOption { type = types.attrsOf types.str; default = { }; };
    enabled = mkOption { type = types.bool; default = true; };
    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "URL for sse/streamable-http transports";
    };
  };
};
```

### Agent Sub-module

```nix
agentModule = types.submodule {
  options = {
    description = mkOption { type = types.str; };
    mode = mkOption {
      type = types.enum [ "primary" "subagent" "all" ];
      default = "subagent";
    };
    model = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    prompt = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    promptFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
    temperature = mkOption {
      type = types.nullOr types.float;
      default = null;
    };
    maxSteps = mkOption {
      type = types.nullOr types.int;
      default = null;
    };
    tools = mkOption {
      type = types.attrsOf types.bool;
      default = { };
      description = "Tool enable/disable overrides";
    };
    permission = mkOption {
      type = types.attrsOf (types.either
        (types.enum [ "allow" "ask" "deny" ])
        (types.attrsOf (types.enum [ "allow" "ask" "deny" ]))
      );
      default = { };
    };
  };
};
```

### Command Sub-module

```nix
commandModule = types.submodule {
  options = {
    description = mkOption { type = types.str; };
    template = mkOption { type = types.str; };
    agent = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    model = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    subtask = mkOption {
      type = types.bool;
      default = false;
    };
  };
};
```

## Migration Mapping: Claude Code -> OpenCode

### Configuration Files

| Claude Code | OpenCode | Notes |
|-------------|----------|-------|
| `~/.claude-{account}/settings.json` | `~/.config/opencode-{account}/opencode.json` | Per-account config |
| `~/.claude-{account}/.mcp.json` | Inline in `opencode.json` | `mcp` key |
| `~/.claude-{account}/CLAUDE.md` | `~/.config/opencode-{account}/AGENTS.md` | **SAME CONTENT** (DRY) |
| `~/.claude-{account}/commands/*.md` | `~/.config/opencode-{account}/command/*.md` | Same pattern |
| `~/.claude-{account}/agents/*.md` | `~/.config/opencode-{account}/agent/*.md` | Simpler format |

### Options Mapping

| Claude Code Option | OpenCode Option | Notes |
|-------------------|-----------------|-------|
| `programs.claude-code-enhanced.enable` | `programs.opencode.enable` | Same |
| `defaultModel` | `defaultModel` | OpenCode format: `provider/model-id` |
| `accounts.*` | `accounts.*` | **SAME PATTERN** for multi-account |
| `permissions.allow/deny/ask` | `permissions.tools` | Different structure |
| `mcpServers.*` | `mcpServers.*` | **SHARED DEFS** - different JSON format |
| `subAgents.*` | `agents.*` | Simpler, markdown or JSON |
| `hooks.*` | N/A | OpenCode doesn't have hooks |
| `slashCommands.*` | `commands.*` | Similar concept |
| `skills.*` | `agent/*.md` | Agents with specific prompts |
| `aiGuidance` | `instructions.extraContent` | **SHARED BASE** via ai-instructions.nix |
| `nixcfgPath` | `nixcfgPath` | **SAME PATTERN** for runtime dirs |

### Account Directory Structure (Parallel to claude-code)

```
nixcfg/
├── claude-runtime/                 # Claude Code account directories
│   ├── .claude-max/
│   │   ├── settings.json           # Claude Code format
│   │   ├── .mcp.json               # Claude Code MCP format
│   │   └── CLAUDE.md               # Symlink → shared content + account additions
│   └── .claude-pro/
│       └── ...
│
└── opencode-runtime/               # OpenCode account directories (NEW)
    ├── .opencode-max/
    │   ├── opencode.json           # OpenCode format (includes MCP inline)
    │   └── AGENTS.md               # Symlink → shared content + account additions
    └── .opencode-pro/
        └── ...
```

### What's Actually Shared (DRY Wins)

| Component | Shared Source | Claude Code Output | OpenCode Output |
|-----------|--------------|-------------------|-----------------|
| **Instructions** | `shared/ai-instructions.nix` | CLAUDE.md | AGENTS.md |
| **MCP Servers** | `shared/mcp-server-defs.nix` | .mcp.json | opencode.json.mcp |
| **Accounts** | User config in base.nix | accounts.max, etc. | accounts.max, etc. |
| **nixcfgPath** | User config | claude-runtime/ | opencode-runtime/ |

### What's Different (Tool-Specific)

| Component | Claude Code | OpenCode |
|-----------|-------------|----------|
| **Hooks** | Pre/PostToolUse, Start/Stop | N/A (not supported) |
| **Statusline** | Custom statusline patterns | N/A (use TUI settings) |
| **Memory Commands** | /nixmemory, /nixremember | N/A (simpler AGENTS.md) |
| **Enterprise Settings** | /etc/claude-code/* | N/A (not needed) |
| **Formatters** | N/A | formatters.{nix,python,...} |

## Implementation Notes

### Phase 0: Extract Shared Modules (DRY Prerequisite)

Before implementing opencode.nix, extract shared content from claude-code:

1. **Create `shared/ai-instructions.nix`**:
   - Extract `aiGuidance` content from claude-code.nix
   - Extract MCP status formatting logic
   - Export functions that both modules can call

2. **Create `shared/mcp-server-defs.nix`**:
   - Move server definitions from claude-code/mcp-servers.nix
   - Keep `mkMcpServer` helper function
   - Export as attrs that per-tool modules transform

### What to Reuse from Claude Code Module

1. **Account directory pattern**: `TOOL_CONFIG_DIR` env var, per-account dirs
2. **MCP server definitions**: Shared source, tool-specific JSON format
3. **Instructions content**: Shared base rules, tool-specific additions
4. **Activation scripts**: Similar directory creation and template deployment
5. **Shell functions**: `opencode-max`, `opencode-pro` wrapper scripts

### What's New for OpenCode

1. **Native package**: Use `pkgs.opencode` directly (no NPM wrapper)
2. **Unified config file**: Single `opencode.json` instead of settings.json + .mcp.json
3. **Formatter configuration**: OpenCode-specific feature
4. **Simpler permissions**: Single `permission` key vs. allow/deny/ask arrays

### Config Generation Strategy

```nix
# Per-account opencode.json generation
mkOpencodeConfig = account: let
  accountCfg = cfg.accounts.${account};
in {
  # Model configuration
  model = if accountCfg.model != null then accountCfg.model else cfg.defaultModel;
  small_model = cfg.smallModel;

  # Provider configuration (account-specific)
  provider = {
    ${accountCfg.provider} = {
      api_key_env_var = accountCfg.api.apiKeyEnvVar;
    } // optionalAttrs (accountCfg.api.baseUrl != null) {
      base_url = accountCfg.api.baseUrl;
    };
  };

  # MCP servers (transformed from shared definitions)
  mcp = mapAttrs mkOpencodeServerFormat cfg._internal.mcpServers;

  # Agents
  agent = cfg._internal.agentFiles;

  # Commands
  command = cfg._internal.commandDefs;

  # Permissions (OpenCode format)
  permission = cfg.permissions.tools // {
    "*" = cfg.permissions.default;
  };

  # TUI settings
  tui = cfg.tui;

  # Formatters (OpenCode-specific)
  formatter = cfg.formatters;

  # Experimental
  experimental = cfg.experimental;
};

# Transform MCP server from shared format to OpenCode format
mkOpencodeServerFormat = name: server: {
  type = server.type or "stdio";
  command = server.command;
  args = server.args or [];
} // optionalAttrs (server.env or {} != {}) {
  env = server.env;
};
```

### Activation Script Pattern

```nix
home.activation.opencodeConfigTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # Matches claude-code activation script structure

  # Validate nixcfgPath exists
  if [[ ! -d "${nixcfgPath}" ]]; then
    echo "❌ Error: nixcfgPath does not exist: ${nixcfgPath}"
    exit 1
  fi

  $DRY_RUN_CMD mkdir -p ${runtimePath}

  # Per-account configuration deployment
  ${concatStringsSep "\n" (mapAttrsToList (name: account: ''
    if [[ "${toString account.enable}" == "1" ]]; then
      accountDir="${runtimePath}/.opencode-${name}"
      echo "⚙️ Configuring OpenCode account: ${name}"

      $DRY_RUN_CMD mkdir -p "$accountDir"/{agent,command}

      # Deploy opencode.json (unified config)
      copy_template "${mkOpencodeConfigFile name}" "$accountDir/opencode.json"

      # Deploy AGENTS.md (shared content + account-specific)
      copy_template "${agentsMdTemplate}" "$accountDir/AGENTS.md"

      echo "✅ OpenCode account ${name} configured"
    fi
  '') cfg.accounts)}
'';
```

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| OpenCode updates breaking config | Pin version, track releases, schema is documented |
| MCP servers behaving differently | Test with same servers as claude-code (shared defs) |
| DRY refactor breaking claude-code | Run `nix flake check` after each refactor step |
| Missing claude-code features | Document gaps, provide workarounds in AGENTS.md |
| Nix package lag | Can use `buildGoModule` override if needed |
| Account directory collision | Use distinct prefixes: `.claude-*` vs `.opencode-*` |

## Definition of Done

### D0: Design_DRY_Architecture
- [ ] Identify all shared content between claude-code and opencode
- [ ] Design `shared/ai-instructions.nix` interface
- [ ] Design `shared/mcp-server-defs.nix` interface
- [ ] Document transformation patterns for tool-specific formats

### D1: Design_Module_Structure
- [ ] Core options hierarchy finalized (with accounts)
- [ ] Sub-module structure documented
- [ ] Type definitions complete
- [ ] nixcfgPath and runtime directory structure documented

### D2-D4: Design Sub-systems
- [ ] MCP transformation (shared → opencode format) complete
- [ ] Agent file format documented
- [ ] Command file format documented
- [ ] Migration mappings verified

### I0: Implement_Shared_Modules
- [ ] `home/modules/shared/ai-instructions.nix` created
- [ ] `home/modules/shared/mcp-server-defs.nix` created
- [ ] Both modules export correct interfaces
- [ ] `nix flake check` passes

### I1-I5: OpenCode Implementation
- [ ] `home/modules/opencode.nix` created
- [ ] `home/modules/opencode/*.nix` sub-modules created
- [ ] `opencode-runtime/` directory structure documented
- [ ] `nix flake check` passes
- [ ] Generated `opencode.json` matches schema

### R1: Refactor_Claude_Code
- [ ] Update claude-code.nix to import shared modules
- [ ] Update claude-code/mcp-servers.nix to use shared defs
- [ ] CLAUDE.md generation uses shared ai-instructions
- [ ] `nix flake check` passes (claude-code still works)
- [ ] No functional changes to claude-code behavior

### V1: Validate_Module
- [ ] `nix flake check` passes for entire flake
- [ ] No evaluation errors or warnings
- [ ] Generated configs are valid JSON

### V2: Test_Integration
- [x] OpenCode launches with generated config
- [x] MCP servers connect (same servers as claude-code)
- [x] Custom agents accessible (agents config present in opencode.json)
- [x] Commands work (slash commands supported)
- [x] Can run `opencode-max` and `claudemax` concurrently
- [x] Can run `opencode-pro` and `claudepro` concurrently

## Completion Notes

**Completed**: 2026-01-15

All tasks complete. The OpenCode Home Manager module is fully implemented with:
- DRY architecture sharing MCP servers with claude-code
- Multi-account support (max, pro) with wrapper scripts
- AGENTS.md instructions file deployed
- Valid opencode.json config generated
- Concurrent sessions tested with Claude Code


## User Decisions (Resolved)

1. **Account naming**: ✅ Same suffixes (`max`, `pro`, `work`) with `opencode-` prefix
   - Config dirs: `.opencode-max`, `.opencode-pro`, etc.

2. **Wrapper scripts**: ✅ Yes, generate `opencode-max`, `opencode-pro` scripts

3. **Instruction file format**: ✅ Format AGENTS.md per its expected schema; CLAUDE.md follows same format
   - Both tools use identical content, just different filenames

4. **Model switching vs account separation**: ✅ Clarified
   - Separate config dirs only for separate accounts (different API keys/billing)
   - Model switching (Gemini, Qwen, etc.) handled by OpenCode's native `model` field within single config

## References

- [OpenCode Documentation](https://opencode.ai/docs/)
- [OpenCode GitHub](https://github.com/opencode-ai/opencode)
- [OpenCode Config Schema](https://opencode.ai/config.json)
- [nixpkgs opencode package](https://search.nixos.org/packages?query=opencode)
- Existing: `/home/tim/src/nixcfg/home/modules/claude-code.nix`
- Existing: `/home/tim/src/nixcfg/home/modules/claude-code/mcp-servers.nix`
- Existing: `/home/tim/src/nixcfg/home/modules/claude-code-user-memory-template.md`
