# Claude Code Multi-Backend & Termux Integration Plan

## Overview

Integrate work's Code-Companion proxy as a new Claude Code "account" alongside existing personal accounts (max, pro), with unified configuration across all platforms including Termux.

**Key Design Decision**: Generate Termux configuration as Nix package outputs - no nix-on-droid required. Single source of truth, simple installation.

## Progress Tracking

### Phase 1: Research & Design (Autonomous - No Nix Required)

| Task | Name | Status | Date |
|------|------|--------|------|
| R1 | Document current account submodule structure | TASK:PENDING | |
| R2 | Document wrapper script generation across platforms | TASK:PENDING | |
| R3 | Document run-tasks.sh for Nix module adaptation | TASK:PENDING | |
| R4 | Document skills structure for Nix module adaptation | TASK:PENDING | |
| R5 | Draft complete API options Nix code | TASK:PENDING | |
| R6 | Draft complete wrapper script Nix code | TASK:PENDING | |

### Phase 2: Implementation (Requires Nix Host)

| Task | Name | Status | Date |
|------|------|--------|------|
| I1 | Implement API options in account submodule | TASK:PENDING | |
| I2 | Implement wrapper script generation | TASK:PENDING | |
| I3 | Add work account configuration | TASK:PENDING | |
| I4 | Create Termux package output | TASK:PENDING | |
| I5 | Store secrets in Bitwarden | TASK:PENDING | |
| I6 | Test on Nix-managed host | TASK:PENDING | |
| I7 | Test Termux installation | TASK:PENDING | |
| I8 | Add task automation to Nix module | TASK:PENDING | |
| I9 | Add skills support to Nix module | TASK:PENDING | |

---

## Phase 1: Research Task Definitions

### Task R1: Document current account submodule structure

**Goal**: Read and document the current account submodule in `home/modules/claude-code.nix` to understand what exists and what needs to be added.

**Actions**:
1. Read `home/modules/claude-code.nix` lines 140-200 (account submodule definition)
2. Read `home/modules/base.nix` to find current account usage (search for "accounts")
3. Document the current structure in findings section below
4. Identify gaps vs. requirements in Code-Companion Requirements section

**Output**: Document current state in "R1 Findings" section below.

**Definition of Done** (ALL must be true):
- [ ] R1 Findings section contains "Current Options" subsection listing each existing option with its type
- [ ] R1 Findings section contains "Current Usage" subsection showing how accounts are defined in base.nix
- [ ] R1 Findings section contains "Gaps Analysis" subsection listing what's missing for Code-Companion
- [ ] R1 Findings placeholder text `*(Task R1 will populate this section)*` is replaced

---

### Task R2: Document wrapper script generation across platforms

**Goal**: Read all platform-specific wrapper script generation code and document the pattern.

**Actions**:
1. Read `home/migration/wsl-home-files.nix` - search for "mkClaudeWrapperScript" or wrapper generation
2. Read `home/migration/linux-home-files.nix` - same search
3. Read `home/migration/darwin-home-files.nix` - same search
4. Document how wrappers are generated, what they set, common patterns
5. Note where the wrapper function should be refactored to avoid duplication

**Output**: Document findings in "R2 Findings" section below.

**Definition of Done** (ALL must be true):
- [ ] R2 Findings contains "Platform Files" subsection listing each platform file and line numbers where wrappers are defined
- [ ] R2 Findings contains "Common Pattern" subsection with the actual Nix code pattern used (or noting differences)
- [ ] R2 Findings contains "Environment Variables Set" subsection listing all env vars currently set by wrappers
- [ ] R2 Findings contains "Refactoring Recommendation" subsection identifying duplication and where to extract shared code
- [ ] R2 Findings placeholder text `*(Task R2 will populate this section)*` is replaced

---

### Task R3: Document run-tasks.sh for Nix module adaptation

**Goal**: Document the run-tasks.sh script in enough detail to generate it from Nix.

