# GitHub and GitLab Authentication Module
# Provides seamless GitHub and GitLab authentication using Bitwarden or SOPS
{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.githubAuth;

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
    TOKEN=$(${pkgs.rbw}/bin/rbw get "${cfg.bitwarden.tokenName}" 2>/dev/null)

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

    # Only handle gitlab.com
    if [[ "$INPUT_host" != "gitlab.com" ]]; then
      exit 0
    fi

    # Fetch token from Bitwarden
    TOKEN=$(${pkgs.rbw}/bin/rbw get "${cfg.gitlab.bitwarden.tokenName}" 2>/dev/null)

    if [ -n "$TOKEN" ]; then
      echo "protocol=https"
      echo "host=gitlab.com"
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

    if [[ "$INPUT_host" != "gitlab.com" ]]; then
      exit 0
    fi

    TOKEN_FILE="${config.sops.secrets."${cfg.gitlab.sops.secretName}".path}"

    if [ -f "$TOKEN_FILE" ]; then
      TOKEN=$(cat "$TOKEN_FILE")
      echo "protocol=https"
      echo "host=gitlab.com"
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
        description = "Bitwarden entry name for GitHub token";
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
          description = "Bitwarden entry name for GitLab token";
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

      # GitLab CLI installation and configuration
      home.packages = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) [ pkgs.glab ];

      # GitLab CLI configuration file
      home.file.".config/glab-cli/config.yml" = mkIf (cfg.gitlab.enable && cfg.gitlab.glab.enable) {
        text = ''
          # GitLab CLI configuration
          # Token authentication handled via git credential helper
          hosts:
            ${cfg.gitlab.host}:
              git_protocol: ${cfg.protocol}
              api_protocol: https
          display_hyperlinks: true
          glamour_style: dark
          editor: ${config.home.sessionVariables.EDITOR or "vim"}
        '';
      };

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
