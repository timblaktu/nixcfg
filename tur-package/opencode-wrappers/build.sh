#!/data/data/com.termux/files/usr/bin/bash
##
## OpenCode Multi-Account Wrappers for Termux
##
## Provides wrapper scripts for managing multiple OpenCode accounts:
## - opencodemax:  OpenCode Max account
## - opencodepro:  OpenCode Pro account
## - opencodework: Custom proxy template (requires configuration)
##
## Each wrapper:
## - Sets up account-specific configuration directory
## - Handles API configuration (base URL, authentication, model mappings)
## - Reads bearer tokens from ~/.secrets/ (for proxy accounts)
## - Launches OpenCode with proper environment
##

TERMUX_PKG_HOMEPAGE=https://github.com/timblaktu/nixcfg
TERMUX_PKG_DESCRIPTION="OpenCode multi-account wrapper scripts for Termux"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Tim Blaktu @timblaktu"
TERMUX_PKG_VERSION=1.0.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

# No hard dependencies on OpenCode itself - wrappers should provide helpful
# error messages if opencode binary not found. Dependencies are runtime bash/coreutils.
TERMUX_PKG_DEPENDS="bash"

# Suggests installing OpenCode, but doesn't enforce it
# (Users may have different installation methods)
TERMUX_PKG_SUGGESTS="nodejs-lts"  # Needed for OpenCode installation

termux_step_make_install() {
	# Install wrapper scripts
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/opencodemax "$TERMUX_PREFIX"/bin/opencodemax
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/opencodepro "$TERMUX_PREFIX"/bin/opencodepro
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/opencodework "$TERMUX_PREFIX"/bin/opencodework

	# Install documentation
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR"/README.md "$TERMUX_PREFIX"/share/doc/opencode-wrappers/README.md

	# Install setup helper script
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/opencode-setup-work "$TERMUX_PREFIX"/bin/opencode-setup-work
}

termux_step_create_debscripts() {
	# Pre-installation conflict check
	cat > ./preinst << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BINARIES="opencodemax opencodepro opencodework opencode-setup-work"
UNTRACKED=""
CONFLICTS=""

# Check each binary for conflicts
for bin in $BINARIES; do
	BIN_PATH="$PREFIX/bin/$bin"

	if [ -e "$BIN_PATH" ]; then
		# Check if owned by a package
		if OWNER=$(dpkg -S "$BIN_PATH" 2>/dev/null | cut -d: -f1); then
			# Owned by a package - dpkg will handle this with its own error
			# (unless it's this package being reinstalled/upgraded)
			if [ "$OWNER" != "opencode-wrappers" ]; then
				CONFLICTS="$CONFLICTS $bin($OWNER)"
			fi
		else
			# Untracked file - manual installation or leftover
			UNTRACKED="$UNTRACKED $bin"
		fi
	fi
done

# Report untracked files and abort
if [ -n "$UNTRACKED" ]; then
	echo ""
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║  ERROR: File Conflicts Detected                                ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "The following files already exist but are not managed by any package:"
	echo ""
	for bin in $UNTRACKED; do
		echo "  • $PREFIX/bin/$bin"
	done
	echo ""
	echo "These files were likely installed manually or by a script."
	echo ""
	echo "To resolve this conflict, choose ONE of the following options:"
	echo ""
	echo "  Option 1: Backup and remove (RECOMMENDED)"
	echo "    # Create backup"
	echo "    mkdir -p ~/backup/opencode-wrappers-\$(date +%Y%m%d-%H%M%S)"
	for bin in $UNTRACKED; do
		echo "    cp $PREFIX/bin/$bin ~/backup/opencode-wrappers-\$(date +%Y%m%d-%H%M%S)/"
	done
	echo ""
	echo "    # Remove files"
	for bin in $UNTRACKED; do
		echo "    rm $PREFIX/bin/$bin"
	done
	echo ""
	echo "    # Retry installation"
	echo "    pkg install opencode-wrappers"
	echo ""
	echo "  Option 2: Force overwrite (NOT RECOMMENDED - no backup)"
	echo "    # Remove files"
	for bin in $UNTRACKED; do
		echo "    rm $PREFIX/bin/$bin"
	done
	echo "    pkg install opencode-wrappers"
	echo ""
	echo "After resolving conflicts, you can safely install this package."
	echo ""
	exit 1
fi

# Report package conflicts (informational only - dpkg handles these)
if [ -n "$CONFLICTS" ]; then
	echo ""
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║  WARNING: Package Conflicts                                    ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "The following files are owned by other packages:"
	echo ""
	for conflict in $CONFLICTS; do
		echo "  • $conflict"
	done
	echo ""
	echo "dpkg will handle these conflicts automatically."
	echo "You may need to remove the conflicting packages first."
	echo ""
	# Let dpkg handle this with its own error message
fi

exit 0
EOF

	chmod 0755 ./preinst

	# Post-installation message
	cat > ./postinst << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenCode Wrappers Installed                                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Available commands:"
echo "  opencodemax   - OpenCode Max account"
echo "  opencodepro   - OpenCode Pro account"
echo "  opencodework  - Custom proxy (template, edit before use)"
echo ""
echo "To configure opencodework for your proxy:"
echo "  1. Edit: \$PREFIX/bin/opencodework (set URL and models)"
echo "  2. Run: opencode-setup-work (configure bearer token)"
echo ""
echo "Documentation:"
echo "  $PREFIX/share/doc/opencode-wrappers/README.md"
echo ""
echo "Note: OpenCode must be installed separately."
echo "      Install with: npm install -g @opencode-ai/sdk"
echo ""
EOF

	chmod 0755 ./postinst
}
