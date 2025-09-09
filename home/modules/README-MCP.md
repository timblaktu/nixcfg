# MCP Server Configuration - Home Manager Module

## Overview

This module provides comprehensive MCP (Model Context Protocol) server integration for Claude Desktop and claude-code, with full cross-platform support including WSL, native Linux, and Windows.

## Current Status ✅

**All 5 MCP servers operational as of 2025-08-29:**

| Server | Purpose | Status | Implementation |
|--------|---------|--------|----------------|
| `sequential-thinking` | Enhanced reasoning | ✅ Working | NPM @modelcontextprotocol/server-sequential-thinking |
| `context7` | Documentation lookup | ✅ Working | NPM @upstash/context7-mcp |
| `mcp-nixos` | NixOS package/option search | ✅ Working | Nix run github:utensils/mcp-nixos |
| `mcp-filesystem` | Filesystem operations | ✅ Working | NPM @modelcontextprotocol/server-filesystem |
| `cli-mcp-server` | CLI command execution | ✅ Working | Nix run /home/tim/src/cli-mcp-server |

**Architecture Simplification (2025-08-27)**: Removed complex nixmcp framework in favor of language-appropriate tools (NPM for TypeScript, Nix run for Nix packages).

## Architecture

### Simplified Template-Based Approach (Current)
- **NPM Template**: For TypeScript/JavaScript servers via `npx`
- **Nix Run Template**: For servers with Nix flakes via `nix run`
- **Direct Binary Template**: For packaged binaries on PATH
- **No Complex Framework**: Each server uses its native tooling

### Module Structure
```
home/modules/
├── mcp-servers.nix              # User-facing configuration
├── claude-code.nix              # Main orchestration + WSL-aware config generation
└── claude-code/
    ├── mcp-servers.nix          # Server implementation definitions
    ├── hooks.nix                # Development workflow hooks
    ├── sub-agents.nix           # AI sub-agent configurations
    └── slash-commands.nix       # Command shortcuts
```

### Configuration Flow

1. **User enables servers** in `mcp-servers.nix`
2. **Server definitions** in `claude-code/mcp-servers.nix` create configurations
3. **Dual configuration generation** in `claude-code.nix`:
   - `~/.claude/mcp.json` for claude-code (excludes redundant filesystem/CLI)
   - `~/claude-mcp-config.json` for Claude Desktop (includes all servers)
4. **WSL wrapper** applied for Windows Claude Desktop compatibility
5. **Home Manager** deploys configurations with platform-specific adaptations

## Key Features

### WSL-Aware Configuration
Automatically detects WSL environment and wraps commands for Windows Claude Desktop:

```nix
# Converts Linux commands to WSL-wrapped Windows commands
command = "C:\\WINDOWS\\system32\\wsl.exe"
args = ["-d" "NixOS" "-e" "sh" "-c" "ENVVAR=value exec /nix/store/.../binary"]
```

### Dual Configuration Strategy
- **claude-code**: Optimized server list (excludes filesystem/CLI as redundant)
- **Claude Desktop**: Full server list with WSL wrappers for Windows compatibility

### Environment Variable Handling
Embeds environment variables directly in WSL shell commands to ensure proper passing:
```bash
sh -c 'ALLOWED_DIR=/tmp DEBUG="" NODE_ENV=production exec /path/to/server'
```

## Usage

### Basic Configuration

```nix
# In your home.nix or equivalent
{
  imports = [ ./modules/mcp-servers.nix ];
  
  programs.claude-code = {
    enable = true;
    defaultModel = "sonnet";
    
    mcpServers = {
      sequentialThinking.enable = true;
      context7.enable = true;
      nixos.enable = false;  # Disabled due to watchfiles
      mcpFilesystem.enable = false;  # Disabled due to watchfiles
      cliMcpServer.enable = true;
    };
  };
}
```

### Apply Configuration

```bash
# Stage changes (required for flake)
git add home/modules/

# Apply Home Manager configuration
nix run home-manager -- switch --flake '.#user@hostname'

# Restart Claude Desktop to load new servers
restart_claude
```

## Technical Solutions

### Problem: Watchfiles Test Failures
**Issue**: Python `watchfiles` package has sandbox-incompatible tests affecting FastMCP servers.

