#!/data/data/com.termux/files/usr/bin/bash
##
## OpenCode - Open Source AI Coding Agent
##
## Installs OpenCode via npm and provides the 'opencode' command for Termux.
## This package is a dependency for opencode-wrappers.
##

TERMUX_PKG_HOMEPAGE=https://opencode.ai
TERMUX_PKG_DESCRIPTION="Open source AI coding agent"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Tim Blaktu @timblaktu"
TERMUX_PKG_VERSION=0.1.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

# Requires Node.js and npm for installation
TERMUX_PKG_DEPENDS="nodejs-lts"

termux_step_make_install() {
	# Install OpenCode globally via npm
	# Note: We install to a temporary location and then move files to avoid
	# npm's automatic symlinking which can cause issues with Termux packaging

	echo "Installing OpenCode via npm..."

	# Create temporary npm prefix
	TEMP_NPM_PREFIX="$TERMUX_PKG_TMPDIR/npm-global"
	mkdir -p "$TEMP_NPM_PREFIX"

	# Install to temporary prefix
	npm install -g --prefix "$TEMP_NPM_PREFIX" @opencode-ai/sdk

	# Copy the installed files to the package prefix
	# npm installs to lib/node_modules/ and creates symlinks in bin/
	if [ -d "$TEMP_NPM_PREFIX/lib/node_modules/@opencode-ai/sdk" ]; then
		# Create node_modules directory structure
		mkdir -p "$TERMUX_PREFIX/lib/node_modules/@opencode-ai"

		# Copy the module
		cp -r "$TEMP_NPM_PREFIX/lib/node_modules/@opencode-ai/sdk" \
		      "$TERMUX_PREFIX/lib/node_modules/@opencode-ai/"

		# Create symlink in bin/
		mkdir -p "$TERMUX_PREFIX/bin"
		ln -sf "$TERMUX_PREFIX/lib/node_modules/@opencode-ai/sdk/bin/opencode.js" \
		       "$TERMUX_PREFIX/bin/opencode"

		echo "OpenCode installed successfully"
	else
		echo "ERROR: npm installation failed - module not found" >&2
		exit 1
	fi

	# Create basic README
	mkdir -p "$TERMUX_PREFIX/share/doc/opencode"
	cat > "$TERMUX_PREFIX/share/doc/opencode/README.md" << 'EOREADME'
# OpenCode for Termux

Open source AI coding agent, packaged for Termux.

## Usage

```bash
# Interactive mode
opencode

# Single prompt
opencode "help me with bash"

# Show version
opencode --version

# Show help
opencode --help
```

## Configuration

OpenCode stores configuration in `~/.opencode/` by default.

## Multi-Account Setup

For managing multiple OpenCode accounts, install the `opencode-wrappers` package:

```bash
pkg install opencode-wrappers
```

This provides:
- `opencodemax` - OpenCode Max account
- `opencodepro` - OpenCode Pro account
- `opencodework` - Custom proxy setup

## Documentation

- Official docs: https://opencode.ai/docs
- Source code: https://github.com/anomalyco/opencode
- Package source: https://github.com/timblaktu/nixcfg/tree/main/tur-package/opencode

## Troubleshooting

If `opencode` command is not found after installation:
1. Verify installation: `ls -l $PREFIX/bin/opencode`
2. Check node_modules: `ls -l $PREFIX/lib/node_modules/@opencode-ai/`
3. Reinstall: `pkg reinstall opencode`

Report issues at: https://github.com/timblaktu/tur/issues
EOREADME
}

termux_step_create_debscripts() {
	# Post-installation message
	cat > ./postinst << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenCode Installed                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "OpenCode is now available via the 'opencode' command."
echo ""
echo "Quick start:"
echo "  opencode              - Interactive mode"
echo "  opencode \"help me\"    - Single prompt"
echo "  opencode --help       - Show all options"
echo ""
echo "Configuration:"
echo "  OpenCode stores config in ~/.opencode/ directory"
echo ""
echo "Multi-account setup:"
echo "  Install opencode-wrappers for account switching:"
echo "  pkg install opencode-wrappers"
echo ""
echo "Documentation:"
echo "  $PREFIX/share/doc/opencode/README.md"
echo "  https://opencode.ai/docs"
echo ""
EOF

	chmod 0755 ./postinst

	# Pre-removal message (warn about removing wrappers)
	cat > ./prerm << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Check if opencode-wrappers is installed
if dpkg -l opencode-wrappers 2>/dev/null | grep -q '^ii'; then
	echo ""
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║  WARNING: opencode-wrappers installed                         ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "The opencode-wrappers package depends on opencode."
	echo "Removing opencode will break opencodemax, opencodepro, opencodework."
	echo ""
	echo "Consider removing opencode-wrappers first:"
	echo "  pkg remove opencode-wrappers"
	echo ""
	read -p "Continue removing opencode? [y/N] " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
fi
exit 0
EOF

	chmod 0755 ./prerm
}
