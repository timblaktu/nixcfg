# GitLab Authentication Module
# Provides seamless GitLab authentication using Bitwarden or SOPS
#
# This module is the GitLab counterpart to github-auth.nix.
# Both modules share common infrastructure via lib/git-forge-auth.nix.
#
# Usage:
#   gitAuth.gitlab = {
#     enable = true;
#     host = "gitlab.com";  # or your self-hosted instance
#     bitwarden = {
#       item = "gitlab.com";
#       field = "api-token";
#     };
#   };
#
{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.gitAuth.gitlab;

  # Import shared git forge authentication library
  gitForgeLib = import ./lib/git-forge-auth.nix { inherit pkgs lib config options; };
  inherit (gitForgeLib) rbwLib resolveBwConfig;

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

    mode = gitForgeLib.mkModeOption;
    protocol = gitForgeLib.mkProtocolOption;
    rbwSyncInterval = gitForgeLib.mkRbwSyncIntervalOption;

    bitwarden = gitForgeLib.mkBitwardenOptions {
      defaultTokenName = "gitlab-token";
      exampleItem = "gitlab.com";
    };

    sops = gitForgeLib.mkSopsOptions {
      defaultSecretName = "gitlab_token";
      defaultSecretsFile = ../../secrets/common/gitlab.yaml;
    };

    git = gitForgeLib.mkGitCredentialOptions {
      defaultUserName = "oauth2";
    };

    cli = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Install and configure GitLab CLI (glab)";
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
        hosts:
          ${cfg.host}:
            git_protocol: ${cfg.protocol}
            api_protocol: https
        display_hyperlinks: true
        glamour_style: dark
        editor: ${config.home.sessionVariables.EDITOR or "vim"}
        EOF
                chmod 600 "$CONFIG_FILE"
                $DRY_RUN_CMD echo "✅ GitLab CLI configured for ${cfg.host} (token via env var)"
      '');

    # Bitwarden mode: informational activation check
    home.activation.gitlabAuthBitwarden = mkIf (cfg.mode == "bitwarden")
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
          $DRY_RUN_CMD echo "ℹ️  Note: Bitwarden vault is locked. GitLab auth will fail until you run: rbw unlock"
        else
          $DRY_RUN_CMD echo "✅ Bitwarden unlocked - GitLab authentication ready (${cfg.host})"
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
}