**Root Cause**: Flake inputs have isolated dependency trees; overlays don't propagate even with `inputs.nixpkgs.follows`.

**Current Workaround**: Disabled affected servers locally, but they build from GitHub.

**Investigation (2025-08-21)**:
1. ✅ Confirmed watchfiles 1.0.5 in nixpkgs has test failures in sandbox
2. ✅ Verified nixmcp already has watchfiles overlay fix applied
3. ✅ Tested builds from GitHub work: `nix build github:timblaktu/nixmcp#mcp-nixos`
4. ❌ Local overlay attempts with `pythonPackagesExtensions` failed to propagate
5. ❌ Direct `python311Packages` and `python312Packages` overrides also failed
6. ✅ Identified tests failing: `test_watch_polling_not_env` and `test_watch`

**Attempted Solutions**:
1. ✅ Added overlay to disable watchfiles tests in nixmcp - fix committed to repo
2. ❌ Overlay doesn't propagate when nixmcp is imported as flake input
3. ⚠️ Local overlay in nixcfg also doesn't affect nixmcp packages
4. ✅ GitHub builds work as a viable alternative deployment strategy

**Potential Future Solutions**:
1. Use GitHub builds as separate flake input or binary cache
2. Apply overlay at nixpkgs level before passing to nixmcp
3. Fork and fix watchfiles upstream test issues
4. Wait for watchfiles 1.1.0+ with potential fixes

### Problem: WSL Path Resolution
**Issue**: Windows Claude Desktop couldn't find Nix store paths.

**Solution**: WSL wrapper with embedded environment variables:
```nix
mkClaudeDesktopServer = name: serverCfg: 
  let
    envPrefix = lib.concatStringsSep " " (lib.mapAttrsToList 
      (k: v: "${k}=${lib.escapeShellArg (toString v)}") 
      serverCfg.env);
    wslCommand = "sh -c '${envPrefix} exec ${serverCfg.command} ${args}'";
  in {
    command = "C:\\WINDOWS\\system32\\wsl.exe";
    args = ["-d" wslDistroName "-e" "sh" "-c" wslCommand];
  };
```

### Problem: Incorrect Package Names
**Issue**: context7 package name was wrong.

**Solution**: Use `@upstash/context7-mcp` instead of `context7`.

### Problem: Module Path Errors
**Issue**: sequential-thinking used wrong module name.

**Solution**: Use `sequential_thinking_mcp.server` not `server_fastmcp`.

### Problem: Sequential-thinking Runtime Error
**Issue**: Server fails with TaskGroup exception on startup.

**Investigation (2025-08-21)**:
1. ✅ Confirmed binary exists at `/bin/sequential-thinking-mcp`
2. ✅ Tested both module (`-m sequential_thinking_mcp.server`) and binary execution
3. ❌ Both methods produce: `Fatal error: unhandled errors in a TaskGroup (1 sub-exception)`
4. ✅ Server starts and shows session ID before crashing
5. ❌ Error occurs in stdio_server implementation, not configuration

**Current Status**: Runtime bug in upstream sequential-thinking-mcp implementation.

## Adding New MCP Servers

### 1. Define Configuration Options

In `claude-code/mcp-servers.nix`:
```nix
newServer = {
  enable = mkEnableOption "description";
  timeout = mkOption {
    type = types.int;
    default = 300;
  };
  # Add server-specific options
};
```

### 2. Implement Server Definition

```nix
optionalAttrs cfg.mcpServers.newServer.enable {
  new-server = mkMcpServer {
    command = "npx";  # or Python binary path
    args = ["-y" "@org/package-name"];
    env = {
      API_KEY = cfg.mcpServers.newServer.apiKey;
    };
    timeout = cfg.mcpServers.newServer.timeout;
  };
}
```

### 3. Enable in Configuration

```nix
programs.claude-code.mcpServers.newServer.enable = true;
```

## Troubleshooting

### Check Generated Configurations
```bash
# Claude-code configuration
cat ~/.claude/mcp.json | jq

# Claude Desktop configuration  
cat ~/claude-mcp-config.json | jq
```

