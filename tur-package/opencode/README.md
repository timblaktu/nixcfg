# OpenCode for Termux

Open source AI coding agent, packaged for Termux via TUR (Termux User Repository).

## Overview

This package installs OpenCode, an open source AI coding agent, making it available as the `opencode` command in Termux.

**Package Type**: npm wrapper
**Installation Method**: Installs `@opencode-ai/sdk` from npm
**Dependencies**: nodejs-lts (provides npm)

## Installation

### From TUR Repository

```bash
# Add repository (if not already added)
echo "deb [trusted=yes] https://timblaktu.github.io/tur stable main" | \
  tee $PREFIX/etc/apt/sources.list.d/timblaktu-tur.list

# Update and install
pkg update
pkg install opencode

# Verify installation
opencode --version
```

### Quick Setup Script

```bash
curl -sSL https://raw.githubusercontent.com/timblaktu/nixcfg/main/tur-package/nixcfg-integration/setup-termux-repos.sh | bash
pkg install opencode
```

## Usage

### Basic Commands

```bash
# Interactive mode
opencode

# Single prompt
opencode "help me with bash scripting"

# Pipe content
cat script.sh | opencode "review this code"

# File analysis
opencode "explain this file" < script.sh

# Show version
opencode --version

# Show help
opencode --help
```

### Configuration

OpenCode stores configuration in `~/.opencode/` directory:

```
~/.opencode/
├── settings.json      # User settings
├── .opencode.json     # Runtime state
└── logs/              # Session logs
```

### Authentication

OpenCode requires authentication on first run:
1. Run `opencode` for the first time
2. Follow the authentication prompts
3. Authentication token is stored securely

## Multi-Account Management

For managing multiple OpenCode accounts (Max, Pro, Work), install the companion package:

```bash
pkg install opencode-wrappers
```

This provides:
- `opencodemax` - OpenCode Max account wrapper
- `opencodepro` - OpenCode Pro account wrapper
- `opencodework` - Custom proxy configuration
- `opencode-setup-work` - Work account configuration helper

See `opencode-wrappers` package documentation for details.

## Package Details

### What Gets Installed

- **Binary**: `/data/data/com.termux/files/usr/bin/opencode` (symlink)
- **Module**: `/data/data/com.termux/files/usr/lib/node_modules/@opencode-ai/sdk/`
- **Docs**: `/data/data/com.termux/files/usr/share/doc/opencode/README.md`

### Installation Method

This package uses npm to install OpenCode:
1. Downloads `@opencode-ai/sdk` from npm
2. Installs to Termux prefix (`/data/data/com.termux/files/usr`)
3. Creates symlink: `$PREFIX/bin/opencode` → node_modules binary
4. No modification of upstream code

### Dependencies

- **nodejs-lts** (required) - Provides Node.js runtime and npm

### Version Tracking

Package version follows upstream OpenCode releases:
- Package version: `0.1.0` (initial TUR release)
- Upstream version: Installed from npm (may be newer)
- Check upstream: `npm view @opencode-ai/sdk version`

## Updating

```bash
# Update package list
pkg update

# Upgrade opencode
pkg upgrade opencode

# Or reinstall for fresh installation
pkg reinstall opencode
```

**Note**: Updates follow TUR package updates, which may lag behind npm releases. For bleeding-edge versions, use npm directly:

```bash
npm install -g @opencode-ai/sdk
```

## Troubleshooting

### Command Not Found

```bash
# Check if binary exists
ls -l $PREFIX/bin/opencode

# Check node_modules
ls -l $PREFIX/lib/node_modules/@opencode-ai/

# Reinstall
pkg reinstall opencode
```

### Permission Errors

```bash
# Ensure proper ownership
chown -R $(whoami) ~/.opencode
chmod 700 ~/.opencode
```

### npm Installation Failures

```bash
# Check Node.js installation
node --version
npm --version

# Reinstall Node.js
pkg reinstall nodejs-lts

# Retry opencode installation
pkg reinstall opencode
```

### Authentication Issues

```bash
# Remove cached authentication
rm -rf ~/.opencode/.opencode.json

# Re-authenticate
opencode
```

## Uninstallation

```bash
# Remove package
pkg remove opencode

# Also remove configuration (optional)
rm -rf ~/.opencode
```

**Warning**: If `opencode-wrappers` is installed, it will break after removing `opencode`. Remove `opencode-wrappers` first if you want to fully uninstall.

## Architecture

### Why npm Wrapper?

This package wraps npm installation rather than vendoring the binary because:

1. **Upstream Compatibility**: OpenCode updates frequently; npm ensures latest stable
2. **Size Efficiency**: No need to vendor large Node.js binaries
3. **Maintenance**: Upstream handles platform compatibility
4. **Simplicity**: Leverages existing npm infrastructure

### Package Relationships

```
opencode (this package)
    ↓ installs binary
opencodemax, opencodepro, opencodework
    ↓ provided by
opencode-wrappers (optional companion)
```

## Development

### Building Locally

```bash
# Clone TUR fork
git clone https://github.com/timblaktu/tur.git
cd tur

# Copy package definition
cp -r ~/termux-src/nixcfg/tur-package/opencode tur/

# Build (requires termux-packages environment)
./build-package.sh opencode
```

### Testing

```bash
# Install locally built package
pkg install ./opencode_*.deb

# Test commands
opencode --version
opencode "hello"

# Test with wrappers
pkg install opencode-wrappers
opencodemax --version
```

### Source Code

- **Package source**: https://github.com/timblaktu/nixcfg/tree/main/tur-package/opencode
- **TUR fork**: https://github.com/timblaktu/tur
- **Upstream OpenCode**: https://github.com/anomalyco/opencode

## Known Limitations

1. **Offline Installation**: Requires network for npm download during installation
2. **Version Lag**: TUR package updates may lag behind npm releases
3. **npm Dependency**: Requires Node.js and npm (relatively large dependencies)

## Alternatives

### Direct npm Installation

```bash
pkg install nodejs-lts
npm install -g @opencode-ai/sdk
```

**Pros**: Latest version immediately
**Cons**: No Termux package management, manual updates, no integration with opencode-wrappers

### Official Installation

Follow upstream docs: https://opencode.ai/docs

## Resources

### Documentation
- [Upstream docs](https://opencode.ai/docs)
- [GitHub repository](https://github.com/anomalyco/opencode)
- [npm package](https://www.npmjs.com/package/@opencode-ai/sdk)

### Related Packages
- [opencode-wrappers](https://github.com/timblaktu/nixcfg/tree/main/tur-package/opencode-wrappers) - Multi-account management
- [TUR](https://github.com/termux-user-repository/tur) - Termux User Repository

### Support
- **TUR Issues**: https://github.com/timblaktu/tur/issues
- **Package Source Issues**: https://github.com/timblaktu/nixcfg/issues
- **OpenCode Issues**: https://github.com/anomalyco/opencode/issues

## License

- **This package**: MIT (packaging only)
- **OpenCode**: MIT (Open Source)

## Changelog

### Version 0.1.0-1 (2026-01-19)
- Initial TUR release
- npm wrapper installation
- Integration with opencode-wrappers
- Comprehensive documentation
- Post-install and pre-removal scripts

---

**Maintained by**: Tim Blaktu (@timblaktu)
**Package Repository**: https://timblaktu.github.io/tur
**Last Updated**: 2026-01-19