**Actions**:
1. Read `~/bin/run-tasks.sh` completely
2. Document all features, options, and dependencies (rg, claude, etc.)
3. Identify any hardcoded paths that need parameterization
4. Read `~/.claude/commands/next-task.md` for slash command format
5. Document what files need to be generated and their content

**Output**: Document in "R3 Findings" section below.

**Definition of Done** (ALL must be true):
- [ ] R3 Findings contains "CLI Options" subsection listing all command-line options with descriptions
- [ ] R3 Findings contains "Dependencies" subsection listing required tools (rg, claude, etc.)
- [ ] R3 Findings contains "Hardcoded Values" subsection listing any paths/values that need parameterization
- [ ] R3 Findings contains "Slash Command Format" subsection with the content of next-task.md
- [ ] R3 Findings contains "Safety Limits" subsection documenting MAX_ITERATIONS, rate limit handling, etc.
- [ ] R3 Findings placeholder text `*(Task R3 will populate this section)*` is replaced

---

### Task R4: Document skills structure for Nix module adaptation

**Goal**: Document the skills directory structure for Nix module generation.

**Actions**:
1. List `~/.claude/skills/` directory structure
2. Read SKILL.md file(s) to understand format
3. Read any REFERENCE.md or supporting files
4. Document the expected directory structure and file formats
5. Identify which skills should be "built-in" vs user-defined

**Output**: Document in "R4 Findings" section below.

**Definition of Done** (ALL must be true):
- [ ] R4 Findings contains "Directory Structure" subsection showing the file tree of ~/.claude/skills/
- [ ] R4 Findings contains "SKILL.md Format" subsection with an example or template of the format
- [ ] R4 Findings contains "Supporting Files" subsection listing other files (REFERENCE.md, etc.) and their purpose
- [ ] R4 Findings contains "Built-in Skills" subsection listing which skills should ship with the Nix module
- [ ] R4 Findings placeholder text `*(Task R4 will populate this section)*` is replaced

---

### Task R5: Draft complete API options Nix code

**Goal**: Write the complete, copy-paste ready Nix code for the API options extension.

**Prerequisite**: R1 must be TASK:COMPLETE before starting this task.

**Actions**:
1. Using R1 findings, draft the complete new options block
2. Include all options from the plan: api.baseUrl, api.authMethod, api.disableApiKey, api.modelMappings
3. Include secrets.bearerToken with Bitwarden reference structure
4. Include extraEnvVars option
5. Format as valid Nix code ready to insert

**Output**: Complete Nix code block in "R5 Draft Code" section below.

**Definition of Done** (ALL must be true):
- [ ] R5 Draft Code contains a complete `accounts = mkOption { ... }` block in valid Nix syntax
- [ ] R5 Draft Code includes `api.baseUrl` option with type `types.nullOr types.str`
- [ ] R5 Draft Code includes `api.authMethod` option with type `types.enum [ "api-key" "bearer" "bedrock" ]`
- [ ] R5 Draft Code includes `api.disableApiKey` option with type `types.bool`
- [ ] R5 Draft Code includes `api.modelMappings` option with type `types.attrsOf types.str`
- [ ] R5 Draft Code includes `secrets.bearerToken.bitwarden` submodule with `item` and `field` options
- [ ] R5 Draft Code includes `extraEnvVars` option with type `types.attrsOf types.str`
- [ ] R5 Draft Code placeholder text `*(Task R5 will populate this section)*` is replaced

---

### Task R6: Draft complete wrapper script Nix code

**Goal**: Write the complete, copy-paste ready Nix code for wrapper script generation.

**Prerequisite**: R2 must be TASK:COMPLETE before starting this task.

**Actions**:
1. Using R2 findings, draft the updated mkClaudeWrapperScript function
2. Handle all API options (baseUrl, authMethod, modelMappings)
3. Handle secrets retrieval via rbw
4. Handle extraEnvVars
5. Design as a shared function to be used across all platform files
6. Format as valid Nix code

**Output**: Complete Nix code block in "R6 Draft Code" section below.

