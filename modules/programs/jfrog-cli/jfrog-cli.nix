# modules/programs/jfrog-cli/jfrog-cli.nix
# JFrog CLI with Bitwarden/SOPS credential injection
#
# Provides:
#   flake.modules.homeManager.jfrog-cli - JFrog CLI with env-var-based auth
#
# Features:
#   - JFrog CLI installation with credential wrapper
#   - Bitwarden or SOPS secret backend for access token
#   - Env var injection (JF_URL, JF_ACCESS_TOKEN) — no ~/.jfrog/ config files
#   - Time-based rbw sync to avoid excessive network calls
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.jfrog-cli ];
#   jfrogCli = {
#     enable = true;
#     host = "artifinity.nextcloud.aero";
#     bitwarden = {
#       item = "JFrog Artifactory";
#       field = "access-token";
#     };
#   };
#
# Authentication flow:
#   1. User runs `jfrog` (wrapper)
#   2. Wrapper syncs rbw if stale, fetches JF_ACCESS_TOKEN from Bitwarden
#   3. Exports JF_URL and JF_ACCESS_TOKEN
#   4. Execs real jfrog-cli binary with "$@"
{ config, lib, inputs, ... }:
{
  flake.modules = {
    homeManager.jfrog-cli = { config, lib, pkgs, options, ... }:
      with lib;
      let
        cfg = config.jfrogCli;

        # ===== Inline rbw helper library =====
        rbwLib = rec {
          defaultStaleSeconds = 300;

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
        };

        # ===== JFrog CLI wrapper with Bitwarden token injection =====
        jfrog-with-auth = pkgs.writeShellScriptBin "jfrog" ''
          ${rbwLib.mkRbwSyncIfStale { staleSeconds = cfg.rbwSyncInterval; }}

          JF_ACCESS_TOKEN="$(${rbwLib.mkRbwGetCommand {
            inherit (cfg.bitwarden) item;
            inherit (cfg.bitwarden) field;
          }} 2>/dev/null)" || {
            echo "Error: Failed to retrieve JFrog access token from Bitwarden" >&2
            echo "  Item: ${cfg.bitwarden.item}" >&2
            echo "  Field: ${if cfg.bitwarden.field != null then cfg.bitwarden.field else "(default password)"}" >&2
            echo "  Ensure rbw is unlocked: rbw unlock" >&2
            exit 1
          }
          export JF_ACCESS_TOKEN
          export JF_URL="https://${cfg.host}"

          exec ${pkgs.jfrog-cli}/bin/jf "$@"
        '';

        # ===== JFrog CLI wrapper with SOPS token injection =====
        jfrog-with-auth-sops = pkgs.writeShellScriptBin "jfrog" ''
          ${if options ? sops then ''
            TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"
            if [ -f "$TOKEN_FILE" ]; then
              export JF_ACCESS_TOKEN="$(cat "$TOKEN_FILE")"
            else
              echo "Error: SOPS secret file not found: $TOKEN_FILE" >&2
              echo "  Ensure sops-nix is configured and secrets are decrypted" >&2
              exit 1
            fi
          '' else ''
            echo "Error: SOPS mode configured but SOPS module not available" >&2
            exit 1
          ''}
          export JF_URL="https://${cfg.host}"

          exec ${pkgs.jfrog-cli}/bin/jf "$@"
        '';

        # Select wrapper based on mode
        jfrogWrapper = if cfg.mode == "bitwarden" then jfrog-with-auth else jfrog-with-auth-sops;

      in
      {
        options.jfrogCli = {
          enable = mkEnableOption "JFrog CLI with credential injection";

          host = mkOption {
            type = types.str;
            description = "Artifactory hostname (e.g. artifinity.nextcloud.aero)";
            example = "artifactory.example.com";
          };

          mode = mkOption {
            type = types.enum [ "bitwarden" "sops" ];
            default = "bitwarden";
            description = "Secret backend to use for token storage";
          };

          rbwSyncInterval = mkOption {
            type = types.int;
            default = 300;
            description = ''
              Seconds before rbw cache is considered stale and triggers a sync.
              Default: 300 (5 minutes). Set to 0 to sync every time.
            '';
          };

          bitwarden = {
            item = mkOption {
              type = types.str;
              default = "JFrog Artifactory";
              description = "Bitwarden item name containing JFrog credentials";
            };

            field = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Custom field name within the Bitwarden item for the access token.
                If null, retrieves the password field.
              '';
              example = "access-token";
            };
          };

          sops = {
            secretName = mkOption {
              type = types.str;
              default = "jfrog_access_token";
              description = "Secret name in SOPS file";
            };
          };
        };

        config = mkIf cfg.enable {
          home.packages = [ jfrogWrapper ];

          # Bitwarden mode: informational activation check
          home.activation.jfrogAuthBitwarden = mkIf (cfg.mode == "bitwarden")
            (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
                $DRY_RUN_CMD echo "Note: Bitwarden vault is locked. JFrog auth will fail until you run: rbw unlock"
              else
                $DRY_RUN_CMD echo "Bitwarden unlocked - JFrog CLI authentication ready (${cfg.host})"
              fi
            '');

          # Assertions
          assertions = [
            {
              assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
              message = "jfrogCli with bitwarden mode requires secretsManagement.enable = true";
            }
          ];

          # Warnings
          warnings =
            optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
              "jfrogCli: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
        };
      };
  };
}
