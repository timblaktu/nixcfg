# modules/programs/github-auth [nd]/github-auth.nix
# GitHub authentication configuration for home-manager
#
# Provides:
#   flake.modules.homeManager.github-auth - GitHub CLI with Bitwarden/SOPS token injection
#
# Features:
#   - GitHub CLI (gh) with automatic token injection
#   - Bitwarden or SOPS secret backend
#   - Subcommand-specific token overrides (e.g., classic PAT for cross-fork PRs)
#   - Nix access-tokens configuration for rate-limit-free GitHub fetches
#   - Git credential helper integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.github-auth ];
#   gitAuth.github = {
#     enable = true;
#     bitwarden = {
#       item = "github.com";
#       field = "PAT-mytoken";
#     };
#   };
#
# Subcommand-specific token overrides (e.g., classic PAT for cross-fork PRs):
#   gitAuth.github.cli.tokenOverrides = {
#     pr = {
#       item = "github.com";
#       field = "PAT-classic";
#     };
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === Home Manager GitHub Auth Module ===
    homeManager.github-auth = { config, lib, pkgs, options, ... }:
      with lib;
      let
        cfg = config.gitAuth.github;

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

        # ===== GitHub CLI wrappers =====

        # GitHub CLI wrapper with Bitwarden token injection and subcommand overrides
        gh-with-auth =
          let
            bwConfig = resolveBwConfig cfg.bitwarden;

            # Generate shell case branches for each override
            overrideCases = concatStringsSep "\n      " (mapAttrsToList
              (subcommand: override: ''
                ${subcommand})
                  GH_TOKEN="$(${rbwLib.mkRbwGetCommand { inherit (override) item field; }} 2>/dev/null)"
                  ;;'')
              cfg.cli.tokenOverrides);

            # Default case uses the main bitwarden config
            defaultCase = ''
              *)
                  GH_TOKEN="$(${rbwLib.mkRbwGetCommand { inherit (bwConfig) item field; }} 2>/dev/null)"
                  ;;'';

            # Build the complete case statement (only if overrides exist)
            tokenSelection =
              if cfg.cli.tokenOverrides == { } then ''
                # No overrides configured, use default token
                GH_TOKEN="$(${rbwLib.mkRbwGetCommand { inherit (bwConfig) item field; }} 2>/dev/null)"''
              else ''
                # Select token based on subcommand
                case "''${1:-}" in
                  ${overrideCases}
                  ${defaultCase}
                esac'';
          in
          pkgs.writeShellScriptBin "gh" ''
            ${rbwLib.mkRbwSyncIfStale { staleSeconds = cfg.rbwSyncInterval; }}
            ${rbwLib.mkClearGitCredentialCache}
            ${tokenSelection}
            export GH_TOKEN
            exec ${pkgs.gh}/bin/gh "$@"
          '';

        # GitHub CLI wrapper with SOPS token injection
        gh-with-auth-sops = pkgs.writeShellScriptBin "gh" ''
          ${if options ? sops then ''
            TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"
            if [ -f "$TOKEN_FILE" ]; then
              export GH_TOKEN="$(cat "$TOKEN_FILE")"
            fi
          '' else ''
            echo "Warning: SOPS mode configured but SOPS module not available" >&2
          ''}
          exec ${pkgs.gh}/bin/gh "$@"
        '';

        # Select wrapper based on mode
        ghWrapper = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;

      in
      {
        options.gitAuth.github = {
          enable = mkEnableOption "GitHub authentication";

          mode = mkModeOption;
          protocol = mkProtocolOption;
          rbwSyncInterval = mkRbwSyncIntervalOption;

          bitwarden = mkBitwardenOptions {
            defaultTokenName = "github-token";
            exampleItem = "github.com";
          };

          sops = mkSopsOptions {
            defaultSecretName = "github_token";
            # Note: Path is relative to flake root when used
            defaultSecretsFile = ../../../secrets/common/github.yaml;
          };

          git = mkGitCredentialOptions {
            defaultUserName = null; # GitHub doesn't need explicit username
          };

          cli = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Install and configure GitHub CLI (gh)";
            };

            enableAliases = mkOption {
              type = types.bool;
              default = true;
              description = "Enable useful gh aliases";
            };

            tokenOverrides = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  item = mkOption {
                    type = types.str;
                    description = "Bitwarden item name for this subcommand";
                  };
                  field = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Bitwarden field name (null for password)";
                  };
                };
              });
              default = { };
              description = ''
                Subcommand-specific token overrides. Maps gh subcommand names to
                alternative Bitwarden credentials.

                Use case: Fine-grained PATs work for most operations, but cross-fork
                PR creation to upstream repos (e.g., NixOS/nixpkgs) requires a
                classic PAT with broader permissions.

                The wrapper checks the first argument (subcommand) against these
                overrides and uses the matching credentials if found.
              '';
              example = literalExpression ''
                {
                  pr = {
                    item = "github.com";
                    field = "PAT-classic";
                  };
                }
              '';
            };
          };

          nix = {
            enableAccessToken = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Configure nix access-tokens for authenticated GitHub fetches.
                This prevents rate limiting errors when fetching from GitHub.
                Token will be stored in ~/.config/nix/github-token (mode 600).
              '';
            };
          };
        };

        config = mkIf cfg.enable {
          # GitHub CLI configuration
          programs.gh = mkIf cfg.cli.enable {
            enable = true;
            package = ghWrapper;

            settings = mkMerge [
              {
                git_protocol = cfg.protocol;
              }
              (mkIf cfg.cli.enableAliases {
                aliases = {
                  pv = "pr view";
                  rv = "repo view";
                  prs = "pr list";
                  issues = "issue list";
                };
              })
            ];
          };

          # Git credential configuration for GitHub
          programs.git.settings = mkIf cfg.git.enableCredentialHelper {
            credential = {
              "https://github.com" = mkMerge [
                {
                  helper = mkForce "!${ghWrapper}/bin/gh auth git-credential";
                }
                (mkIf (cfg.git.userName != null) {
                  username = cfg.git.userName;
                })
              ];
              "https://gist.github.com" = {
                helper = mkForce "!${ghWrapper}/bin/gh auth git-credential";
              };
            };
          };

          # Bitwarden mode: informational activation check
          home.activation.githubAuthBitwarden = mkIf (cfg.mode == "bitwarden")
            (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
                $DRY_RUN_CMD echo "ℹ️  Note: Bitwarden vault is locked. GitHub auth will fail until you run: rbw unlock"
              else
                $DRY_RUN_CMD echo "✅ Bitwarden unlocked - GitHub authentication ready"
              fi
            '');

          # Setup GitHub token for nix access-tokens
          home.activation.setupNixGithubToken = mkIf cfg.nix.enableAccessToken
            (lib.hm.dag.entryAfter [ "writeBoundary" ] (
              let
                bwConfig = resolveBwConfig cfg.bitwarden;
                rbwGetCmd = rbwLib.mkRbwGetCommand { inherit (bwConfig) item field; };
              in
              ''
                TOKEN_DIR="$HOME/.config/nix"
                TOKEN_FILE="$TOKEN_DIR/github-token"

                mkdir -p "$TOKEN_DIR"

                if [ "''${DRY_RUN:-0}" != "1" ]; then
                  if [ "${cfg.mode}" = "bitwarden" ]; then
                    TOKEN="$(${rbwGetCmd} 2>/dev/null || true)"
                    if [ -n "$TOKEN" ]; then
                      echo "$TOKEN" > "$TOKEN_FILE"
                      chmod 600 "$TOKEN_FILE"
                      $DRY_RUN_CMD echo "✅ GitHub token for nix stored in ~/.config/nix/github-token"
                    else
                      if [ -f "$TOKEN_FILE" ]; then
                        $DRY_RUN_CMD echo "ℹ️  Using existing GitHub token file for nix"
                      else
                        $DRY_RUN_CMD echo "⚠️  No GitHub token found. Create one at https://github.com/settings/tokens"
                        $DRY_RUN_CMD echo "    Store it in ~/.config/nix/github-token with permissions 600"
                        $DRY_RUN_CMD echo "    Required scopes: read:packages (or just 'repo' for private repos)"
                      fi
                    fi
                  elif [ "${cfg.mode}" = "sops" ]; then
                    ${optionalString (options ? sops) ''
                      TOKEN_SRC="${config.sops.secrets."${cfg.sops.secretName}".path}"
                      if [ -f "$TOKEN_SRC" ]; then
                        cp "$TOKEN_SRC" "$TOKEN_FILE"
                        chmod 600 "$TOKEN_FILE"
                        $DRY_RUN_CMD echo "✅ GitHub token for nix copied from SOPS"
                      else
                        $DRY_RUN_CMD echo "⚠️  SOPS secret not available for GitHub token"
                      fi
                    ''}
                    ${optionalString (!(options ? sops)) ''
                      $DRY_RUN_CMD echo "⚠️  SOPS mode configured but SOPS module not available"
                    ''}
                  fi
                fi
              ''
            ));

          # Configure nix to use the token file
          nix.settings = mkIf cfg.nix.enableAccessToken {
            extra-access-tokens = "${config.home.homeDirectory}/.config/nix/github-token";
          };

          # Assertions
          assertions = [
            {
              assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
              message = "gitAuth.github with bitwarden mode requires secretsManagement.enable = true";
            }
          ];

          # Warnings
          warnings =
            optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
              "gitAuth.github: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
        };
      };
  };
}