**Definition of Done** (ALL must be true):
- [ ] R6 Draft Code contains a complete `mkClaudeWrapperScript` function in valid Nix syntax
- [ ] R6 Draft Code handles `api.baseUrl` by conditionally setting ANTHROPIC_BASE_URL
- [ ] R6 Draft Code handles `api.authMethod == "bearer"` by retrieving token via rbw
- [ ] R6 Draft Code handles `api.disableApiKey` by conditionally setting ANTHROPIC_API_KEY=""
- [ ] R6 Draft Code handles `api.modelMappings` by setting ANTHROPIC_DEFAULT_*_MODEL env vars
- [ ] R6 Draft Code handles `extraEnvVars` by iterating and exporting each
- [ ] R6 Draft Code includes comment indicating where to place this shared function
- [ ] R6 Draft Code placeholder text `*(Task R6 will populate this section)*` is replaced

---

## Phase 1 Findings

### R1 Findings

*(Task R1 will populate this section)*

---

### R2 Findings

*(Task R2 will populate this section)*

---

### R3 Findings

*(Task R3 will populate this section)*

---

### R4 Findings

*(Task R4 will populate this section)*

---

### R5 Draft Code

*(Task R5 will populate this section)*

---

### R6 Draft Code

*(Task R6 will populate this section)*

---

## Code-Companion Requirements

Environment variables required for work proxy:

```bash
ANTHROPIC_BASE_URL="https://codecompanionv2.d-dp.nextcloud.aero"
ANTHROPIC_AUTH_TOKEN="<bearer_token>"  # Secret - stored in Bitwarden
ANTHROPIC_API_KEY=""                    # Must be explicitly empty
ANTHROPIC_DEFAULT_SONNET_MODEL="devstral"
ANTHROPIC_DEFAULT_OPUS_MODEL="devstral"
ANTHROPIC_DEFAULT_HAIKU_MODEL="qwen-a3b"
```

**VPN Requirement**: Code-Companion endpoint requires work VPN access.

---

## Phase 2: Implementation Task Definitions

### Task I1: Implement API options in account submodule

**File**: `home/modules/claude-code.nix`

**Location**: Lines 143-163 (current account submodule)

**Changes**: Add new options to the account submodule:

```nix
accounts = mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      enable = mkEnableOption "this Claude Code account profile";
      displayName = mkOption { ... };  # existing
      model = mkOption { ... };         # existing

      # NEW: API Configuration
      api = {
        baseUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Custom API base URL (null = default Anthropic API)";
        };

        authMethod = mkOption {
          type = types.enum [ "api-key" "bearer" "bedrock" ];
          default = "api-key";
          description = "Authentication method";
        };

        disableApiKey = mkOption {
          type = types.bool;
          default = false;
          description = "Set ANTHROPIC_API_KEY to empty string";
        };

        modelMappings = mkOption {
          type = types.attrsOf types.str;
          default = {};
          description = "Map Claude model names to proxy model names";
          example = { sonnet = "devstral"; opus = "devstral"; haiku = "qwen-a3b"; };
        };
      };

      # NEW: Secrets Configuration
      secrets = {
        bearerToken = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              bitwarden = {
                item = mkOption { type = types.str; };
                field = mkOption { type = types.str; };
              };
            };
          });
          default = null;
          description = "Bitwarden reference for bearer token";
        };
      };

      # NEW: Extra environment variables
      extraEnvVars = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for this account";
      };
    };
  });
};
```

**Validation**: `nix flake check` must pass after changes.

---

### Task I2: Update wrapper script generation

**Files**:
- `home/migration/wsl-home-files.nix` (lines 373-431)
- `home/migration/linux-home-files.nix` (equivalent section)
- `home/migration/darwin-home-files.nix` (equivalent section)

**Changes**: Modify `mkClaudeWrapperScript` to use new API options:

