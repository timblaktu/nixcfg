# GitHub Authentication Module
# Provides seamless GitHub authentication using Bitwarden or SOPS
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.githubAuth;

  # Bitwarden credential helper script
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

  # SOPS credential helper script
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
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Git credential configuration
      programs.git = {
        extraConfig = mkIf cfg.git.enableCredentialHelper {
          credential = {
            helper = [
              "cache --timeout=${toString cfg.git.cacheTimeout}"
              (if cfg.mode == "bitwarden" then "${rbwCredentialHelper}" else "${sopsCredentialHelper}")
            ];
            "https://github.com" = {
              username = cfg.git.userName;
            };
          };
        };
      };

      # GitHub CLI configuration
      programs.gh = mkIf cfg.gh.enable {
        enable = true;
        gitProtocol = cfg.protocol;

        settings = {
          git_protocol = cfg.protocol;
          # Token fetched via git credential helper
        };

        # Additional useful aliases (merged with existing)
        aliases = mkIf cfg.gh.enableAliases {
          pv = "pr view";
          rv = "repo view";
          prs = "pr list";
          issues = "issue list";
        };
      };

      # Bitwarden mode: informational activation check
      home.activation.githubAuthBitwarden = mkIf (cfg.mode == "bitwarden")
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Non-blocking check if rbw is unlocked
          if ! ${pkgs.rbw}/bin/rbw unlocked >/dev/null 2>&1; then
            $DRY_RUN_CMD echo "ℹ️  Note: Bitwarden vault is locked. GitHub auth will fail until you run: rbw unlock"
          else
            $DRY_RUN_CMD echo "✅ Bitwarden unlocked - GitHub authentication ready"
          fi
        '');

      # Assertions
      assertions = [
        {
          assertion = cfg.mode == "bitwarden" -> (config.secretsManagement.enable or false);
          message = "githubAuth with bitwarden mode requires secretsManagement.enable = true";
        }
        {
          assertion = cfg.mode == "sops" -> ((config.sops.age.keyFile or null) != null);
          message = "githubAuth with sops mode requires SOPS age key configuration";
        }
      ];

      # Warnings
      warnings =
        optional (cfg.mode == "bitwarden" && (config.secretsManagement.rbw.email or null) == null)
          "githubAuth: bitwarden mode enabled but secretsManagement.rbw.email not set. Run 'rbw-init' to configure.";
    }

    # SOPS mode: configure secret (only if sops-nix module is loaded)
    # Check if sops options are available before trying to configure them
    (mkIf (cfg.mode == "sops" && (builtins.hasAttr "sops" options)) {
      sops.secrets."${cfg.sops.secretName}" = {
        sopsFile = cfg.sops.secretsFile;
        path = "${config.home.homeDirectory}/.config/github/token";
        mode = "0600";
      };
    })
  ]);
}
