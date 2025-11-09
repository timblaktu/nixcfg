# Claude Code 2.0 Migration - Nix-First Architecture

## Executive Summary

Clean migration to Claude Code v2.0 leveraging its improved configuration/state separation. The Nix-first design manages all static configuration, with minimal runtime coalescence for slash-command-modifiable settings.

**Core Changes:**
1. **CLI**: `--config-dir` → `--settings` flag
2. **Schema**: `allowedTools`/`ignorePatterns` → `permissions.{allow,deny}`
3. **Separation**: MCP servers moved to `.mcp.json`
4. **Wrapper**: Update flag + add coalescence hook

## Current System Architecture

### File Structure
```
nixcfg/
├── home/modules/
│   └── claude-code.nix              # Orchestrator
│       ├── mcp-servers.nix          # MCP definitions
│       ├── hooks.nix                # Automation
│       └── [other modules]
└── claude-runtime/                  # Git-tracked
    ├── .claude-max/
    │   ├── settings.json            # Nix-managed (v2.0)
    │   ├── .mcp.json                # Nix-managed (v2.0)
    │   ├── .claude.json             # Runtime state + coalesced config
    │   ├── CLAUDE.md                # Memory
    │   └── commands/                # Slash commands
    └── .claude-pro/
        └── [same structure]
```

### Current Wrapper (v1.x)
```bash
#!/usr/bin/env bash
# Existing single-instance enforcement + --config-dir usage
exec claude --config-dir "${HOME}/src/nixcfg/claude-runtime/.claude-max" "$@"
```

**What Changes:**
- Flag: `--config-dir` → `--settings`
- Add: Startup coalescence call

## Migration Strategy

### Phase 1: Nix Module Updates (v2.0 Schema)

#### 1.1 Settings Template (v2.0 Structure)

**File:** `home/modules/claude-code.nix`

```nix
mkSettingsTemplate = model: pkgs.writeText "claude-settings.json" (builtins.toJSON {
  model = model;
  
  # V2.0 permissions structure
  permissions = {
    allow = cfg.permissions.allow;
    deny = cfg.permissions.deny;
    ask = cfg.permissions.ask;
    defaultMode = cfg.permissions.defaultMode;
    disableBypassPermissionsMode = cfg.permissions.disableBypass;
    additionalDirectories = cfg.permissions.additionalDirs;
  };
  
  env = cfg.environmentVariables;
  hooks = cleanHooks;
  statusLine = cfg._internal.statuslineSettings;
  
  # MCP servers REMOVED - moved to .mcp.json
  
  projectOverrides = {
    enabled = true;
    searchPaths = cfg.projectOverridePaths;
  };
});
```

**Key Change:** `mcpServers` removed from settings.json → separate file.

#### 1.2 MCP File Generation

```nix
# New template for .mcp.json
mcpTemplate = pkgs.writeText "claude-mcp.json" (builtins.toJSON {
  mcpServers = claudeCodeMcpServers;
});
```

#### 1.3 Permission Options (v2.0)

```nix
permissions = mkOption {
  type = types.submodule {
    options = {
      allow = mkOption {
        type = types.listOf types.str;
        default = [
          "Bash" "Read" "Write" "Edit" "WebFetch"
          "mcp__context7"  # Note: mcp__ prefix
          "mcp__sequential-thinking"
        ];
      };
      deny = mkOption {
        type = types.listOf types.str;
        default = ["Search" "Find" "Bash(rm -rf /*)"];
      };
      ask = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Patterns requiring explicit permission";
      };
      defaultMode = mkOption {
        type = types.enum ["default" "plan" "acceptEdits"];
        default = "default";
      };
      disableBypass = mkOption {
        type = types.bool;
        default = false;
      };
      additionalDirs = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };
};
```

### Phase 2: Wrapper Updates (Minimal Changes)

#### 2.1 Core Wrapper (claudemax/claudepro)

**File:** `home/modules/files/bin/claudemax`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
ACCOUNT="max"
CONFIG_BASE="${HOME}/src/nixcfg/claude-runtime"
SETTINGS_FILE="$CONFIG_BASE/.claude-$ACCOUNT/settings.json"

# Your existing single-instance check (with -p/--print exception)
if [[ "$*" != *"-p"* && "$*" != *"--print"* ]]; then
  # [Your existing pidfile logic]
  pidfile="/tmp/claude-$ACCOUNT.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "❌ Claude Code ($ACCOUNT) already running"
    exit 1
  fi
  echo $$ > "$pidfile"
  trap "rm -f '$pidfile'" EXIT
fi

# NEW: Startup coalescence (v2.0 aware)
coalesce_nix_config() {
  local config="$CONFIG_BASE/.claude-$ACCOUNT/.claude.json"
  [[ ! -f "$config" ]] && return 0
  
  # Apply Nix-managed fields, preserve runtime state
  jq \
    --slurpfile settings <(cat "$SETTINGS_FILE") \
    --slurpfile mcp <(cat "$CONFIG_BASE/.claude-$ACCOUNT/.mcp.json") \
    '. as $runtime |
    $settings[0] as $s |
    $mcp[0] as $m |
    $runtime |
    .model = $s.model |
    .permissions = $s.permissions |
    .env = $s.env |
    .hooks = $s.hooks |
    .statusLine = $s.statusLine |
    .mcpServers = $m.mcpServers |
    .projectOverrides = $s.projectOverrides
    # Runtime state (oauthAccount, projects, userID, etc.) preserved
    ' "$config" > "$config.tmp" && mv "$config.tmp" "$config"
}

