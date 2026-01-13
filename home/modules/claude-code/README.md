# Claude Code Nix Modules

This directory contains Nix modules for configuring Claude Code with advanced features including MCP servers, slash commands, and multi-account support.

## Modules Overview

### Core Functionality
- **`mcp-servers.nix`** - MCP (Model Context Protocol) server configurations
- **`slash-commands.nix`** - Custom slash command definitions
- **`sub-agents.nix`** - Sub-agent configurations for specialized tasks
- **`hooks.nix`** - Automation hooks for pre/post actions

### Memory Commands
- **`memory-commands.nix`** - Original symlink-based implementation (deprecated)
- **`memory-commands-static.nix`** - Static wrapper implementation (current)

## The Slash Command Evolution (2025-09-01)

### The Problem
Home-manager's default behavior creates symlinks from git-tracked locations to Nix store paths. For slash commands:
```
claude-runtime/.claude-pro/commands/nixmemory.sh -> /nix/store/hash/nixmemory
```

Every `home-manager switch` generates new store paths (even with identical content), causing git to detect changes in symlink targets. This created constant, meaningless git noise.

### The Solution: Static Wrappers
We redesigned slash commands to use a two-tier architecture:

1. **Static wrapper files** (in git repo):
   ```bash
   #!/usr/bin/env bash
   exec claude-nixmemory "$@"
   ```
   These never change, eliminating git churn.

2. **PATH commands** (installed by Nix):
   ```nix
   claudeNixmemoryCmd = pkgs.writeShellApplication {
     name = "claude-nixmemory";
     # ... implementation
   };
   ```
   These update transparently via `home.packages`.

### Why This Works
- **Claude Code** just executes `.sh` files - doesn't care if they're symlinks or static files
- **Unix PATH** resolution finds the actual commands
- **Git** sees static files that never change
- **Nix** still manages and updates the implementation

### Enabling Static Commands
```nix
programs.claude-code = {
  enable = true;
  memoryCommands.enable = true;
  staticCommands.enable = true;  # Enable static wrappers
};
```

## Architecture Principles

### 1. Separation of Concerns
- **Interface** (static files in repo) vs **Implementation** (commands on PATH)
- **Configuration** (Nix modules) vs **Runtime** (Claude Code execution)

### 2. Git-Friendly Design
- Minimize files that change frequently
- Use static content where possible
- Leverage PATH for dynamic resolution

### 3. Multi-Account Support
- Each account (`claude-pro`, `claude-max`) gets its own command directory
- Commands detect account via `CLAUDE_ACCOUNT` environment variable
- Shared implementation, account-specific data

## Files and Documentation

### Implementation Files
- `memory-commands-static.nix` - Installs actual commands to PATH when staticCommands.enable = true
- `memory-commands.nix` - Creates symlink-based commands when staticCommands.enable = false
- Static wrapper files in `claude-runtime/.claude-*/commands/` - Committed to git, never change

### Documentation
- `SLASH-COMMANDS-MIGRATION.md` - Migration guide from symlinks to static wrappers
- `CONFIGURATION-COALESCENCE.md` - How Nix manages Claude Code configuration
- `../../CLAUDE.md` - Main documentation with issue tracking and solutions

## Maintenance

### Static Wrapper Files
The files in `claude-runtime/.claude-*/commands/*.sh` are now static files committed to git.
They contain simple 3-line wrappers:
```bash
#!/usr/bin/env bash
exec claude-nixmemory "$@"
```

**Important**: These files must be manually maintained if you:
- Add new slash commands
- Rename existing commands
- Add new Claude Code accounts

To regenerate them, temporarily set `staticCommands.enable = false`, rebuild, 
then manually replace symlinks with their content.

## Testing Commands

```bash
# Verify commands are installed
which claude-nixmemory
which claude-nixremember

# Test functionality
claude-nixmemory          # Opens memory file
claude-nixremember "test" # Adds to memory

# Check file types (should be regular files, not symlinks)
file claude-runtime/.claude-pro/commands/*.sh

# Verify no git changes after rebuild
home-manager switch && git status claude-runtime/
```

## Future Improvements

1. **Extend pattern** - Apply static wrapper approach to all slash commands
2. **Command discovery** - Auto-generate command list from PATH
3. **Version checking** - Ensure wrapper/command compatibility
4. **Hot reload** - Update commands without restart

## Troubleshooting

### Commands not found
```bash
# Ensure home-manager configuration includes the module
grep -r "memory-commands-static" ~/.config/home-manager/

# Check if staticCommands is enabled
nix eval '.#homeConfigurations."$USER@$HOST".config.programs.claude-code.staticCommands.enable'
```

### Git still showing changes
```bash
# Ensure you're using static implementation
ls -la claude-runtime/.claude-*/commands/*.sh
# Should show regular files, not symlinks (->)

# If still symlinks, enable static commands and rebuild
programs.claude-code.staticCommands.enable = true;
```

## Settings.json Architecture and Git Integration

### Overview

Claude Code v2.0+ reads configuration from `settings.json` files. This section explains how these files are generated, why they're formatted the way they are, and how to manage them in git.

### File Generation Process

**Source**: `home/modules/claude-code.nix:375` - `mkSettingsTemplate` function

```nix
mkSettingsTemplate = { model, accountApi ? null }:
  pkgs.writeText "claude-settings.json" (builtins.toJSON (
    # ... configuration object ...
  ));
```

**Key Points**:
- Nix's `builtins.toJSON` generates **minified** (single-line) JSON by design
- This is intentional for Nix store efficiency and reproducibility
- The minified format is what gets deployed to `~/.config/claude-code/.claude-*/settings.json`

### The Git Diffability Problem

**Issue**: Minified JSON is difficult to diff in git:
```json
{"env":{"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","DISABLE_ERROR_REPORTING":"1","DISABLE_TELEMETRY":"1"},"hooks":{"PostToolUse":[{"hooks":[{"command":"mkdir -p \"$(dirname \"$HOME/.claude/logs/tool-usage.log\")\"\necho \"$(date): Tool used in $(pwd)\" >> \"$HOME/.claude/logs/tool-usage.log\"\n","continueOnError":true,"timeout":5,"type":"command"}],"matcher":".*"}]}}
```

**Current Solution**: Manual formatting when reviewing changes
```bash
# Format a specific account's settings.json
python3 -m json.tool < claude-runtime/.claude-work/settings.json | \
  tee /tmp/formatted.json > /dev/null && \
  mv -f /tmp/formatted.json claude-runtime/.claude-work/settings.json

# Format all account settings
for account in max pro work; do
  python3 -m json.tool < claude-runtime/.claude-$account/settings.json | \
    tee /tmp/$account-formatted.json > /dev/null && \
    mv -f /tmp/$account-formatted.json claude-runtime/.claude-$account/settings.json
done
```

### Claude Code's Runtime Behavior

**Critical Finding**: Claude Code **does NOT** rewrite these files during normal operation.

Evidence:
- Files in `claude-runtime/.claude-*/settings.json` are only updated during `home-manager switch`
- Claude Code reads but doesn't modify these template files
- Changes persist between sessions if manually formatted

**Why these files are in git**:
- They're source templates that get deployed to `~/.config/claude-code/`
- They represent the canonical configuration for each account
- They're modified by Nix during `home-manager switch`, not by Claude Code at runtime

### Multi-Account Configuration Flow

