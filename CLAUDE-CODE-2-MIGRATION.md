# Claude Code 2.0 Migration - Essentials

## Command Line Change

### Old (v1.x) - REMOVED
```bash
claude --config-dir=/path/to/config
```

### New (v2.0) - Use --settings flag
```bash
claude --settings /path/to/config/settings.json
```

**Your wrapper scripts:**
```bash
#!/bin/bash
# claudepro
exec claude --settings "${HOME}/src/nixcfg/claude-runtime/.claude-pro/settings.json" "$@"
```

```bash
#!/bin/bash  
# claudemax
exec claude --settings "${HOME}/src/nixcfg/claude-runtime/.claude-max/settings.json" "$@"
```

## Configuration File Migration

### Manual Migration

Old `.claude.json` → New `settings.json`:

| Old Key | New Key | Action |
|---------|---------|--------|
| `allowedTools` | `permissions.allow` | Rename |
| `ignorePatterns` | `permissions.deny` | Rename + wrap in `Read()` |
| `env` | `env` | Keep as-is |
| `theme` | `theme` | Keep as-is |
| `projects.*.mcpServers` | Move to `.mcp.json` | Separate file |
| `todoFeatureEnabled` | - | Remove |
| `customApiKeyResponses` | - | Remove |
| `shiftEnterKeyBindingInstalled` | - | Remove |
| `hasCompletedOnboarding` | - | Remove |

### Automated Migration with jq

**One-line conversion:**
```bash
jq '{
  permissions: {
    allow: .allowedTools,
    deny: (.ignorePatterns // [] | map("Read(\(.))")),
  },
  env: .env,
  theme: .theme
} | del(..|nulls)' ~/.claude.json > settings.json
```

**With apiKeyHelper for authentication:**
```bash
jq '{
  apiKeyHelper: "echo $ANTHROPIC_API_KEY",
  permissions: {
    allow: .allowedTools,
    deny: (.ignorePatterns // [] | map("Read(\(.))")),
  },
  env: .env,
  theme: .theme
} | del(..|nulls)' ~/.claude.json > settings.json
```

**Example transformation:**

Input (`.claude.json`):
```json
{
  "allowedTools": ["Bash(git:*)", "Read", "Write"],
  "ignorePatterns": ["**/.env", "**/secrets/**"],
  "env": {"ANTHROPIC_API_KEY": "sk-xxx"},
  "theme": "dark",
  "todoFeatureEnabled": true
}
```

Output (`settings.json`):
```json
{
  "permissions": {
    "allow": ["Bash(git:*)", "Read", "Write"],
    "deny": ["Read(**/.env)", "Read(**/secrets/**)"]
  },
  "env": {"ANTHROPIC_API_KEY": "sk-xxx"},
  "theme": "dark"
}
```

## Key New Flags (v2.0)

Useful additions to your wrapper scripts:

```bash
# Specify model per account
--model opus                         # claudemax
--model sonnet                       # claudepro

# Define custom agents inline
--agents '{"reviewer": {"description": "Code reviewer", "prompt": "...", "tools": ["Read"]}}'

# Control permissions per invocation
--allowed-tools "Read Write Bash(git:*)"
--disallowed-tools "Bash(sudo:*)"

# Permission modes
--permission-mode plan               # Approval for plans only
--permission-mode acceptEdits        # Auto-accept edits

# Continue/resume
-c, --continue                       # Continue last session
-r, --resume SESSION_ID              # Resume specific session

# Output control
-p, --print                          # Non-interactive mode
--output-format json                 # JSON output for scripting
```

## New v2.0 Features Worth Using

### 1. Checkpoints/Rewind
Automatically saves code state and conversation before each change. Use /rewind or Esc+Esc to restore both code and context to previous state.

```bash
# In session
/rewind           # Undo last changes
Esc Esc           # Quick rewind
```

### 2. Subagents
Define specialized AI assistants that work in parallel:

```bash
claude --agents '{
  "reviewer": {
    "description": "Expert code reviewer",
    "prompt": "You are a senior code reviewer. Focus on security and best practices.",
    "tools": ["Read", "Grep", "Bash"],
    "model": "sonnet"
  }
}'
```

### 3. Usage Tracking
New /usage command shows plan limits:

```bash
# In session
/usage            # Check token usage and limits
/cost             # Check cost breakdown
```

### 4. Better History Search
Ctrl+R for searchable prompt history - reuse complex commands easily.

### 5. Background Tasks
Long-running processes (dev servers) don't block Claude's work:

```bash
# Claude can run dev server in background while continuing other work
```

## Improved Wrapper Scripts

### Basic Version
```bash
#!/bin/bash
exec claude --settings "${HOME}/.claude-pro/settings.json" "$@"
```

### Enhanced Version
```bash
#!/bin/bash
# claudepro - Enhanced wrapper with 2.0 features

SETTINGS="${HOME}/src/nixcfg/claude-runtime/.claude-pro/settings.json"

# Default to Sonnet for cost efficiency
# Override with: claudepro --model opus "complex task"
exec claude \
  --settings "$SETTINGS" \
  --model sonnet \
  "$@"
```

### Max Account with Subagents
```bash
#!/bin/bash
# claudemax - Full-featured wrapper

SETTINGS="${HOME}/src/nixcfg/claude-runtime/.claude-max/settings.json"

exec claude \
  --settings "$SETTINGS" \
  --model opus \
  --agents '{
    "security": {
      "description": "Security auditor",
      "prompt": "Review code for security vulnerabilities",
      "tools": ["Read", "Grep"]
    }
  }' \
  "$@"
```

## Settings.json Schema

Minimal useful configuration:

```json
{
  "model": "claude-sonnet-4-5-20250929",
  "permissions": {
    "allow": ["Read", "Write", "Edit", "Bash(git:*)"],
    "deny": ["Read(**/.env)", "Bash(sudo:*)"],
    "defaultMode": "default"
  },
  "env": {
    "ANTHROPIC_API_KEY": "sk-xxx"
  }
}
```

Full schema:

```json
{
  "apiKeyHelper": "/path/to/get-key.sh",
  "model": "claude-sonnet-4-5-20250929",
  "permissions": {
    "allow": ["Read", "Write", "Edit"],
    "deny": ["Read(**/.env)"],
    "ask": ["Bash(docker:*)"],
    "defaultMode": "default",
    "disableBypassPermissionsMode": false,
    "additionalDirectories": ["/path"]
  },
  "env": {
    "ANTHROPIC_API_KEY": "key",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": 8192
  },
  "theme": "dark",
  "cleanupPeriodDays": 7,
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "./lint.sh"}]
    }]
  }
}
```

## Migration Checklist

- [ ] Convert `.claude.json` to `settings.json` with jq command
- [ ] Update wrapper scripts: remove `--config-dir`, add `--settings`
- [ ] Test each wrapper authenticates to correct account
- [ ] Consider adding new v2.0 flags (--model, --agents, etc.)
- [ ] Set up hooks for auto-formatting/linting (optional)

## Testing

```bash
# Verify settings loaded correctly
claudepro
# In session: /config

# Check authentication
claudemax  
# In session: /status

# Test new features
claudepro "test task"
# Try: Esc+Esc to rewind, Ctrl+R for history, /usage for limits
```

Done. Your multi-account setup now works with v2.0.
