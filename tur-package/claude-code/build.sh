#!/data/data/com.termux/files/usr/bin/bash
##
## Claude Code - Official Anthropic CLI for Claude
##
## Installs Claude Code via npm and provides the 'claude' command for Termux.
## This package is a dependency for claude-wrappers.
##

TERMUX_PKG_HOMEPAGE=https://github.com/anthropics/claude-code
TERMUX_PKG_DESCRIPTION="Official Anthropic CLI for Claude"
TERMUX_PKG_LICENSE="Proprietary"
TERMUX_PKG_MAINTAINER="Tim Blaktu @timblaktu"
TERMUX_PKG_VERSION=0.1.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

# Requires Node.js and npm for installation
TERMUX_PKG_DEPENDS="nodejs-lts"

termux_step_make_install() {
	# Install Claude Code globally via npm
	# Note: We install to a temporary location and then move files to avoid
	# npm's automatic symlinking which can cause issues with Termux packaging

	echo "Installing Claude Code via npm..."

	# Create temporary npm prefix
	TEMP_NPM_PREFIX="$TERMUX_PKG_TMPDIR/npm-global"
	mkdir -p "$TEMP_NPM_PREFIX"

	# Install to temporary prefix
	npm install -g --prefix "$TEMP_NPM_PREFIX" @anthropic-ai/claude-code

	# Copy the installed files to the package prefix
	# npm installs to lib/node_modules/ and creates symlinks in bin/
	if [ -d "$TEMP_NPM_PREFIX/lib/node_modules/@anthropic-ai/claude-code" ]; then
		# Create node_modules directory structure
		mkdir -p "$TERMUX_PREFIX/lib/node_modules/@anthropic-ai"

		# Copy the module
		cp -r "$TEMP_NPM_PREFIX/lib/node_modules/@anthropic-ai/claude-code" \
		      "$TERMUX_PREFIX/lib/node_modules/@anthropic-ai/"

		# Create symlink in bin/
		mkdir -p "$TERMUX_PREFIX/bin"
		ln -sf "$TERMUX_PREFIX/lib/node_modules/@anthropic-ai/claude-code/bin/claude.js" \
		       "$TERMUX_PREFIX/bin/claude"

		echo "Claude Code installed successfully"
	else
		echo "ERROR: npm installation failed - module not found" >&2
		exit 1
	fi

	# Create basic README
	mkdir -p "$TERMUX_PREFIX/share/doc/claude-code"
	cat > "$TERMUX_PREFIX/share/doc/claude-code/README.md" << 'EOREADME'
# Claude Code for Termux

Official Anthropic CLI for Claude, packaged for Termux.

## Usage

```bash
# Interactive mode
claude

# Single prompt
claude "help me with bash"

# Show version
claude --version

# Show help
claude --help
```

## Configuration

Claude Code stores configuration in `~/.claude/` by default.

## Multi-Account Setup

For managing multiple Claude accounts, install the `claude-wrappers` package:

```bash
pkg install claude-wrappers
```

This provides:
- `claudemax` - Claude Max account
- `claudepro` - Claude Pro account
- `claudework` - Custom proxy setup

## Documentation

- Official docs: https://docs.anthropic.com/claude-code
- Source code: https://github.com/anthropics/claude-code
- Package source: https://github.com/timblaktu/nixcfg/tree/main/tur-package/claude-code

## Troubleshooting

If `claude` command is not found after installation:
1. Verify installation: `ls -l $PREFIX/bin/claude`
2. Check node_modules: `ls -l $PREFIX/lib/node_modules/@anthropic-ai/`
3. Reinstall: `pkg reinstall claude-code`

Report issues at: https://github.com/timblaktu/tur/issues
EOREADME
}

termux_step_create_debscripts() {
	# Post-installation message
	cat > ./postinst << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Claude Code Installed                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Claude Code is now available via the 'claude' command."
echo ""
echo "Quick start:"
echo "  claude              - Interactive mode"
echo "  claude \"help me\"    - Single prompt"
echo "  claude --help       - Show all options"
echo ""
echo "Configuration:"
echo "  Claude Code stores config in ~/.claude/ directory"
echo ""
echo "Multi-account setup:"
echo "  Install claude-wrappers for account switching:"
echo "  pkg install claude-wrappers"
echo ""
echo "Documentation:"
echo "  $PREFIX/share/doc/claude-code/README.md"
echo "  https://docs.anthropic.com/claude-code"
echo ""
EOF

	chmod 0755 ./postinst

	# Pre-removal message (warn about removing wrappers)
	cat > ./prerm << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Check if claude-wrappers is installed
if dpkg -l claude-wrappers 2>/dev/null | grep -q '^ii'; then
	echo ""
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║  WARNING: claude-wrappers installed                           ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "The claude-wrappers package depends on claude-code."
	echo "Removing claude-code will break claudemax, claudepro, claudework."
	echo ""
	echo "Consider removing claude-wrappers first:"
	echo "  pkg remove claude-wrappers"
	echo ""
	read -p "Continue removing claude-code? [y/N] " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit 1
	fi
fi
exit 0
EOF

	chmod 0755 ./prerm
}