```
┌─────────────────────────────────────────────────────────────┐
│ home/modules/claude-code.nix                                │
│ ├─ mkSettingsTemplate { model, accountApi }                │
│ │  └─ builtins.toJSON → minified single-line JSON         │
│ └─ Generates per-account templates                         │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
          ┌──────────────────────────────┐
          │ home-manager switch          │
          │ ├─ Builds Nix packages       │
          │ └─ Deploys files             │
          └──────────────────────────────┘
                         │
          ┌──────────────┴───────────────┬──────────────────┐
          ▼                              ▼                  ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ Source Templates    │    │ Deployed Config     │    │ Deployed Config     │
│ (git tracked)       │    │ (runtime, ignored)  │    │ (runtime, ignored)  │
├─────────────────────┤    ├─────────────────────┤    ├─────────────────────┤
│ claude-runtime/     │    │ ~/.config/          │    │ ~/.config/          │
│ .claude-max/        │───▶│ claude-code/        │    │ claude-code/        │
│ settings.json       │    │ .claude-max/        │    │ .claude-max/        │
│                     │    │ settings.json       │    │ .claude.json        │
│ (minified or        │    │                     │    │ .mcp.json           │
│  formatted)         │    │ (minified)          │    │ (runtime state)     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

### API Configuration in settings.json (v2.0+)

**Critical Discovery** (2026-01-13): Claude Code v2.0+ ignores shell environment variables for API configuration. It ONLY reads from `settings.json` env object.

**Before** (doesn't work):
```bash
# Wrapper script exports env vars
export ANTHROPIC_BASE_URL="https://proxy.example.com"
export ANTHROPIC_DEFAULT_SONNET_MODEL="custom-model"
exec claude --settings="$settings_file"
```

**After** (works correctly):
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://proxy.example.com",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "custom-model",
    "ANTHROPIC_API_KEY": "${from_wrapper_or_bitwarden}"
  }
}
```

**Implementation** (`home/modules/claude-code.nix:391-405`):
```nix
# Build account-specific env vars for settings.json
accountEnvVars = if accountApi == null then { }
  else
    (optionalAttrs (accountApi.baseUrl or null != null) {
      ANTHROPIC_BASE_URL = accountApi.baseUrl;
    })
    // (lib.mapAttrs'
      (model: mapping: lib.nameValuePair
        "ANTHROPIC_DEFAULT_${lib.toUpper model}_MODEL" mapping)
      (accountApi.modelMappings or { }))
    // (accountApi.extraEnvVars or { });

# Merge global env vars with account-specific ones
mergedEnvVars = cfg.environmentVariables // accountEnvVars;
```

**Authentication Fix** (Commit 5c92b33):
- Changed from `ANTHROPIC_AUTH_TOKEN` → `ANTHROPIC_API_KEY`
- `AUTH_TOKEN` is reserved for Anthropic's OAuth flow (gets cached/overridden)
- `API_KEY` works for both Anthropic API and third-party proxies

### Formatting Strategies

**Option 1: Manual format on review** (current approach)
- Pros: Simple, no automation needed, full control
- Cons: Must remember to format before commits, easy to forget

**Option 2: Pre-commit hook** (not implemented)
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
for file in claude-runtime/.claude-*/settings.json; do
  if git diff --cached --name-only | grep -q "$file"; then
    python3 -m json.tool < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    git add "$file"
  fi
done
```
- Pros: Automatic formatting, never forget
- Cons: Adds complexity, potential for hook failures, reformats on every commit

**Option 3: Custom Nix pretty-printer** (not implemented)
```nix
mkSettingsTemplate = { model, accountApi ? null }:
  let jsonContent = builtins.toJSON { ... };
  in pkgs.runCommand "claude-settings.json" {} ''
    echo '${jsonContent}' | ${pkgs.python3}/bin/python3 -m json.tool > $out
  '';
```
- Pros: Generated files are always formatted
- Cons: Unnecessary build overhead, breaks Nix reproducibility benefits

**Recommendation**: Continue with manual formatting when reviewing changes. The files only change during development of the Claude Code configuration, not during normal use.

### Git Management Best Practices

**When to format**:
1. Before committing changes to account configurations
2. When reviewing diffs to understand what changed
3. After adding new accounts or modifying API settings

**When NOT to format**:
- Don't format deployed files in `~/.config/claude-code/`
- Don't reformat if only checking status
- Don't format unrelated accounts when working on one

**Workflow**:
```bash
# 1. Make configuration changes in Nix
vim home/common/development.nix