```nix
mkClaudeWrapperScript = { account, displayName, configDir, api ? {}, secrets ? {}, extraEnvVars ? {} }: ''
  #!/usr/bin/env bash
  set -euo pipefail

  account="${account}"
  config_dir="${configDir}"

  # API Configuration
  ${lib.optionalString (api.baseUrl or null != null) ''
  export ANTHROPIC_BASE_URL="${api.baseUrl}"
  ''}
  ${lib.optionalString (api.disableApiKey or false) ''
  export ANTHROPIC_API_KEY=""
  ''}
  ${lib.optionalString (api.authMethod or "api-key" == "bearer" && secrets.bearerToken or null != null) ''
  export ANTHROPIC_AUTH_TOKEN="$(rbw get "${secrets.bearerToken.bitwarden.item}" "${secrets.bearerToken.bitwarden.field}")"
  ''}
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
  export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
  '') (api.modelMappings or {}))}

  # Extra environment variables
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
  export ${k}="${v}"
  '') extraEnvVars)}

  # Standard wrapper logic (existing code)
  export CLAUDE_CONFIG_DIR="$config_dir"
  ...
'';
```

**Note**: Extract `mkClaudeWrapperScript` to a shared location to avoid duplication across platform files.

---

### Task I3: Add work account configuration

**File**: `home/modules/base.nix` (around line 341)

**Changes**: Add work account to existing accounts:

```nix
accounts = {
  max = {
    enable = true;
    displayName = "Claude Max Account";
    extraEnvVars = {
      DISABLE_TELEMETRY = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
  };
  pro = {
    enable = true;
    displayName = "Claude Pro Account";
    model = "sonnet";
    extraEnvVars = {
      DISABLE_TELEMETRY = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
  };
  work = {
    enable = true;
    displayName = "Work Code-Companion";
    model = "sonnet";
    api = {
      baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
      authMethod = "bearer";
      disableApiKey = true;
      modelMappings = {
        sonnet = "devstral";
        opus = "devstral";
        haiku = "qwen-a3b";
      };
    };
    secrets.bearerToken.bitwarden = {
      item = "Code-Companion";
      field = "bearer_token";
    };
  };
};
```

---

### Task I4: Create Termux package output

**New File**: `flake-modules/termux-outputs.nix`

**Concept**: Generate shell scripts and config as a Nix package that can be copied to Termux without requiring Nix on Termux.

```nix
{ inputs, self, withSystem, ... }: {
  flake = {
    packages.aarch64-linux.termux-claude-scripts = withSystem "aarch64-linux" ({ pkgs, ... }:
      let
        cfg = self.homeConfigurations."tim@thinky-nixos".config.programs.claude-code-enhanced;

        # Generate wrapper script for each account
        mkTermuxWrapper = name: account: pkgs.writeShellScriptBin "claude${name}" ''
          #!/data/data/com.termux/files/usr/bin/bash
          set -euo pipefail

          ${lib.optionalString (account.api.baseUrl or null != null) ''
          export ANTHROPIC_BASE_URL="${account.api.baseUrl}"
          ''}
          ${lib.optionalString (account.api.disableApiKey or false) ''
          export ANTHROPIC_API_KEY=""
          ''}
          ${lib.optionalString (account.api.authMethod or "api-key" == "bearer") ''
          # Bearer token - read from local secrets file on Termux
          if [[ -f "$HOME/.secrets/claude-${name}-token" ]]; then
            export ANTHROPIC_AUTH_TOKEN="$(cat "$HOME/.secrets/claude-${name}-token")"
          else
            echo "Warning: Bearer token not found at ~/.secrets/claude-${name}-token" >&2
          fi
          ''}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (model: mapping: ''
          export ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL="${mapping}"
          '') (account.api.modelMappings or {}))}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
          export ${k}="${v}"
          '') (account.extraEnvVars or {}))}

          export CLAUDE_CONFIG_DIR="$HOME/.claude-${name}"
          mkdir -p "$CLAUDE_CONFIG_DIR"

          exec claude "$@"
        '';

        wrapperScripts = lib.mapAttrs mkTermuxWrapper
          (lib.filterAttrs (n: a: a.enable) cfg.accounts);

        # Account switcher function
        accountSwitcher = pkgs.writeShellScriptBin "claude-account" ''
          #!/data/data/com.termux/files/usr/bin/bash

          show_usage() {
            echo "Usage: claude-account <account>"
            echo "Available accounts: ${lib.concatStringsSep ", " (lib.attrNames wrapperScripts)}"
          }

          case "''${1:-}" in
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: ''
            ${name})
              source <(claude${name} --print-env 2>/dev/null || true)
              echo "Switched to Claude account: ${name}"
              ;;
            '') wrapperScripts)}
            -h|--help)
              show_usage
              ;;
            *)
              echo "Unknown account: $1" >&2
              show_usage >&2
              exit 1
              ;;
          esac
        '';

        # Install script
        installScript = pkgs.writeShellScriptBin "install-termux-claude" ''
          #!/data/data/com.termux/files/usr/bin/bash
          set -euo pipefail

          INSTALL_DIR="''${1:-$HOME/bin}"
          mkdir -p "$INSTALL_DIR"

          echo "Installing Claude Code account wrappers to $INSTALL_DIR..."

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
          cp "${script}/bin/claude${name}" "$INSTALL_DIR/"
          chmod +x "$INSTALL_DIR/claude${name}"
          echo "  Installed: claude${name}"
          '') wrapperScripts)}

          cp "${accountSwitcher}/bin/claude-account" "$INSTALL_DIR/"
          chmod +x "$INSTALL_DIR/claude-account"
          echo "  Installed: claude-account"

          echo ""
          echo "Installation complete!"
          echo "Make sure $INSTALL_DIR is in your PATH."
          echo ""
          echo "Usage:"
          echo "  claudemax   - Launch with Max account"
          echo "  claudepro   - Launch with Pro account"
          echo "  claudework  - Launch with Work Code-Companion account"
          echo ""
          echo "For work account, store bearer token at:"
          echo "  ~/.secrets/claude-work-token"
        '';

      in pkgs.symlinkJoin {
        name = "termux-claude-scripts";
        paths = (lib.attrValues wrapperScripts) ++ [ accountSwitcher installScript ];
      }
    );
  };
}
```