### View Claude Desktop Logs
```bash
tail -f /tmp/claude_desktop.log

# Windows log location
ls /mnt/wsl/*/mnt/c/Users/*/AppData/Roaming/Claude/logs/
```

### Test MCP Server Manually

#### Build Testing:
```bash
# Test individual servers in nixmcp
nix build github:timblaktu/nixmcp#mcp-nixos

# Test in home configuration
nix build '.#homeConfigurations.user@host.activationPackage'
```

#### NPM-based servers:
```bash
timeout 5 npx -y @upstash/context7-mcp
```

#### Python-based servers:
```bash
PYTHONPATH=/nix/store/.../site-packages \
  /nix/store/.../bin/python3.12 -m module.server

# Test with MCP protocol
echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | /path/to/server
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Server disconnected | Missing environment variables | Check env vars in WSL command |
| ENOENT errors | Hardcoded paths | Use dynamic store paths or WSL wrapper |
| Module not found | Wrong Python module name | Check actual module structure |
| Package not found | Incorrect npm package name | Verify in npm registry |
| JSON parse error | Server not outputting proper MCP | Check if it's actually an MCP server |

## Slash Commands Architecture (2025-09-01)

### The Symlink Problem
Home-manager creates symlinks from git-tracked locations to Nix store:
```bash
# Before: Symlinks that change every rebuild
claude-runtime/.claude-pro/commands/nixmemory.sh -> /nix/store/abc123/nixmemory
```
This caused constant git noise as store paths changed with each rebuild.

### The Static Wrapper Solution
We redesigned slash commands using static wrappers:
```bash
# After: Static files that never change
#!/usr/bin/env bash
exec claude-nixmemory "$@"
```

Benefits:
- **Zero git churn** - Files never change after creation
- **Clean updates** - Implementation updates via PATH
- **Unix philosophy** - Standard command resolution pattern

See `claude-code/memory-commands-static.nix` for implementation.

## Future Improvements

1. **Additional servers**: brave-search, puppeteer, github, gitlab
2. **Performance monitoring** of server startup times
3. **Security hardening** of allowed paths and directories
4. **Extend static wrapper pattern** to all slash commands

## Architecture Benefits

- **Declarative Configuration**: All servers defined in Nix
- **Cross-Platform Support**: Works on WSL, Linux, Windows Claude Desktop
- **Reproducible Builds**: Nix ensures consistent deployments
- **Modular Design**: Easy to add/remove servers
- **Platform Detection**: Automatic WSL/native adaptation
- **Dual Client Support**: Optimized for both claude-code and Claude Desktop

## Related Files

- `CLAUDE.md` - Project memory and configuration status
- `home/files/bin/restart_claude` - Claude Desktop restart script
- `overlays/default.nix` - Watchfiles test disable overlay
- `flake-modules/packages.nix` - Custom package definitions

## Recent Work Summary (2025-08-21)

### Investigation Phase
- Researched watchfiles package for upstream fixes in versions 1.0.5+ and potential FastMCP alternatives
- Analyzed FastMCP dependency on watchfiles for file watching functionality
- Cloned and examined nixmcp repository to understand overlay implementation
- Tested builds directly from GitHub repository, confirming they work

### Implementation Phase
- Updated sequential-thinking configuration to use binary instead of Python module
- Created comprehensive watchfiles overlays using both `pythonPackagesExtensions` and direct overrides
- Modified server configurations to use nixmcp packages properly
- Temporarily disabled servers with local build issues while keeping GitHub builds as reference

### Key Findings
- **Build Dichotomy**: Servers build successfully from GitHub but fail locally due to test sandboxing
- **Overlay Limitation**: Nix flake inputs have isolated dependency trees preventing overlay propagation
- **Sequential-thinking Bug**: Upstream implementation has TaskGroup error, not a configuration issue
- **Viable Workaround**: GitHub builds provide working binaries that could be used via binary cache

### Current State
- 2 servers fully operational (context7, cli-mcp-server)
- 2 servers build from GitHub but disabled locally (mcp-nixos, mcp-filesystem)
- 1 server has upstream runtime bug (sequential-thinking)
- Documentation fully updated with investigation results and technical findings

## Credits

This implementation represents the culmination of extensive development to achieve reliable cross-platform MCP server deployment through creative Nix-based solutions.