# 2. Rebuild and deploy
home-manager switch --flake '.#tim@thinky-nixos'

# 3. Check what changed (minified, hard to read)
git diff claude-runtime/.claude-work/settings.json

# 4. Format for review
python3 -m json.tool < claude-runtime/.claude-work/settings.json | \
  tee /tmp/work.json > /dev/null && \
  mv -f /tmp/work.json claude-runtime/.claude-work/settings.json

# 5. Review formatted diff
git diff claude-runtime/.claude-work/settings.json

# 6. Stage and commit
git add claude-runtime/.claude-work/settings.json
git commit -m "Update claudework API configuration"
```

### Account-Specific Configuration

**Three accounts currently configured**:

1. **claudemax** - Personal Anthropic MAX account
   - Direct Anthropic API
   - No custom baseUrl or model mappings
   - Only telemetry/traffic controls in env

2. **claudepro** - Personal Anthropic PRO account
   - Direct Anthropic API
   - No custom baseUrl or model mappings
   - Only telemetry/traffic controls in env

3. **claudework** - Work Code-Companion proxy
   - Custom baseUrl: `https://codecompanionv2.d-dp.nextcloud.aero`
   - Model mappings:
     - `sonnet` → `devstral`
     - `haiku` → `qwen-a3b`
     - `opus` → `devstral`
   - Requires `ANTHROPIC_API_KEY` from Bitwarden

**Example configuration** (`home/common/development.nix`):
```nix
programs.claude-code = {
  accounts.work = {
    enable = true;
    displayName = "Work (Code-Companion)";
    api = {
      baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
      authMethod = "bearer";
      modelMappings = {
        sonnet = "devstral";
        haiku = "qwen-a3b";
        opus = "devstral";
      };
    };
    secrets.bearerToken.bitwarden = {
      item = "Code Companion";
      field = "api-key";
    };
  };
};
```

### Troubleshooting

**Settings not being applied**:
```bash
# Check deployed settings match source templates
diff claude-runtime/.claude-work/settings.json \
     ~/.config/claude-code/.claude-work/settings.json

# If different, rebuild
home-manager switch --flake '.#tim@thinky-nixos'
```

**API not connecting**:
```bash
# Verify env vars are in settings.json, not just wrapper
jq '.env' claude-runtime/.claude-work/settings.json

# Check for correct API key variable name
jq '.env | keys | map(select(. | startswith("ANTHROPIC")))' \
  claude-runtime/.claude-work/settings.json

# Should show ANTHROPIC_API_KEY, not ANTHROPIC_AUTH_TOKEN
```

**Model mappings not working**:
```bash
# Check model mappings are in env
jq '.env | with_entries(select(.key | startswith("ANTHROPIC_DEFAULT")))' \
  claude-runtime/.claude-work/settings.json

# Should show entries like:
# "ANTHROPIC_DEFAULT_SONNET_MODEL": "devstral"
```

## Key Takeaways

The transition from symlinks to static wrappers demonstrates important Nix patterns:

1. **Not everything needs to be a symlink** - Sometimes static files with PATH-based indirection is better
2. **Git integration matters** - Design with version control in mind
3. **Simple is sustainable** - 3-line wrapper scripts are easy to understand and maintain
4. **Unix patterns are timeless** - PATH resolution has worked for 50+ years

The settings.json architecture reveals important Claude Code v2.0 behaviors:

5. **Environment variables don't work** - Claude Code v2.0+ only reads from settings.json env object
6. **builtins.toJSON is minified** - This is Nix's design, not a bug
7. **Manual formatting is acceptable** - Pre-commit hooks add unnecessary complexity
8. **Authentication matters** - Use ANTHROPIC_API_KEY, not ANTHROPIC_AUTH_TOKEN