**Build & Install Process**:

```bash
# On any Nix machine (or GitHub Actions)
nix build .#termux-claude-scripts

# Copy to Termux (via adb, scp, or shared storage)
adb push result/bin/* /data/data/com.termux/files/home/bin/

# Or use the install script
./result/bin/install-termux-claude ~/bin
```

---

### Task I5: Store secrets in Bitwarden

**On Nix-managed hosts** (rbw available):

```bash
rbw unlock
rbw add "Code-Companion" --field bearer_token="<your-actual-token>"
```

**On Termux** (no rbw):

```bash
mkdir -p ~/.secrets
chmod 700 ~/.secrets
echo "<your-actual-token>" > ~/.secrets/claude-work-token
chmod 600 ~/.secrets/claude-work-token
```

---

### Task I6: Test on Nix-managed host

```bash
# Rebuild home-manager
home-manager switch --flake .#tim@thinky-nixos

# Verify wrappers exist
which claudemax claudepro claudework

# Test work account (requires VPN)
claudework --version

# Test bearer token retrieval
rbw get "Code-Companion" "bearer_token"
```

---

### Task I7: Test Termux installation

```bash
# Build on Nix host
nix build .#termux-claude-scripts

# Transfer to Termux
# Option A: Direct copy via shared storage
cp -r result/bin/* ~/storage/shared/termux-claude/

# Option B: adb push
adb push result/bin/* /data/data/com.termux/files/home/bin/

# On Termux: Install
cd ~/storage/shared/termux-claude
./install-termux-claude ~/bin

# Test
claudemax --version
claudework --version  # After storing token
```

---

### Task I8: Add task automation to Nix module

**Context**: Unattended task automation (`run-tasks.sh`, `/next-task`) is a general Claude Code workflow feature that should be available on ALL platforms via the Nix module.

**New file**: `home/modules/claude-code/task-automation.nix`

**Features to add**:

1. **`run-tasks` script** - Unattended task runner (generated via `home.packages`)
   - Safety limits: 100 iterations max, 8h runtime, rate limit circuit breaker
   - Modes: single task (`-n 1`), count (`-n N`), all pending (`-a`), continuous (`-c`)
   - Features: state persistence, logging, dry-run mode

