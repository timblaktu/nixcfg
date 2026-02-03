# Claude Code for Termux

Official Anthropic CLI for Claude, packaged for Termux via TUR (Termux User Repository).

## Overview

This package installs Claude Code, the official command-line interface for Claude AI, making it available as the `claude` command in Termux.

**Package Type**: npm wrapper
**Installation Method**: Installs `@anthropic-ai/claude-code` from npm
**Dependencies**: nodejs-lts (provides npm)

## Installation

### From TUR Repository

```bash
# Add repository (if not already added)
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update and install
pkg update
pkg install claude-code

# Verify installation
claude --version
```

### Quick Setup Script

```bash
curl -sSL https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh | bash
pkg install claude-code
```

## Usage

### Basic Commands

```bash
# Interactive mode
claude

# Single prompt
claude "help me with bash scripting"

# Pipe content
cat script.sh | claude "review this code"

# File analysis
claude "explain this file" < script.sh

# Show version
claude --version

# Show help
claude --help
```

### Configuration

Claude Code stores configuration in `~/.claude/` directory:

```
~/.claude/
├── settings.json      # User settings
├── .claude.json       # Runtime state
└── logs/              # Session logs
```

### Authentication

Claude Code requires authentication on first run:
1. Run `claude` for the first time
2. Follow the authentication prompts
3. Authentication token is stored securely

## Multi-Account Management

For managing multiple Claude accounts (Max, Pro, Work), install the companion package:

```bash
pkg install claude-wrappers
```

This provides:
- `claudemax` - Claude Max account wrapper
- `claudepro` - Claude Pro account wrapper
- `claudework` - Custom proxy configuration
- `claude-setup-work` - Work account configuration helper

See `claude-wrappers` package documentation for details.

## Package Details

### What Gets Installed

- **Binary**: `/data/data/com.termux/files/usr/bin/claude` (symlink)
- **Module**: `/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/`
- **Docs**: `/data/data/com.termux/files/usr/share/doc/claude-code/README.md`

### Installation Method

This package uses npm to install Claude Code:
1. Downloads `@anthropic-ai/claude-code` from npm
2. Installs to Termux prefix (`/data/data/com.termux/files/usr`)
3. Creates symlink: `$PREFIX/bin/claude` → node_modules binary
4. No modification of upstream code

### Dependencies

- **nodejs-lts** (required) - Provides Node.js runtime and npm

### Version Tracking

Package version follows upstream Claude Code releases:
- Package version: `0.1.0` (initial TUR release)
- Upstream version: Installed from npm (may be newer)
- Check upstream: `npm view @anthropic-ai/claude-code version`

## Updating

```bash
# Update package list
pkg update

# Upgrade claude-code
pkg upgrade claude-code

# Or reinstall for fresh installation
pkg reinstall claude-code
```

**Note**: Updates follow TUR package updates, which may lag behind npm releases. For bleeding-edge versions, use npm directly:

```bash
npm install -g @anthropic-ai/claude-code
```

## Troubleshooting

### Command Not Found

```bash
# Check if binary exists
ls -l $PREFIX/bin/claude

# Check node_modules
ls -l $PREFIX/lib/node_modules/@anthropic-ai/

# Reinstall
pkg reinstall claude-code
```

### Permission Errors

```bash
# Ensure proper ownership
chown -R $(whoami) ~/.claude
chmod 700 ~/.claude
```

### npm Installation Failures

```bash
# Check Node.js installation
node --version
npm --version

# Reinstall Node.js
pkg reinstall nodejs-lts

# Retry claude-code installation
pkg reinstall claude-code
```

### Authentication Issues

```bash
# Remove cached authentication
rm -rf ~/.claude/.claude.json

# Re-authenticate
claude
```

## Uninstallation

```bash
# Remove package
pkg remove claude-code

# Also remove configuration (optional)
rm -rf ~/.claude
```

**Warning**: If `claude-wrappers` is installed, it will break after removing `claude-code`. Remove `claude-wrappers` first if you want to fully uninstall.

## Architecture

### Why npm Wrapper?

This package wraps npm installation rather than vendoring the binary because:

1. **Upstream Compatibility**: Claude Code updates frequently; npm ensures latest stable
2. **Size Efficiency**: No need to vendor large Node.js binaries
3. **Maintenance**: Upstream handles platform compatibility
4. **Simplicity**: Leverages existing npm infrastructure

### Package Relationships

```
claude-code (this package)
    ↓ installs binary
claudemax, claudepro, claudework
    ↓ provided by
claude-wrappers (optional companion)
```

## Development

### Building Locally

```bash
# Clone TUR fork
git clone https://github.com/timblaktu/tur.git
cd tur

# Copy package definition
cp -r ~/termux-src/nixcfg/tur-package/claude-code tur/

# Build (requires termux-packages environment)
./build-package.sh claude-code
```

### Testing

```bash
# Install locally built package
pkg install ./claude-code_*.deb

# Test commands
claude --version
claude "hello"

# Test with wrappers
pkg install claude-wrappers
claudemax --version
```

### Source Code

- **Package source**: https://github.com/timblaktu/nixcfg/tree/main/tur-package/claude-code
- **TUR fork**: https://github.com/timblaktu/tur
- **Upstream Claude Code**: https://github.com/anthropics/claude-code

## Known Limitations

1. **Offline Installation**: Requires network for npm download during installation
2. **Version Lag**: TUR package updates may lag behind npm releases
3. **npm Dependency**: Requires Node.js and npm (relatively large dependencies)

## Alternatives

### Direct npm Installation

```bash
pkg install nodejs-lts
npm install -g @anthropic-ai/claude-code
```

**Pros**: Latest version immediately
**Cons**: No Termux package management, manual updates, no integration with claude-wrappers

### Official Installation

Follow upstream docs: https://docs.anthropic.com/claude-code

## Resources

### Documentation
- [Upstream docs](https://docs.anthropic.com/claude-code)
- [GitHub repository](https://github.com/anthropics/claude-code)
- [npm package](https://www.npmjs.com/package/@anthropic-ai/claude-code)

### Related Packages
- [claude-wrappers](https://github.com/timblaktu/nixcfg/tree/main/tur-package/claude-wrappers) - Multi-account management
- [TUR](https://github.com/termux-user-repository/tur) - Termux User Repository

### Support
- **TUR Issues**: https://github.com/timblaktu/tur/issues
- **Package Source Issues**: https://github.com/timblaktu/nixcfg/issues
- **Claude Code Issues**: https://github.com/anthropics/claude-code/issues

## License

- **This package**: MIT (packaging only)
- **Claude Code**: Proprietary (Anthropic Inc.)

## Changelog

### Version 0.1.0-1 (2026-01-19)
- Initial TUR release
- npm wrapper installation
- Integration with claude-wrappers
- Comprehensive documentation
- Post-install and pre-removal scripts

---

**Maintained by**: Tim Blaktu (@timblaktu)
**Package Repository**: https://timblaktu.github.io/tur
**Last Updated**: 2026-01-19
