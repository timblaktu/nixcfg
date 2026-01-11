# Claude Code Multi-Backend & Termux Integration Plan

## Overview

Integrate work's Code-Companion proxy as a new Claude Code "account" alongside existing personal accounts (max, pro), with unified configuration across all platforms including Termux.

**Key Design Decision**: Generate Termux configuration as Nix package outputs - no nix-on-droid required. Single source of truth, simple installation.

## Progress Tracking

| Task | Name | Status | Date |
|------|------|--------|------|
| 1 | Extend account submodule with API options | Pending | |
| 2 | Update wrapper script generation | Pending | |
| 3 | Add work account configuration | Pending | |
| 4 | Create Termux package output | Pending | |
| 5 | Store secrets in Bitwarden | Pending | |
| 6 | Test on Nix-managed host | Pending | |
| 7 | Test Termux installation | Pending | |

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

## Task Definitions

### Task 1: Extend account submodule with API options

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

### Task 2: Update wrapper script generation

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

### Task 3: Add work account configuration

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

### Task 4: Create Termux package output

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

### Task 5: Store secrets in Bitwarden

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

### Task 6: Test on Nix-managed host

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

### Task 7: Test Termux installation

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

## Architecture Summary

```
nixcfg/
├── home/modules/
│   └── claude-code.nix          # Account schema with API options
├── home/modules/base.nix        # Account definitions (max, pro, work)
├── home/migration/
│   ├── wsl-home-files.nix       # Platform wrappers (use shared mkClaudeWrapperScript)
│   ├── linux-home-files.nix
│   └── darwin-home-files.nix
├── flake-modules/
│   └── termux-outputs.nix       # Termux package generation
└── docs/
    └── claude-code-multi-backend-plan.md  # This file

Outputs:
├── homeConfigurations."tim@*"   # Nix-managed hosts get wrappers via home.packages
└── packages.aarch64-linux.termux-claude-scripts  # Termux gets portable scripts
```

---

## Execution Rules

1. Execute tasks in order shown in Progress Tracking table
2. Complete ONE task per session (for context-cleared workflow)
3. Update Progress Tracking: mark status "Complete", add date
4. Run `nix flake check` after each code change
5. Commit changes when task passes validation

---

## Next Session Prompt

```
Continue claude-code-multi-backend integration. Plan file: docs/claude-code-multi-backend-plan.md
Current status: Plan complete, ready to start Task 1.
Next step: Extend account submodule in home/modules/claude-code.nix with API options.
Key context: Add api.baseUrl, api.authMethod, api.disableApiKey, api.modelMappings, secrets.bearerToken, extraEnvVars.
Check: Lines 143-163 for current account submodule structure.
```
