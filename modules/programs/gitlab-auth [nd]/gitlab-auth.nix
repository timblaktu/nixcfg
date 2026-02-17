# modules/programs/gitlab-auth [nd]/gitlab-auth.nix
# GitLab authentication configuration for home-manager
#
# Provides:
#   flake.modules.homeManager.gitlab-auth - GitLab CLI with Bitwarden/SOPS token injection
#
# Features:
#   - GitLab CLI (glab) with automatic token injection
#   - Bitwarden or SOPS secret backend
#   - Self-hosted GitLab instance support
#   - Git credential helper integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.gitlab-auth ];
#   gitAuth.gitlab = {
#     enable = true;
#     host = "gitlab.com";  # or your self-hosted instance
#     bitwarden = {
#       item = "gitlab.com";
#       field = "api-token";
#     };
#   };
#
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager GitLab Auth Module ===
    homeManager.gitlab-auth = { config, lib, pkgs, options, ... }:
      with lib;
      let
        cfg = config.gitAuth.gitlab;

        # ===== Inline rbw helper library =====
        # (From home/modules/lib/rbw.nix)
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

          mkClearGitCredentialCache = ''
            ${pkgs.git}/bin/git credential-cache exit 2>/dev/null || true
          '';

          mkGitAuthSetup = { item, field ? null, varName, staleSeconds ? defaultStaleSeconds }:
            ''
              ${mkRbwSyncIfStale { inherit staleSeconds; }}
              ${mkClearGitCredentialCache}
              export ${varName}="$(${mkRbwGetCommand { inherit item field; }} 2>/dev/null)"
            '';
        };

        # ===== Inline git-forge-auth helpers =====
        # (From home/modules/lib/git-forge-auth.nix)
        resolveBwConfig = bwCfg:
          if bwCfg.item != null then {
            inherit (bwCfg) item;
            inherit (bwCfg) field;
          } else {
            item = bwCfg.tokenName;
            field = null;
          };

        mkBitwardenOptions = { defaultTokenName, exampleItem ? null }: {
          tokenName = mkOption {
            type = types.str;
            default = defaultTokenName;
            description = ''
              Bitwarden entry name for the token.
              Deprecated: Use 'item' and 'field' for more control.
            '';
          };

          item = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Bitwarden item name.
              Takes precedence over tokenName if set.
            '';
            example = exampleItem;
          };

          field = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Custom field name within the Bitwarden item.
              If null, retrieves the password field.
              Only used when 'item' is set.
            '';
            example = "token";
          };
        };

        mkSopsOptions = { defaultSecretName, defaultSecretsFile }: {
          secretName = mkOption {
            type = types.str;
            default = defaultSecretName;
            description = "Secret name in SOPS file";
          };

          secretsFile = mkOption {
            type = types.path;
            default = defaultSecretsFile;
            description = "Path to SOPS secrets file";
          };
        };

        mkGitCredentialOptions = { defaultUserName ? null }: {
          enableCredentialHelper = mkOption {
            type = types.bool;
            default = true;
            description = "Configure git credential helper for this forge";
          };

          userName = mkOption {
            type = types.nullOr types.str;
            default = defaultUserName;
            description = ''
              Username for HTTPS authentication.
              If null, the credential helper will provide the username.
            '';
          };
        };

        mkModeOption = mkOption {
          type = types.enum [ "bitwarden" "sops" ];
          default = "bitwarden";
          description = "Secret backend to use for token storage";
        };

        mkProtocolOption = mkOption {
          type = types.enum [ "https" "ssh" ];
          default = "https";
          description = "Git protocol for operations";
        };

        mkRbwSyncIntervalOption = mkOption {
          type = types.int;
          default = 300;
          description = ''
            Time in seconds before rbw cache is considered stale and needs sync.
            The sync happens automatically before credential retrieval if the
            last sync was longer than this interval ago.

            Set to 0 to sync on every command (slower but always fresh).
            Set to a larger value (e.g., 3600) if you rarely rotate tokens.

            Default: 300 (5 minutes)
          '';
          example = 600;
        };

        # ===== GitLab CLI wrappers =====

        # GitLab CLI wrapper with Bitwarden token injection
        glab-with-auth =
          let
            bwConfig = resolveBwConfig cfg.bitwarden;
          in
          pkgs.writeShellScriptBin "glab" ''
            ${rbwLib.mkGitAuthSetup {
              inherit (bwConfig) item field;
              varName = "GITLAB_TOKEN";
              staleSeconds = cfg.rbwSyncInterval;
            }}
            exec ${pkgs.glab}/bin/glab "$@"
          '';

        # GitLab CLI wrapper with SOPS token injection
        glab-with-auth-sops = pkgs.writeShellScriptBin "glab" ''
          ${if options ? sops then ''
            TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"
            if [ -f "$TOKEN_FILE" ]; then
              export GITLAB_TOKEN="$(cat "$TOKEN_FILE")"
            fi
          '' else ''
            echo "Warning: SOPS mode configured but SOPS module not available" >&2
          ''}
          exec ${pkgs.glab}/bin/glab "$@"
        '';

        # Select wrapper based on mode
        glabWrapper = if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops;

      in
      {
        options.gitAuth.gitlab = {
          enable = mkEnableOption "GitLab authentication";

          host = mkOption {
            type = types.str;
            default = "gitlab.com";
            description = "GitLab host (for self-hosted instances)";
            example = "gitlab.mycompany.com";
          };

          mode = mkModeOption;
          protocol = mkProtocolOption;
          rbwSyncInterval = mkRbwSyncIntervalOption;

          bitwarden = mkBitwardenOptions {
            defaultTokenName = "gitlab-token";
            exampleItem = "gitlab.com";
          };

          sops = mkSopsOptions {
            defaultSecretName = "gitlab_token";
            # Note: Path is relative to flake root when used
            defaultSecretsFile = ../../../secrets/common/gitlab.yaml;
          };

          git = mkGitCredentialOptions {
            defaultUserName = "oauth2";
          };

          cli = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Install and configure GitLab CLI (glab)";
            };

            apiUser = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                GitLab username for the CLI. Sets the `user` field in
                glab's config.yml. If null, glab falls back to whoami.
              '';
              example = "blackt1";
            };

            enableAliases = mkOption {
              type = types.bool;
              default = true;
              description = "Enable useful glab aliases";
            };
          };
        };

        config = mkIf cfg.enable {
          # Install glab wrapper
          home.packages = mkIf cfg.cli.enable [ glabWrapper ];

          # Git credential configuration for GitLab
          programs.git.settings = mkIf cfg.git.enableCredentialHelper {
            credential."https://${cfg.host}" = mkMerge [
              {
                helper = mkForce "!${glabWrapper}/bin/glab auth git-credential";
              }
              (mkIf (cfg.git.userName != null) {
                username = cfg.git.userName;
              })
            ];
          };

          # Create glab config file (token provided via GITLAB_TOKEN env var)
          home.activation.glabConfig = mkIf cfg.cli.enable
            (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
                    mkdir -p "$HOME/.config/glab-cli"
                    CONFIG_FILE="$HOME/.config/glab-cli/config.yml"

                    # Remove symlink if it exists
                    if [ -L "$CONFIG_FILE" ]; then
                      rm -f "$CONFIG_FILE"
                    fi

                    # Create config WITHOUT token field
                    cat > "$CONFIG_FILE" <<EOF
              # GitLab CLI configuration
              # Token provided via GITLAB_TOKEN environment variable at runtime
              host: ${cfg.host}
              ${lib.optionalString (cfg.cli.apiUser != null) "user: ${cfg.cli.apiUser}"}
              hosts:
                ${cfg.host}:
                  git_protocol: ${cfg.protocol}
                  api_protocol: https
              display_hyperlinks: true
              glamour_style: dark
              editor: ${config.home.sessionVariables.EDITOR or "vim"}
              EOF
                    chmod 600 "$CONFIG_FILE"
                    $DRY_RUN_CMD echo "GitLab CLI configured for ${cfg.host} (token via env var)"
            '');

          # Bitwarden mode: informational activation check
          home.activation.gitlabAuthBitwarden = mkIf (cfg.mode == "bitwarden")
            (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
                $DRY_RUN_CMD echo "Note: Bitwarden vault is locked. GitLab auth will fail until you run: rbw unlock"
              else
                $DRY_RUN_CMD echo "Bitwarden unlocked - GitLab authentication ready (${cfg.host})"
              fi
            '');

          # Assertions
          assertions = [
            {
              assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
              message = "gitAuth.gitlab with bitwarden mode requires secretsManagement.enable = true";
            }
          ];

          # Warnings
          warnings =
            optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
              "gitAuth.gitlab: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
        };
      };
  };
}
