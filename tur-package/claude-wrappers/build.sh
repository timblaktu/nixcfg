#!/data/data/com.termux/files/usr/bin/bash
##
## Claude Code Multi-Account Wrappers for Termux
##
## Provides wrapper scripts for managing multiple Claude Code accounts:
## - claudemax:  Claude Max account
## - claudepro:  Claude Pro account
## - claudework: Custom proxy template (requires configuration)
##
## Each wrapper:
## - Sets up account-specific configuration directory
## - Handles API configuration (base URL, authentication, model mappings)
## - Reads bearer tokens from ~/.secrets/ (for proxy accounts)
## - Launches Claude Code with proper environment
##

TERMUX_PKG_HOMEPAGE=https://github.com/timblaktu/nixcfg
TERMUX_PKG_DESCRIPTION="Claude Code multi-account wrapper scripts for Termux"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="Tim Blaktu @timblaktu"
TERMUX_PKG_VERSION=1.0.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

# No hard dependencies on Claude Code itself - wrappers should provide helpful
# error messages if claude binary not found. Dependencies are runtime bash/coreutils.
TERMUX_PKG_DEPENDS="bash"

# Suggests installing Claude Code, but doesn't enforce it
# (Users may have different installation methods)
TERMUX_PKG_SUGGESTS="nodejs-lts"  # Needed for Claude Code installation

termux_step_make_install() {
	# Install wrapper scripts
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/claudemax "$TERMUX_PREFIX"/bin/claudemax
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/claudepro "$TERMUX_PREFIX"/bin/claudepro
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/claudework "$TERMUX_PREFIX"/bin/claudework

	# Install documentation
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR"/README.md "$TERMUX_PREFIX"/share/doc/claude-wrappers/README.md

	# Install setup helper script
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR"/claude-setup-work "$TERMUX_PREFIX"/bin/claude-setup-work
}

termux_step_create_debscripts() {
	# Post-installation message
	cat > ./postinst << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Claude Code Wrappers Installed                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Available commands:"
echo "  claudemax   - Claude Max account"
echo "  claudepro   - Claude Pro account"
echo "  claudework  - Custom proxy (template, edit before use)"
echo ""
echo "To configure claudework for your proxy:"
echo "  1. Edit: \$PREFIX/bin/claudework (set URL and models)"
echo "  2. Run: claude-setup-work (configure bearer token)"
echo ""
echo "Documentation:"
echo "  $PREFIX/share/doc/claude-wrappers/README.md"
echo ""
echo "Note: Claude Code must be installed separately."
echo "      Install with: npm install -g @anthropic/claude-code"
echo ""
EOF

	chmod 0755 ./postinst
}