2. **`/next-task` slash command** - Interactive version for within Claude sessions
   - Deploy to each account's `commands/` directory
   - Auto-detects plan file from project CLAUDE.md
   - Finds first "Pending" task and executes it

**Implementation**:

```nix
# home/modules/claude-code/task-automation.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code-enhanced;

  runTasksScript = pkgs.writeShellScriptBin "run-tasks" ''
    #!/usr/bin/env bash
    # [Portable run-tasks.sh content - no hardcoded paths]
    # Uses: rg (ripgrep), claude CLI
  '';

  nextTaskMd = ''
    Read the plan file specified below (or auto-detect from CLAUDE.md),
    find the first "Pending" task, execute it, mark "Complete" with date,
    commit changes when done.

    Plan file: $ARGUMENTS
  '';
in {
  options.programs.claude-code-enhanced.taskAutomation = {
    enable = mkEnableOption "task automation scripts";
  };

  config = mkIf (cfg.enable && cfg.taskAutomation.enable) {
    home.packages = [ runTasksScript ];
    # Deploy /next-task command to all account commands/ directories
  };
}
```

**Source**: Adapt from existing `~/bin/run-tasks.sh` and `~/.claude/commands/next-task.md`

---

### Task I9: Add skills support to Nix module

**Context**: Skills (like `adr-writer`) are a general Claude Code feature that should be Nix-managed and deployed to ALL platforms.

**New file**: `home/modules/claude-code/skills.nix`

**Features to add**:

1. **Skills option** - Define skills declaratively in Nix
2. **Deployment** - Copy skill files to each account's `skills/` directory
3. **Built-in skills** - Include useful skills like `adr-writer`

**Implementation**:

```nix
# home/modules/claude-code/skills.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-code-enhanced;

  builtinSkills = {
    adr-writer = {
      description = "Guide writing Architecture Decision Records (ADRs)";
      files = {
        "SKILL.md" = ./skills/adr-writer/SKILL.md;
        "REFERENCE.md" = ./skills/adr-writer/REFERENCE.md;
      };
    };
  };
in {
  options.programs.claude-code-enhanced.skills = {
    enable = mkEnableOption "Claude Code skills";

    builtins = {
      adr-writer = mkEnableOption "ADR writing skill";
    };

    custom = mkOption {
      type = types.attrsOf (types.submodule { ... });
      default = {};
      description = "Custom skill definitions";
    };
  };

  config = mkIf (cfg.enable && cfg.skills.enable) {
    # Deploy skills to each account's skills/ directory
  };
}
```

**Source**: Adapt from existing `~/.claude/skills/adr-writer/`

---

## Features Analysis (2026-01-11)

Analysis of existing Termux Claude Code setup revealed features to add to the **general Nix module** (all platforms):

### General Features to Add to Nix Module

| Feature | Source | Target Module |
|---------|--------|---------------|
| Task automation (`run-tasks.sh`) | `~/bin/run-tasks.sh` | `task-automation.nix` (Task 8) |
| `/next-task` slash command | `~/.claude/commands/next-task.md` | `task-automation.nix` (Task 8) |
| Skills support (`adr-writer`) | `~/.claude/skills/adr-writer/` | `skills.nix` (Task 9) |
| `clc_get_commit_message` | `home/files/lib/claude-utils.bash` | Consider for shell integration |

### Already Implemented in Nix Module

| Module | Features |
|--------|----------|
| `claude-code-statusline.nix` | 5 statusline styles (powerline, minimal, context, box, fast) |
| `hooks.nix` | formatting, linting, security, git, testing, logging hooks |
| `memory-commands.nix` | `/nixmemory`, `/nixremember` with tmux integration |
| `mcp-servers.nix` | NixOS, sequential-thinking, context7, serena, brave, puppeteer, github, gitlab |
| `slash-commands.nix` | documentation, security, refactoring, context commands |

### Truly Termux-Specific (for Task 4 package only)