coalesce_nix_config

# CHANGED: v2.0 flag
exec claude --settings "$SETTINGS_FILE" "$@"
```

**Changes:**
1. `--config-dir` → `--settings` 
2. Add `coalesce_nix_config()` function
3. Single-instance logic preserved (already working)

### Phase 3: Activation Script Updates

#### 3.1 Template Deployment (v2.0 Format)

**File:** `home/modules/claude-code.nix` → `home.activation.claudeConfigTemplates`

```bash
# For each enabled account
for account in max pro; do
  accountDir="${runtimePath}/.claude-${account}"
  
  # V2.0 SETTINGS: Always deploy (Nix-managed)
  copy_template "${mkSettingsTemplate model}" "$accountDir/settings.json"
  echo "✅ Deployed v2.0 settings.json"
  
  # V2.0 MCP: Always deploy (Nix-managed)
  copy_template "${mcpTemplate}" "$accountDir/.mcp.json"
  echo "✅ Deployed .mcp.json"
  
  # MEMORY: Deploy once, then preserve
  if [[ ! -f "$accountDir/CLAUDE.md" ]]; then
    copy_template "${claudeMdTemplate}" "$accountDir/CLAUDE.md"
    chmod ${if makeWritable then "644" else "444"} "$accountDir/CLAUDE.md"
    echo "✅ Created CLAUDE.md"
  fi
  
  # RUNTIME STATE: .claude.json managed by Claude Code + coalescence
  # NOT deployed here - created by Claude Code on first run
done
```

**Key Points:**
- `settings.json` and `.mcp.json` always overwritten (Nix truth)
- `.claude.json` left alone (runtime state + coalesced config)
- No migration logic needed

#### 3.2 What Claude Code Manages at Runtime

**Pure Runtime State** (never coalesced):
- `oauthAccount` - Authentication
- `projects` - Project history
- `userID` - User identification
- `numStartups`, `firstStartTime` - Usage tracking
- `has*`, `cached*`, `last*` - UI/feature flags

**Coalesced Config** (restored from Nix on startup):
- `model` - Can be changed via slash commands
- `permissions` - Can be modified at runtime
- `mcpServers` - Can be toggled on/off
- `hooks`, `env`, `statusLine` - Configurable features

The coalescence ensures Nix's declarative config wins on each session start.

### Phase 4: Testing & Validation

#### Quick Test After Migration

```bash
# 1. Rebuild with v2.0 changes
cd ~/src/nixcfg
home-manager switch --flake .

# 2. Check settings format
jq '.permissions.allow' claude-runtime/.claude-max/settings.json
# Should show array with mcp__ prefixed entries

# 3. Check MCP separation
ls claude-runtime/.claude-max/.mcp.json
# Should exist with mcpServers

# 4. Test wrapper
claudemax --print "echo test"
# Should use --settings flag internally

# 5. Verify coalescence
# Start session, check that runtime .claude.json has Nix config applied
```

## V2.0 Feature Opportunities

### 1. Model Override per Session
```bash
# Use opus for complex tasks
claudemax --model opus "refactor this codebase"

# Use sonnet for quick fixes  
claudepro --model sonnet --print "fix typo"
```

### 2. Permission Modes
```nix
# In Nix config - approval for plans only
permissions.defaultMode = "plan";

# Or per-session via wrapper
claudemax --permission-mode acceptEdits "routine update"
```

### 3. Sub-agent Inline Definitions
```bash
# Define specialized agent for session
claudemax --agents '{
  "security": {
    "description": "Security auditor",
    "tools": ["Read", "Grep"],
    "model": "sonnet"
  }
}' "audit authentication code"
```

### 4. Session Management
```bash
# Continue previous session
claudemax -c

# Resume specific session
claudemax --resume <session-id>

# Non-interactive mode
claudemax -p "git status"
```

## Configuration Separation Benefits

**Nix-Managed (settings.json, .mcp.json):**
- Version controlled
- Declarative
- Applied consistently
- No drift

**Runtime-Managed (.claude.json):**
- Session state
- Auth tokens
- Usage analytics
- UI preferences

**Coalescence:**
- Runs once at startup
- Restores Nix config
- Preserves runtime state
- No monitoring overhead

## Migration Checklist

- [ ] Update `claude-code.nix`: v2.0 permissions structure
- [ ] Add `.mcp.json` template generation
- [ ] Update wrappers: `--settings` flag + coalescence
- [ ] Update activation script: deploy both files
- [ ] Test: `home-manager switch`
- [ ] Verify: Check settings.json, .mcp.json format
- [ ] Test: Run `claudemax --print "test"`
- [ ] Commit: Git add new template files

## Troubleshooting

**Settings not applying:**
- Check `settings.json` has v2.0 permissions structure
- Verify wrapper calls coalescence before exec
- Delete `.claude.json` and restart for fresh state

**MCP servers not connecting:**
- Check `.mcp.json` exists
- Verify `mcp__` prefix in permissions.allow
- Check Claude Code logs

**Wrapper fails:**
- Ensure `jq` available (should be in Nix packages)
- Check settings file path correct
- Verify no syntax errors in JSON templates

## References

- https://docs.claude.com/en/docs/claude-code/cli-reference
- https://docs.claude.com/en/docs/claude-code/settings
- https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview
