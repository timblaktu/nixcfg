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

  # Bitwarden credential helper script for GitHub
  rbwCredentialHelper = pkgs.writeShellScript "git-credential-rbw" ''
    #!/usr/bin/env bash
    # Git credential helper that fetches token from Bitwarden via rbw

    # Read git's credential request from stdin
    eval "$(cat | sed 's/^/INPUT_/')"

    # Only handle github.com
    if [[ "$INPUT_host" != "github.com" ]]; then
      exit 0
    fi

    # Fetch token from Bitwarden
    TOKEN=$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)

    if [ -n "$TOKEN" ]; then
      echo "protocol=https"
      echo "host=github.com"
      echo "username=${cfg.git.userName}"
      echo "password=$TOKEN"
    fi
  '';

  # Bitwarden credential helper script for GitLab
  rbwGitlabCredentialHelper = pkgs.writeShellScript "git-credential-rbw-gitlab" ''
    #!/usr/bin/env bash
    # Git credential helper that fetches GitLab token from Bitwarden via rbw

    # Read git's credential request from stdin
    eval "$(cat | sed 's/^/INPUT_/')"

    # Only handle the configured GitLab host
    if [[ "$INPUT_host" != "${cfg.gitlab.host}" ]]; then
      exit 0
    fi

    # Fetch token from Bitwarden
    TOKEN=$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)

    if [ -n "$TOKEN" ]; then
      echo "protocol=https"
      echo "host=${cfg.gitlab.host}"
      echo "username=${cfg.gitlab.git.userName}"
      echo "password=$TOKEN"
    fi
  '';

  # SOPS credential helper script for GitHub
  sopsCredentialHelper = pkgs.writeShellScript "git-credential-sops" ''
    #!/usr/bin/env bash
    # Git credential helper that reads token from SOPS secret

    eval "$(cat | sed 's/^/INPUT_/')"

    if [[ "$INPUT_host" != "github.com" ]]; then
      exit 0
    fi

    TOKEN_FILE="${config.sops.secrets."${cfg.sops.secretName}".path}"

    if [ -f "$TOKEN_FILE" ]; then
      TOKEN=$(cat "$TOKEN_FILE")
      echo "protocol=https"
      echo "host=github.com"
      echo "username=${cfg.git.userName}"
      echo "password=$TOKEN"
    fi
  '';

  # SOPS credential helper script for GitLab
  sopsGitlabCredentialHelper = pkgs.writeShellScript "git-credential-sops-gitlab" ''
    #!/usr/bin/env bash
    # Git credential helper that reads GitLab token from SOPS secret

    eval "$(cat | sed 's/^/INPUT_/')"

    if [[ "$INPUT_host" != "${cfg.gitlab.host}" ]]; then
      exit 0
    fi

    TOKEN_FILE="${config.sops.secrets."${cfg.gitlab.sops.secretName}".path}"

    if [ -f "$TOKEN_FILE" ]; then
      TOKEN=$(cat "$TOKEN_FILE")
      echo "protocol=https"
      echo "host=${cfg.gitlab.host}"
      echo "username=${cfg.gitlab.git.userName}"
      echo "password=$TOKEN"
    fi
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
      # Git credential configuration for GitHub
      programs.git = {
        extraConfig = mkMerge [
          (mkIf cfg.git.enableCredentialHelper {
            credential = {
              # Use mkForce to override the existing helper definition from git.nix
              helper = mkForce [
                "cache --timeout=${toString cfg.git.cacheTimeout}"
                (if cfg.mode == "bitwarden" then "${rbwCredentialHelper}" else "${sopsCredentialHelper}")
              ];
              "https://github.com" = {
                username = cfg.git.userName;
              };
            };
          })
          # GitLab credential configuration
          (mkIf (cfg.gitlab.enable && cfg.gitlab.git.enableCredentialHelper) {
            credential."https://${cfg.gitlab.host}" = {
              username = cfg.gitlab.git.userName;
              helper = (if cfg.mode == "bitwarden" then "${rbwGitlabCredentialHelper}" else "${sopsGitlabCredentialHelper}");
            };
          })
        ];
      };

      # GitHub CLI configuration
      programs.gh = mkIf cfg.gh.enable {
        enable = true;

        settings = mkMerge [
          {
            git_protocol = cfg.protocol;
            # Token fetched via git credential helper
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

      # GitLab CLI installation
      home.packages = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) [ pkgs.glab ];

      # Setup shell aliases for GitHub and GitLab CLI automatic authentication
      programs.bash.shellAliases = mkMerge [
        (mkIf cfg.gh.enable {
          gh = "GH_TOKEN=\"$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)\" ${pkgs.gh}/bin/gh";
        })
        (mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) {
          glab = "GITLAB_TOKEN=\"$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)\" ${pkgs.glab}/bin/glab";
        })
      ];

      programs.zsh.shellAliases = mkMerge [
        (mkIf cfg.gh.enable {
          gh = "GH_TOKEN=\"$(${mkRbwCommand cfg.bitwarden} 2>/dev/null)\" ${pkgs.gh}/bin/gh";
        })
        (mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) {
          glab = "GITLAB_TOKEN=\"$(${mkRbwCommand cfg.gitlab.bitwarden} 2>/dev/null)\" ${pkgs.glab}/bin/glab";
        })
      ];

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
