# Shared rbw (Bitwarden CLI) helpers
#
# Provides consistent rbw operations across all modules that need
# credential management via Bitwarden.
#
# Features:
# - Time-based sync to ensure fresh credentials without excessive network calls
# - Consistent command construction for item/field retrieval
# - Configurable staleness threshold (default: 5 minutes)
#
# Usage in other modules:
#   let
#     rbwLib = import ../lib/rbw.nix { inherit pkgs lib; };
#   in
#   rbwLib.mkRbwGetWithSync {
#     item = "github.com";
#     field = "PAT-token";  # optional
#     staleSeconds = 300;   # optional, default 300
#   }
#
{ pkgs, lib }:

let
  inherit (lib) escapeShellArg;
in
rec {
  # Default staleness threshold in seconds (5 minutes)
  defaultStaleSeconds = 300;

  # Build the rbw get command string
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional, defaults to password)
  # Returns: Shell command string
  mkRbwGetCommand = { item, field ? null }:
    let
      rbwBin = "${pkgs.rbw}/bin/rbw";
      itemArg = escapeShellArg item;
      fieldArg =
        if field != null && field != ""
        then ''--field ${escapeShellArg field}''
        else "";
    in
    "${rbwBin} get ${itemArg} ${fieldArg}";

  # Build shell code that syncs rbw if last sync was too long ago
  # Arguments:
  #   staleSeconds: Seconds after which to consider cache stale (default: 300)
  # Returns: Shell code string that performs conditional sync
  #
  # Implementation notes:
  # - Uses XDG_RUNTIME_DIR for sync timestamp file (tmpfs, cleared on reboot)
  # - Falls back to /tmp if XDG_RUNTIME_DIR not set
  # - Sync failures are non-fatal (|| true) to handle offline scenarios
  # - Touch timestamp after sync attempt (even if failed) to prevent retry storm
  mkRbwSyncIfStale = { staleSeconds ? defaultStaleSeconds }:
    let
      rbwBin = "${pkgs.rbw}/bin/rbw";
    in
    ''
      # Time-based rbw sync: only sync if last sync was >${toString staleSeconds}s ago
      _RBW_SYNC_FILE="''${XDG_RUNTIME_DIR:-/tmp}/.rbw-last-sync-$USER"
      _RBW_NOW=$(date +%s)
      _RBW_LAST_SYNC=$(stat -c %Y "$_RBW_SYNC_FILE" 2>/dev/null || echo 0)
      _RBW_SYNC_AGE=$((_RBW_NOW - _RBW_LAST_SYNC))
      if [ "$_RBW_SYNC_AGE" -gt ${toString staleSeconds} ]; then
        ${rbwBin} sync 2>/dev/null || true
        touch "$_RBW_SYNC_FILE" 2>/dev/null || true
      fi
      unset _RBW_SYNC_FILE _RBW_NOW _RBW_LAST_SYNC _RBW_SYNC_AGE
    '';

  # Build shell code that syncs (if stale) then gets a credential
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional, defaults to password)
  #   staleSeconds: Seconds after which to consider cache stale (default: 300)
  #   suppressErrors: If true, redirect stderr to /dev/null (default: true)
  # Returns: Shell code string that outputs the credential value
  mkRbwGetWithSync = { item, field ? null, staleSeconds ? defaultStaleSeconds, suppressErrors ? true }:
    let
      getCmd = mkRbwGetCommand { inherit item field; };
      errorRedirect = if suppressErrors then "2>/dev/null" else "";
    in
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds; }}
      ${getCmd} ${errorRedirect}'';

  # Build shell code for credential retrieval with detailed error messages
  # Useful for wrappers where users need diagnostic information
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional)
  #   staleSeconds: Staleness threshold (default: 300)
  #   varName: Environment variable name to export (required)
  # Returns: Shell code that exports the variable with error handling
  mkRbwExportWithDiagnostics = { item, field ? null, staleSeconds ? defaultStaleSeconds, varName }:
    let
      getCmd = mkRbwGetCommand { inherit item field; };
      fieldDesc =
        if field != null && field != ""
        then "Field: ${field}"
        else "(default password)";
    in
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds; }}
      if command -v rbw >/dev/null 2>&1; then
        ${varName}="$(${getCmd} </dev/null 2>/dev/null)" || {
          echo "Warning: Failed to retrieve credential from Bitwarden" >&2
          echo "   Item: ${item}, ${fieldDesc}" >&2
        }
        export ${varName}
      else
        echo "Error: rbw (Bitwarden CLI) is required but not found" >&2
        exit 1
      fi
    '';

  # Convenience: clear git credential cache
  # Useful when rotating tokens to ensure git doesn't use cached auth
  mkClearGitCredentialCache = ''
    ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true
  '';

  # Combined helper for git-related auth wrappers (gh, glab)
  # Performs sync-if-stale, clears git cache, exports token
  # Arguments:
  #   item: Bitwarden item name
  #   field: Field within item (optional)
  #   varName: Env var to export (e.g., "GH_TOKEN", "GITLAB_TOKEN")
  #   staleSeconds: Staleness threshold (default: 300)
  mkGitAuthSetup = { item, field ? null, varName, staleSeconds ? defaultStaleSeconds }:
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds; }}
      ${mkClearGitCredentialCache}
      export ${varName}="$(${mkRbwGetCommand { inherit item field; }} 2>/dev/null)"
    '';
}
