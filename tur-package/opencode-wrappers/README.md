# OpenCode Multi-Account Wrappers for Termux

Wrapper scripts for managing multiple OpenCode accounts on Termux.

## Overview

This package provides three wrapper commands for OpenCode:

| Command | Account | Configuration |
|---------|---------|---------------|
| `opencodemax` | OpenCode Max | Default API, telemetry disabled |
| `opencodepro` | OpenCode Pro | Default API, telemetry disabled |
| `opencodework` | Custom Proxy | Template for third-party API proxy (requires setup) |

## Installation

### 1. Install OpenCode

```bash
pkg install nodejs-lts
npm install -g @opencode-ai/sdk
```

### 2. Install Wrappers

```bash
pkg install opencode-wrappers
```

### 3. Set Up Authentication

**For Max/Pro accounts:**
```bash
# Authenticate using standard OpenCode flow
opencodemax auth
# or
opencodepro auth
```

**For custom proxy (opencodework):**

⚠️  **Important:** `opencodework` is a template. You must configure it first:

```bash
# 1. Edit the wrapper to set your proxy URL and model mappings
nano $PREFIX/bin/opencodework
# Replace:
#   - ANTHROPIC_BASE_URL with your proxy URL
#   - Model mappings with your proxy's models

# 2. Run interactive setup to configure bearer token
opencode-setup-work

# Or manually create token file
mkdir -p ~/.secrets
chmod 700 ~/.secrets
echo 'your-bearer-token-here' > ~/.secrets/opencode-work-token
chmod 600 ~/.secrets/opencode-work-token
```

## Usage

Each wrapper works exactly like the `opencode` command but with account-specific configuration:

```bash
# Use Max account
opencodemax "help me with bash scripting"

# Use Pro account in a git repository
cd ~/myproject
opencodepro "review this codebase"

# Use custom proxy (after configuring opencodework)
opencodework "analyze this code"
```

## Configuration

Each account uses a separate configuration directory:

- Max: `~/.opencode-max/`
- Pro: `~/.opencode-pro/`
- Work: `~/.opencode-work/`

These directories contain:
- `settings.json` - Account-specific settings
- `.opencode.json` - Runtime state
- `.mcp.json` - MCP server configuration
- `logs/` - Session logs

## Environment Variables

All wrappers set:
- `DISABLE_TELEMETRY=1`
- `OPENCODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- `DISABLE_ERROR_REPORTING=1`

**Custom proxy (opencodework) additionally sets:**
- `ANTHROPIC_BASE_URL` (template: `https://api.example.com/v1`)
- `ANTHROPIC_API_KEY` (from `~/.secrets/opencode-work-token`)
- `ANTHROPIC_DEFAULT_SONNET_MODEL` (template: `custom-model-large`)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (template: `custom-model-large`)
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (template: `custom-model-small`)

⚠️  **Template values:** Edit `$PREFIX/bin/opencodework` to set your actual proxy URL and model names.

## Model Mappings (Custom Proxy)

The `opencodework` template demonstrates model mapping:

| OpenCode Model | Template Mapping |
|----------------|------------------|
| Sonnet 4.5 | custom-model-large |
| Opus 4.5 | custom-model-large |
| Haiku 4 | custom-model-small |

**Replace these with your proxy's actual model names.**

## Troubleshooting

### "opencode command not found"

Install OpenCode:
```bash
pkg install nodejs-lts
npm install -g @opencode-ai/sdk
```

### "API key not found" (work account)

Run the setup helper:
```bash
opencode-setup-work
```

Or manually create the token file:
```bash
mkdir -p ~/.secrets
echo 'your-token' > ~/.secrets/opencode-work-token
chmod 600 ~/.secrets/opencode-work-token
```

### Check wrapper configuration

```bash
# View environment variables set by wrapper
opencodework env | grep ANTHROPIC
opencodework env | grep OPENCODE
```

### Test connection

```bash
# Should show version if working
opencodemax --version
opencodepro --version
opencodework --version
```

## Files

- `/data/data/com.termux/files/usr/bin/opencodemax` - Max wrapper script
- `/data/data/com.termux/files/usr/bin/opencodepro` - Pro wrapper script
- `/data/data/com.termux/files/usr/bin/opencodework` - Work wrapper script
- `/data/data/com.termux/files/usr/bin/opencode-setup-work` - Setup helper
- `/data/data/com.termux/files/usr/share/doc/opencode-wrappers/README.md` - This file
- `~/.secrets/opencode-work-token` - Bearer token (work account, user-created)

## Source

- Package: https://github.com/timblaktu/tur
- Upstream: https://github.com/timblaktu/nixcfg
- OpenCode: https://github.com/anomalyco/opencode

## License

MIT
