# GitHub Authentication Module
# Provides seamless GitHub authentication using Bitwarden or SOPS
#
# This module is the GitHub counterpart to gitlab-auth.nix.
# Both modules share common infrastructure via lib/git-forge-auth.nix.
#
# Usage:
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
#
# Migration from old githubAuth namespace:
#   OLD: githubAuth.enable = true;
#   NEW: gitAuth.github.enable = true;
#
#   OLD: githubAuth.gitlab.enable = true;
#   NEW: gitAuth.gitlab.enable = true;  (separate module)
#
{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.gitAuth.github;

  # Import shared git forge authentication library
  gitForgeLib = import ./lib/git-forge-auth.nix { inherit pkgs lib config options; };
  inherit (gitForgeLib) rbwLib resolveBwConfig;

  # GitHub CLI wrapper with Bitwarden token injection and subcommand overrides
  gh-with-auth =
    let
      bwConfig = resolveBwConfig cfg.bitwarden;

      # Generate shell case branches for each override
      # Returns: string of case patterns like "pr) ... ;;"
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

    mode = gitForgeLib.mkModeOption;
    protocol = gitForgeLib.mkProtocolOption;
    rbwSyncInterval = gitForgeLib.mkRbwSyncIntervalOption;

    bitwarden = gitForgeLib.mkBitwardenOptions {
      defaultTokenName = "github-token";
      exampleItem = "github.com";
    };

    sops = gitForgeLib.mkSopsOptions {
      defaultSecretName = "github_token";
      defaultSecretsFile = ../../secrets/common/github.yaml;
    };

    git = gitForgeLib.mkGitCredentialOptions {
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
}
