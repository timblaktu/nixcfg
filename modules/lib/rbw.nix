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

  # Default timeouts (seconds)
  defaultSyncTimeoutSeconds = 10;
  defaultGetTimeoutSeconds = 5;

  # Build the rbw get command string, hard-bounded by timeout(1).
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional, defaults to password)
  #   getTimeoutSeconds: Hard timeout for the get call (default: 5)
  # Returns: Shell command string. Exit 124 indicates timeout.
  mkRbwGetCommand = { item, field ? null, getTimeoutSeconds ? defaultGetTimeoutSeconds }:
    let
      rbwBin = "${pkgs.rbw}/bin/rbw";
      timeoutBin = "${pkgs.coreutils}/bin/timeout";
      itemArg = escapeShellArg item;
      fieldArg =
        if field != null && field != ""
        then ''--field ${escapeShellArg field}''
        else "";
    in
    "${timeoutBin} ${toString getTimeoutSeconds}s ${rbwBin} get ${itemArg} ${fieldArg}";

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
  mkRbwSyncIfStale = { staleSeconds ? defaultStaleSeconds, syncTimeoutSeconds ? defaultSyncTimeoutSeconds }:
    let
      rbwBin = "${pkgs.rbw}/bin/rbw";
      timeoutBin = "${pkgs.coreutils}/bin/timeout";
      flockBin = "${pkgs.util-linux}/bin/flock";
    in
    ''
      # Time-based rbw sync: only sync if last sync was >${toString staleSeconds}s ago.
      # Hard-bounded by timeout(1) and serialized via non-blocking flock so a stuck
      # rbw-agent (Bitwarden 503 cascade, network drop) cannot hang the wrapper or
      # cause N concurrent wrappers to pile sync requests onto the agent.
      _RBW_SYNC_FILE="''${XDG_RUNTIME_DIR:-/tmp}/.rbw-last-sync-$USER"
      _RBW_SYNC_LOCK="''${XDG_RUNTIME_DIR:-/tmp}/.rbw-sync-$USER.lock"
      _RBW_NOW=$(date +%s)
      _RBW_LAST_SYNC=$(stat -c %Y "$_RBW_SYNC_FILE" 2>/dev/null || echo 0)
      _RBW_SYNC_AGE=$((_RBW_NOW - _RBW_LAST_SYNC))
      if [ "$_RBW_SYNC_AGE" -gt ${toString staleSeconds} ]; then
        [ -e "$_RBW_SYNC_LOCK" ] || : > "$_RBW_SYNC_LOCK" 2>/dev/null || true
        # -n: non-blocking try-lock; -E 0: exit 0 if lock unavailable (another wrapper is syncing)
        ${flockBin} -n -E 0 "$_RBW_SYNC_LOCK" \
          ${timeoutBin} ${toString syncTimeoutSeconds}s ${rbwBin} sync 2>/dev/null || true
      fi
      # Always touch marker (even on timeout/failure/skipped) to prevent retry storms
      # when the agent is wedged.
      touch "$_RBW_SYNC_FILE" 2>/dev/null || true
      unset _RBW_SYNC_FILE _RBW_SYNC_LOCK _RBW_NOW _RBW_LAST_SYNC _RBW_SYNC_AGE
    '';

  # Build shell code that syncs (if stale) then gets a credential
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional, defaults to password)
  #   staleSeconds: Seconds after which to consider cache stale (default: 300)
  #   suppressErrors: If true, redirect stderr to /dev/null (default: true)
  # Returns: Shell code string that outputs the credential value
  mkRbwGetWithSync =
    { item
    , field ? null
    , staleSeconds ? defaultStaleSeconds
    , syncTimeoutSeconds ? defaultSyncTimeoutSeconds
    , getTimeoutSeconds ? defaultGetTimeoutSeconds
    , suppressErrors ? true
    }:
    let
      getCmd = mkRbwGetCommand { inherit item field getTimeoutSeconds; };
      errorRedirect = if suppressErrors then "2>/dev/null" else "";
    in
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds syncTimeoutSeconds; }}
      ${getCmd} ${errorRedirect}'';

  # Build shell code for credential retrieval with detailed error messages
  # Useful for wrappers where users need diagnostic information
  # Arguments:
  #   item: Bitwarden item name (required)
  #   field: Field within item (optional)
  #   staleSeconds: Staleness threshold (default: 300)
  #   varName: Environment variable name to export (required)
  # Returns: Shell code that exports the variable with error handling
  mkRbwExportWithDiagnostics =
    { item
    , field ? null
    , staleSeconds ? defaultStaleSeconds
    , syncTimeoutSeconds ? defaultSyncTimeoutSeconds
    , getTimeoutSeconds ? defaultGetTimeoutSeconds
    , varName
    }:
    let
      getCmd = mkRbwGetCommand { inherit item field getTimeoutSeconds; };
      fieldDesc =
        if field != null && field != ""
        then "Field: ${field}"
        else "(default password)";
    in
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds syncTimeoutSeconds; }}
      if command -v rbw >/dev/null 2>&1; then
        ${varName}="$(${getCmd} </dev/null 2>/dev/null)"
        _RBW_RC=$?
        if [ "$_RBW_RC" -ne 0 ]; then
          if [ "$_RBW_RC" -eq 124 ]; then
            echo "Warning: [timeout after ${toString getTimeoutSeconds}s] rbw get hung — likely rbw-agent deadlock, network issue, or vault locked" >&2
          else
            echo "Warning: Failed to retrieve credential from Bitwarden (exit $_RBW_RC)" >&2
          fi
          echo "   Item: ${item}, ${fieldDesc}" >&2
          # Do NOT exit; let downstream tool surface its own missing-credential error.
        fi
        unset _RBW_RC
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
  mkGitAuthSetup =
    { item
    , field ? null
    , varName
    , staleSeconds ? defaultStaleSeconds
    , syncTimeoutSeconds ? defaultSyncTimeoutSeconds
    , getTimeoutSeconds ? defaultGetTimeoutSeconds
    }:
    ''
      ${mkRbwSyncIfStale { inherit staleSeconds syncTimeoutSeconds; }}
      ${mkClearGitCredentialCache}
      export ${varName}="$(${mkRbwGetCommand { inherit item field getTimeoutSeconds; }} 2>/dev/null)"
    '';
}
