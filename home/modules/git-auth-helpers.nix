# Git Authentication Helpers Module
# Provides combined utilities for GitHub and GitLab authentication
#
# This module provides:
# - refresh-git-creds: Force sync rbw and clear git credential cache
#
# It works with whichever forge modules are enabled (GitHub, GitLab, or both).
#
{ config, lib, pkgs, ... }:

with lib;

let
  githubCfg = config.gitAuth.github or { enable = false; };
  gitlabCfg = config.gitAuth.gitlab or { enable = false; };

  # Only enable if at least one forge is enabled
  anyForgeEnabled = githubCfg.enable or false || gitlabCfg.enable or false;

  # Determine if we're using bitwarden mode for any forge
  usingBitwarden =
    (githubCfg.enable or false && (githubCfg.mode or "bitwarden") == "bitwarden") ||
    (gitlabCfg.enable or false && (gitlabCfg.mode or "bitwarden") == "bitwarden");

in
{
  config = mkIf anyForgeEnabled {
    home.packages = [
      # Helper script to refresh credentials from Bitwarden/SOPS
      (pkgs.writeShellScriptBin "refresh-git-creds" ''
        echo "🔄 Refreshing git credentials..."

        ${optionalString usingBitwarden ''
          # Sync Bitwarden vault
          echo "  → Syncing Bitwarden vault..."
          ${pkgs.rbw}/bin/rbw sync 2>/dev/null || echo "    ⚠️  rbw sync failed (vault may be locked)"

          # Clear the sync timestamp to force fresh sync on next command
          rm -f "''${XDG_RUNTIME_DIR:-/tmp}/.rbw-last-sync-$USER" 2>/dev/null || true
        ''}

        # Clear git credential cache
        echo "  → Clearing git credential cache..."
        ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true

        echo "✅ Credentials refreshed!"

        ${optionalString (githubCfg.enable or false) ''
          echo ""
          echo "Testing GitHub authentication..."
          gh auth status 2>&1 || true
        ''}

        ${optionalString (gitlabCfg.enable or false) ''
          echo ""
          echo "Testing GitLab authentication (${gitlabCfg.host or "gitlab.com"})..."
          glab auth status 2>&1 || true
        ''}
      '')
    ];
  };
}
