# Claude Code Multi-Account Wrappers for Termux

Wrapper scripts for managing multiple Claude Code accounts on Termux.

## Overview

This package provides three wrapper commands for Claude Code:

| Command | Account | Configuration |
|---------|---------|---------------|
| `claudemax` | Claude Max | Default Anthropic API, telemetry disabled |
| `claudepro` | Claude Pro | Default Anthropic API, telemetry disabled |
| `claudework` | Custom Proxy | Template for third-party API proxy (requires setup) |

## Installation

### 1. Install Claude Code

```bash
pkg install nodejs-lts
npm install -g @anthropic/claude-code
```

### 2. Install Wrappers

```bash
pkg install claude-wrappers
```

### 3. Set Up Authentication

**For Max/Pro accounts:**
```bash
# Authenticate using standard Claude Code flow
claudemax auth
# or
claudepro auth
```

**For custom proxy (claudework):**

⚠️  **Important:** `claudework` is a template. You must configure it first:

```bash
# 1. Edit the wrapper to set your proxy URL and model mappings
nano $PREFIX/bin/claudework
# Replace:
#   - ANTHROPIC_BASE_URL with your proxy URL
#   - Model mappings with your proxy's models

# 2. Run interactive setup to configure bearer token
claude-setup-work

# Or manually create token file
mkdir -p ~/.secrets
chmod 700 ~/.secrets
echo 'your-bearer-token-here' > ~/.secrets/claude-work-token
chmod 600 ~/.secrets/claude-work-token
```

## Usage

Each wrapper works exactly like the `claude` command but with account-specific configuration:

```bash
# Use Max account
claudemax "help me with bash scripting"

# Use Pro account in a git repository
cd ~/myproject
claudepro "review this codebase"

# Use custom proxy (after configuring claudework)
claudework "analyze this code"
```

## Configuration

Each account uses a separate configuration directory:

- Max: `~/.claude-max/`
- Pro: `~/.claude-pro/`
- Work: `~/.claude-work/`

These directories contain:
- `settings.json` - Account-specific settings
- `.claude.json` - Runtime state
- `.mcp.json` - MCP server configuration
- `logs/` - Session logs

## Environment Variables

All wrappers set:
- `DISABLE_TELEMETRY=1`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- `DISABLE_ERROR_REPORTING=1`

**Custom proxy (claudework) additionally sets:**
- `ANTHROPIC_BASE_URL` (template: `https://api.example.com/v1`)
- `ANTHROPIC_API_KEY` (from `~/.secrets/claude-work-token`)
- `ANTHROPIC_DEFAULT_SONNET_MODEL` (template: `custom-model-large`)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (template: `custom-model-large`)
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (template: `custom-model-small`)

⚠️  **Template values:** Edit `$PREFIX/bin/claudework` to set your actual proxy URL and model names.

## Model Mappings (Custom Proxy)

The `claudework` template demonstrates model mapping:

| Claude Model | Template Mapping |
|--------------|------------------|
| Sonnet 4.5 | custom-model-large |
| Opus 4.5 | custom-model-large |
| Haiku 4 | custom-model-small |

**Replace these with your proxy's actual model names.**

## Troubleshooting

### "claude command not found"

Install Claude Code:
```bash
pkg install nodejs-lts
npm install -g @anthropic/claude-code
```

### "API key not found" (work account)

Run the setup helper:
```bash
claude-setup-work
```

Or manually create the token file:
```bash
mkdir -p ~/.secrets
echo 'your-token' > ~/.secrets/claude-work-token
chmod 600 ~/.secrets/claude-work-token
```

### Check wrapper configuration

```bash
# View environment variables set by wrapper
claudework env | grep ANTHROPIC
claudework env | grep CLAUDE
```

### Test connection

```bash
# Should show version if working
claudemax --version
claudepro --version
claudework --version
```

## Files

- `/data/data/com.termux/files/usr/bin/claudemax` - Max wrapper script
- `/data/data/com.termux/files/usr/bin/claudepro` - Pro wrapper script
- `/data/data/com.termux/files/usr/bin/claudework` - Work wrapper script
- `/data/data/com.termux/files/usr/bin/claude-setup-work` - Setup helper
- `/data/data/com.termux/files/usr/share/doc/claude-wrappers/README.md` - This file
- `~/.secrets/claude-work-token` - Bearer token (work account, user-created)

## Source

- Package: https://github.com/timblaktu/tur
- Upstream: https://github.com/timblaktu/nixcfg
- Claude Code: https://github.com/anthropics/claude-code

## License

MIT
