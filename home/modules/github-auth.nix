# GitHub and GitLab Authentication Module
# Provides seamless GitHub and GitLab authentication using Bitwarden or SOPS
{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.githubAuth;

  # Helper function to construct rbw command based on configuration
  # Supports both old tokenName format and new item/field format
  mkRbwCommand = bwCfg:
    if bwCfg.field != null then
      ''${pkgs.rbw}/bin/rbw get --field "${bwCfg.field}" "${bwCfg.item}"''
    else if bwCfg.item != null then
      ''${pkgs.rbw}/bin/rbw get "${bwCfg.item}"''
    else
    # Backward compatibility: use tokenName if item is not set
      ''${pkgs.rbw}/bin/rbw get "${bwCfg.tokenName}"'';

  # GitHub CLI wrapper with Bitwarden token injection
  # This wrapper fetches the token from Bitwarden and exports it as GH_TOKEN
  # Used for BOTH CLI operations and git credential helper operations
  gh-with-auth = pkgs.writeShellScriptBin "gh" ''
    export GH_TOKEN="$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)"
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  # GitLab CLI wrapper with Bitwarden token injection
  # This wrapper fetches the token from Bitwarden and exports it as GITLAB_TOKEN
  # Used for BOTH CLI operations and git credential helper operations
  glab-with-auth = pkgs.writeShellScriptBin "glab" ''
    export GITLAB_TOKEN="$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)"
    exec ${pkgs.glab}/bin/glab "$@"
  '';

  # SOPS-based wrappers (for when mode == "sops")
  # GitHub CLI wrapper with SOPS token injection
  gh-with-auth-sops = pkgs.writeShellScriptBin "gh" ''
    TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"
    if [ -f "$TOKEN_FILE" ]; then
      export GH_TOKEN="$(cat "$TOKEN_FILE")"
    fi
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  # GitLab CLI wrapper with SOPS token injection
  glab-with-auth-sops = pkgs.writeShellScriptBin "glab" ''
    TOKEN_FILE="${config.sops.secrets."${cfg.gitlab.sops.secretName}".path}"
    if [ -f "$TOKEN_FILE" ]; then
      export GITLAB_TOKEN="$(cat "$TOKEN_FILE")"
    fi
    exec ${pkgs.glab}/bin/glab "$@"
  '';

in
{
  options.githubAuth = {
    enable = mkEnableOption "GitHub authentication";

    mode = mkOption {
      type = types.enum [ "bitwarden" "sops" ];
      default = "bitwarden";
      description = "Secret backend to use for GitHub token";
    };

    protocol = mkOption {
      type = types.enum [ "https" "ssh" ];
      default = "https";
      description = "Git protocol for GitHub operations";
    };

    bitwarden = {
      tokenName = mkOption {
        type = types.str;
        default = "github-token";
        description = ''
          Bitwarden entry name for GitHub token.
          Deprecated: Use 'item' and 'field' for more control.
        '';
      };

      item = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Bitwarden item name (e.g., "github.com").
          Takes precedence over tokenName if set.
        '';
        example = "github.com";
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

    sops = {
      secretName = mkOption {
        type = types.str;
        default = "github_token";
        description = "Secret name in SOPS file";
      };

      secretsFile = mkOption {
        type = types.path;
        default = ../../secrets/common/github.yaml;
        description = "Path to SOPS secrets file";
      };
    };

    git = {
      enableCredentialHelper = mkOption {
        type = types.bool;
        default = true;
        description = "Configure git credential helper";
      };

      cacheTimeout = mkOption {
        type = types.int;
        default = 3600;
        description = "Credential cache timeout in seconds";
      };

      userName = mkOption {
        type = types.str;
        default = "token";
        description = "Username for HTTPS authentication";
      };
    };

    gh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Configure GitHub CLI (gh)";
      };

      enableAliases = mkOption {
        type = types.bool;
        default = true;
        description = "Enable useful gh aliases";
      };
    };

    gitlab = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable GitLab authentication and CLI";
      };

      host = mkOption {
        type = types.str;
        default = "gitlab.com";
        description = "GitLab host (for self-hosted instances)";
      };

      bitwarden = {
        tokenName = mkOption {
          type = types.str;
          default = "gitlab-token";
          description = ''
            Bitwarden entry name for GitLab token.
            Deprecated: Use 'item' and 'field' for more control.
          '';
        };

        item = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Bitwarden item name (e.g., "gitlab.com").
            Takes precedence over tokenName if set.
          '';
          example = "gitlab.com";
        };

        field = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Custom field name within the Bitwarden item.
            If null, retrieves the password field.
            Only used when 'item' is set.
          '';
          example = "api-token";
        };
      };

      sops = {
        secretName = mkOption {
          type = types.str;
          default = "gitlab_token";
          description = "Secret name in SOPS file for GitLab";
        };

        secretsFile = mkOption {
          type = types.path;
          default = ../../secrets/common/gitlab.yaml;
          description = "Path to SOPS secrets file for GitLab";
        };
      };

      git = {
        enableCredentialHelper = mkOption {
          type = types.bool;
          default = true;
          description = "Configure git credential helper for GitLab";
        };

        userName = mkOption {
          type = types.str;
          default = "oauth2";
          description = "Username for HTTPS authentication with GitLab";
        };
      };

      glab = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Configure GitLab CLI (glab)";
        };

        enableAliases = mkOption {
          type = types.bool;
          default = true;
          description = "Enable useful glab aliases";
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Install glab wrapper (gh wrapper is installed via programs.gh.package)
      # These wrappers inject tokens from Bitwarden/SOPS and are used for:
      # 1. CLI operations (when user types 'glab')
      # 2. Git credential operations (via 'glab auth git-credential')
      home.packages = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) [
        (if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops)
      ];

      # Git credential configuration using wrapper scripts
      programs.git = {
        extraConfig = mkMerge [
          (mkIf cfg.git.enableCredentialHelper {
            credential = {
              # Use the wrapped gh command for GitHub credential operations
              # The wrapper injects the token from Bitwarden/SOPS, then calls
              # the official 'gh auth git-credential' subcommand
              "https://github.com" = {
                username = cfg.git.userName;
                helper = mkForce
                  (
                    let
                      ghWrapper = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;
                    in
                    "!${ghWrapper}/bin/gh auth git-credential"
                  );
              };
              "https://gist.github.com" = {
                helper = mkForce
                  (
                    let
                      ghWrapper = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;
                    in
                    "!${ghWrapper}/bin/gh auth git-credential"
                  );
              };
            };
          })
          # GitLab credential configuration
          (mkIf (cfg.gitlab.enable && cfg.gitlab.git.enableCredentialHelper) {
            credential."https://${cfg.gitlab.host}" = {
              username = cfg.gitlab.git.userName;
              # Use the wrapped glab command for GitLab credential operations
              helper =
                let
                  glabWrapper = if cfg.mode == "bitwarden" then glab-with-auth else glab-with-auth-sops;
                in
                "!${glabWrapper}/bin/glab auth git-credential";
            };
          })
        ];
      };

      # GitHub CLI configuration
      programs.gh = mkIf cfg.gh.enable {
        enable = true;

        # Use our wrapper instead of the regular gh package
        package = if cfg.mode == "bitwarden" then gh-with-auth else gh-with-auth-sops;

        settings = mkMerge [
          {
            git_protocol = cfg.protocol;
            # Token fetched via wrapper script (not via git credential helper)
          }
          # Additional useful aliases (merged with existing)
          (mkIf cfg.gh.enableAliases {
            aliases = {
              pv = "pr view";
              rv = "repo view";
              prs = "pr list";
              issues = "issue list";
            };
          })
        ];
      };

      # Create glab config file WITHOUT token (token provided via GITLAB_TOKEN env var)
      home.activation.glabConfig = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable)
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
          host: ${cfg.gitlab.host}
          hosts:
            ${cfg.gitlab.host}:
              git_protocol: ${cfg.protocol}
              api_protocol: https
          display_hyperlinks: true
          glamour_style: dark
          editor: ${config.home.sessionVariables.EDITOR or "vim"}
          EOF
          chmod 600 "$CONFIG_FILE"
          $DRY_RUN_CMD echo "✅ GitLab CLI configured for ${cfg.gitlab.host} (token via env var)"
        '');

      # Bitwarden mode: informational activation check
      home.activation.githubAuthBitwarden = mkIf (cfg.mode == "bitwarden")
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Non-blocking check if rbw is unlocked
          if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
            $DRY_RUN_CMD echo "ℹ️  Note: Bitwarden vault is locked. GitHub/GitLab auth will fail until you run: rbw unlock"
          else
            $DRY_RUN_CMD echo "✅ Bitwarden unlocked - GitHub${optionalString cfg.gitlab.enable "/GitLab"} authentication ready"
          fi
        '');

      # Assertions
      assertions = [
        {
          assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
          message = "githubAuth with bitwarden mode requires secretsManagement.enable = true";
        }
        # SOPS mode assertion disabled until sops-nix module integration is fixed
        # {
        #   assertion = cfg.mode == "sops" -> ((config.sops.age.keyFile or null) != null);
        #   message = "githubAuth with sops mode requires SOPS age key configuration";
        # }
      ];

      # Warnings
      warnings =
        optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
          "githubAuth: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
    }

    # SOPS mode configuration is intentionally skipped for now
    # as the sops-nix module is not loaded in all contexts.
    # To enable SOPS support, ensure sops-nix is imported and
    # configure the secrets manually.
  ]);
}
