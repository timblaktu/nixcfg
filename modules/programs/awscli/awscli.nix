# modules/programs/awscli/awscli.nix
# AWS CLI v2 with Azure AD SSO authentication
#
# Provides:
#   flake.modules.homeManager.awscli - AWS CLI v2 with Bitwarden-backed Azure AD login
#
# Features:
#   - AWS CLI v2 installation via programs.awscli
#   - Azure AD SSO via aws-azure-login with rbw credential injection
#   - Nix-managed ~/.aws/config (region, output format, session duration)
#   - Runtime credential injection from Bitwarden (no secrets on disk)
#   - Flexible profile support for multi-account setups
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.awscli ];
#   awscli = {
#     enable = true;
#     azureAuth.enable = true;
#   };
#
# Authentication flow:
#   1. User runs `aws-azure-login` (wrapper)
#   2. Wrapper fetches Azure Tenant ID + App ID URI from Bitwarden via rbw
#   3. Wrapper sets AZURE_TENANT_ID and AZURE_APP_ID_URI env vars
#   4. Real aws-azure-login handles Azure AD SAML auth (browser-based)
#   5. Temporary AWS STS credentials written to ~/.aws/credentials
#   6. AWS CLI uses those credentials for subsequent commands
{ config, lib, inputs, ... }:
{
  flake.modules = {
    homeManager.awscli = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.awscli;

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

        # ===== aws-azure-login wrapper =====
        # Injects Azure AD credentials from Bitwarden, then delegates to real binary
        aws-azure-login-wrapper = pkgs.writeShellScriptBin "aws-azure-login" ''
          ${rbwLib.mkRbwSyncIfStale { staleSeconds = cfg.rbwSyncInterval; }}

          AZURE_TENANT_ID="$(${rbwLib.mkRbwGetCommand {
            item = cfg.azureAuth.bitwarden.item;
            field = cfg.azureAuth.bitwarden.tenantIdField;
          }} 2>/dev/null)" || {
            echo "Error: Failed to retrieve Azure Tenant ID from Bitwarden" >&2
            echo "  Item: ${cfg.azureAuth.bitwarden.item}" >&2
            echo "  Field: ${cfg.azureAuth.bitwarden.tenantIdField}" >&2
            echo "  Ensure rbw is unlocked: rbw unlock" >&2
            exit 1
          }
          export AZURE_TENANT_ID

          AZURE_APP_ID_URI="$(${rbwLib.mkRbwGetCommand {
            item = cfg.azureAuth.bitwarden.item;
            field = cfg.azureAuth.bitwarden.appIdUriField;
          }} 2>/dev/null)" || {
            echo "Error: Failed to retrieve Azure App ID URI from Bitwarden" >&2
            echo "  Item: ${cfg.azureAuth.bitwarden.item}" >&2
            echo "  Field: ${cfg.azureAuth.bitwarden.appIdUriField}" >&2
            exit 1
          }
          export AZURE_APP_ID_URI

          exec ${pkgs.aws-azure-login}/bin/aws-azure-login "$@"
        '';

      in
      {
        options.awscli = {
          enable = mkEnableOption "AWS CLI v2 with optional Azure AD SSO integration";

          defaultRegion = mkOption {
            type = types.str;
            default = "us-west-2";
            description = "Default AWS region";
            example = "us-east-1";
          };

          outputFormat = mkOption {
            type = types.enum [ "json" "yaml" "yaml-stream" "text" "table" ];
            default = "json";
            description = "Default output format for AWS CLI commands";
          };

          rbwSyncInterval = mkOption {
            type = types.int;
            default = 300;
            description = ''
              Seconds before rbw cache is considered stale and triggers a sync.
              Default: 300 (5 minutes). Set to 0 to sync every time.
            '';
          };

          azureAuth = {
            enable = mkEnableOption "Azure AD SSO authentication via aws-azure-login";

            bitwarden = {
              item = mkOption {
                type = types.str;
                default = "Azure AD";
                description = "Bitwarden item name containing Azure AD credentials";
              };

              tenantIdField = mkOption {
                type = types.str;
                default = "Azure Tenant ID";
                description = "Custom field name within the Bitwarden item for Azure Tenant ID";
              };

              appIdUriField = mkOption {
                type = types.str;
                default = "Azure App ID URI";
                description = "Custom field name within the Bitwarden item for Azure App ID URI";
              };
            };

            defaultDurationHours = mkOption {
              type = types.int;
              default = 8;
              description = ''
                Default AWS session duration in hours (1-8).
                Azure AD federation typically allows up to 8 hours.
              '';
            };

            defaultRoleArn = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Default IAM role ARN to assume after Azure AD authentication.
                If null, aws-azure-login will prompt for role selection
                when multiple roles are available.
              '';
              example = "arn:aws:iam::123456789012:role/MyRole";
            };
          };

          extraSettings = mkOption {
            type = types.attrsOf (types.attrsOf types.str);
            default = { };
            description = ''
              Additional profile sections for ~/.aws/config.
              Keys are section names (e.g., "profile staging"), values are
              attribute sets of config keys.
            '';
            example = literalExpression ''
              {
                "profile staging" = {
                  region = "us-east-1";
                  output = "table";
                };
              }
            '';
          };
        };

        config = mkIf cfg.enable (mkMerge [
          # Base: AWS CLI v2 with Nix-managed config
          {
            programs.awscli = {
              enable = true;
              package = pkgs.awscli2;
              settings = mkMerge [
                {
                  "default" = {
                    region = cfg.defaultRegion;
                    output = cfg.outputFormat;
                  };
                }
                (mkIf cfg.azureAuth.enable {
                  "default" = mkMerge [
                    {
                      azure_default_duration_hours = toString cfg.azureAuth.defaultDurationHours;
                    }
                    (mkIf (cfg.azureAuth.defaultRoleArn != null) {
                      azure_default_role_arn = cfg.azureAuth.defaultRoleArn;
                    })
                  ];
                })
                cfg.extraSettings
              ];
            };
          }

          # Azure AD SSO: aws-azure-login wrapper with Bitwarden injection
          (mkIf cfg.azureAuth.enable {
            home.packages = [ aws-azure-login-wrapper ];

            assertions = [
              {
                assertion = config.secretsManagement.enable or false;
                message = "awscli.azureAuth requires secretsManagement.enable = true (for rbw/Bitwarden)";
              }
            ];

            warnings =
              optional ((config.secretsManagement.rbw.email or null) == null)
                "awscli.azureAuth: Bitwarden integration enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
          })
        ]);
      };
  };
}