| Item | Reason |
|------|--------|
| Screenshot path | `/data/data/com.termux/files/home/storage/dcim/Screenshots/` |
| Shell shebang | `/data/data/com.termux/files/usr/bin/bash` |
| Secrets path | `~/.secrets/` (no rbw/Bitwarden on Termux) |

---

## Architecture Summary

```
nixcfg/
├── home/modules/
│   ├── claude-code.nix            # Main module with account schema + API options
│   ├── claude-code-statusline.nix # 5 statusline styles
│   └── claude-code/
│       ├── hooks.nix              # Development, security, logging hooks
│       ├── mcp-servers.nix        # MCP server configurations
│       ├── memory-commands.nix    # /nixmemory, /nixremember
│       ├── slash-commands.nix     # Custom slash commands
│       ├── task-automation.nix    # NEW: run-tasks script, /next-task command
│       └── skills.nix             # NEW: Skills management (adr-writer, etc.)
├── home/modules/base.nix          # Account definitions (max, pro, work)
├── home/files/
│   ├── bin/                       # Helper scripts (claudevloop, restart_claude)
│   └── lib/claude-utils.bash      # Shell library functions
├── home/migration/
│   ├── wsl-home-files.nix         # Platform wrappers
│   ├── linux-home-files.nix
│   └── darwin-home-files.nix
├── flake-modules/
│   └── termux-outputs.nix         # Termux package generation
└── docs/
    └── claude-code-multi-backend-plan.md

Outputs:
├── homeConfigurations."tim@*"                    # Nix-managed hosts (all features)
└── packages.aarch64-linux.termux-claude-scripts  # Termux portable package
    ├── bin/
    │   ├── claudemax, claudepro, claudework     # Account wrappers
    │   ├── claude-account                        # Account switcher
    │   ├── run-tasks                             # Task automation (same as Nix hosts)
    │   └── install-termux-claude                 # Installer
    └── share/
        └── claude-commands/next-task.md         # Slash command (same as Nix hosts)
```

---

## Execution Rules

### Status Tokens (CRITICAL)

Use these EXACT tokens in the Progress Tracking table:
- `TASK:PENDING` - Task not yet started
- `TASK:COMPLETE` - Task finished and verified

Do NOT use "Pending" or "Complete" without the "TASK:" prefix.

### Phase 1 (Research - Termux Compatible)

1. Execute R-tasks in order (R1, R2, R3, ...)
2. Complete ONE task per session
3. **Before marking complete**: Verify ALL items in "Definition of Done" checklist are satisfied
4. Update Progress Tracking: change `TASK:PENDING` to `TASK:COMPLETE`, add date
5. Write findings/draft code to the appropriate section in this file
6. Commit changes when task complete
7. **No Nix required** - these tasks only read files and write documentation
8. If no `TASK:PENDING` tasks remain, output `ALL_TASKS_DONE`

### Phase 2 (Implementation - Requires Nix Host)

1. Execute I-tasks in order (I1, I2, I3, ...)
2. Complete ONE task per session
3. Update Progress Tracking: change `TASK:PENDING` to `TASK:COMPLETE`, add date
4. **MUST** run `nix flake check` after each code change
5. Commit changes when task passes validation
6. **Requires Nix** - run on a Nix-managed host, not Termux
7. If no `TASK:PENDING` tasks remain, output `ALL_TASKS_DONE`

---

## Next Session Prompt

```
Continue claude-code-multi-backend integration. Plan file: docs/claude-code-multi-backend-plan.md
Current status: Plan restructured into Phase 1 (research, no Nix) and Phase 2 (implementation, requires Nix).
Next step: Start Task R1 - Document current account submodule structure.
Key context: Read home/modules/claude-code.nix lines 140-200, document in R1 Findings section.
Verification: R1 Findings section is populated with current structure documentation.
Total tasks: 15 (6 research + 9 implementation)
  - Phase 1 (R1-R6): Research tasks - can run autonomously in Termux
  - Phase 2 (I1-I9): Implementation tasks - require Nix host
```
