# Home-Manager GitHub Authentication Module
# This module handles user-level GitHub authentication using SOPS secrets
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.githubAuth;
in
{
  options.programs.githubAuth = {
    enable = mkEnableOption "GitHub authentication for user";

    username = mkOption {
      type = types.str;
      default = "timblaktu";
      description = "GitHub username";
    };

    email = mkOption {
      type = types.str;
      default = "timblaktu@gmail.com";
      description = "GitHub email for commits";
    };

    tokenCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cat /run/secrets.d/1/github_token";
      description = "Command to retrieve GitHub token (e.g., from SOPS)";
    };

    protocol = mkOption {
      type = types.enum [ "https" "ssh" ];
      default = "https";
      description = "Git protocol to use for GitHub";
    };

    configureGitCredentials = mkOption {
      type = types.bool;
      default = true;
      description = "Configure git credential helper";
    };

    configureGhCli = mkOption {
      type = types.bool;
      default = true;
      description = "Configure GitHub CLI";
    };

    enableKeychain = mkOption {
      type = types.bool;
      default = true;
      description = "Use system keychain/secret service for credential storage";
    };
  };

  config = mkIf cfg.enable {
    # Extend existing git configuration
    programs.git = {
      enable = true;
      userName = mkDefault cfg.username;
      userEmail = mkDefault cfg.email;

      extraConfig = mkMerge [
        (mkIf cfg.configureGitCredentials {
          credential = {
            helper =
              if cfg.enableKeychain
              then "libsecret"
              else "store";
            "https://github.com" = {
              username = cfg.username;
            };
          };
          url = mkIf (cfg.protocol == "https") {
            "https://github.com/" = {
              insteadOf = [
                "git@github.com:"
                "ssh://git@github.com/"
              ];
            };
          };
        })
      ];
    };

    # GitHub CLI configuration
    programs.gh = mkIf cfg.configureGhCli {
      enable = true;
      settings = {
        git_protocol = cfg.protocol;
        prompt = "enabled";
        aliases = {
          co = "pr checkout";
          pv = "pr view --web";
          rv = "repo view --web";
        };
      };
    };

    # Create shell aliases for GitHub operations
    home.shellAliases = {
      # GitHub shortcuts
      ghpr = "gh pr create";
      ghprs = "gh pr list";
      ghissue = "gh issue create";
      ghissues = "gh issue list";
      ghrepo = "gh repo view --web";

      # Git shortcuts that leverage GitHub auth
      gpush = "git push";
      gpull = "git pull";
      gfetch = "git fetch";
      gclone = "gh repo clone";
    };

    # Script to initialize GitHub authentication
    home.packages = with pkgs; [
      (writeShellApplication {
        name = "github-auth-init";
        runtimeInputs = [ git gh coreutils ];
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "🔐 Initializing GitHub authentication..."

          # Check if token command is configured
          TOKEN_CMD="${optionalString (cfg.tokenCommand != null) cfg.tokenCommand}"

          if [ -z "$TOKEN_CMD" ]; then
            echo "❌ No token command configured"
            echo "   Please configure programs.githubAuth.tokenCommand"
            exit 1
          fi

          # Retrieve token
          echo "📥 Retrieving GitHub token..."
          if ! GITHUB_TOKEN=$(eval "$TOKEN_CMD" 2>/dev/null); then
            echo "❌ Failed to retrieve GitHub token"
            echo "   Command: $TOKEN_CMD"
            exit 1
          fi

          if [ -z "$GITHUB_TOKEN" ]; then
            echo "❌ GitHub token is empty"
            exit 1
          fi

          # Configure gh CLI
          ${optionalString cfg.configureGhCli ''
            echo "🔧 Configuring GitHub CLI..."
            echo "$GITHUB_TOKEN" | gh auth login --with-token

            # Verify authentication
            if gh auth status >/dev/null 2>&1; then
              echo "✅ GitHub CLI authenticated successfully"
              gh auth status
            else
              echo "⚠️  GitHub CLI authentication may need verification"
            fi
          ''}

          # Configure git credentials
          ${optionalString cfg.configureGitCredentials ''
            echo "📝 Configuring git credentials..."

            # Store credentials
            echo "https://${cfg.username}:$GITHUB_TOKEN@github.com" | \
              git credential-store store

            echo "✅ Git credentials configured"
          ''}

          # Clear sensitive data
          unset GITHUB_TOKEN

          echo "✅ GitHub authentication initialization complete!"
          echo ""
          echo "You can now:"
          echo "  • Clone private repos: gh repo clone owner/repo"
          echo "  • Create PRs: gh pr create"
          echo "  • Manage issues: gh issue list"
          echo "  • Push to repos: git push"
        '';
      })

      # Helper script to test GitHub authentication
      (writeShellApplication {
        name = "github-auth-test";
        runtimeInputs = [ git gh curl jq ];
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "🧪 Testing GitHub authentication..."
          echo ""

          # Test gh CLI
          echo "1️⃣ Testing GitHub CLI (gh)..."
          if gh auth status >/dev/null 2>&1; then
            echo "   ✅ gh is authenticated"
            gh auth status 2>&1 | grep "Logged in" | sed 's/^/   /'
          else
            echo "   ❌ gh is not authenticated"
            echo "   Run: github-auth-init"
          fi
          echo ""

          # Test git credentials
          echo "2️⃣ Testing git credentials..."
          if git ls-remote https://github.com/${cfg.username}/nixcfg.git >/dev/null 2>&1; then
            echo "   ✅ Git can access private repos"
          else
            echo "   ⚠️  Git may not be properly authenticated"
            echo "   Note: This test assumes nixcfg repo exists and is private"
          fi
          echo ""

          # Test API access
          echo "3️⃣ Testing GitHub API access..."
          if gh api user --jq .login >/dev/null 2>&1; then
            USER=$(gh api user --jq .login)
            echo "   ✅ API access working (authenticated as: $USER)"
          else
            echo "   ❌ API access not working"
          fi
          echo ""

          # Summary
          echo "📊 Summary:"
          echo "   Use 'github-auth-init' to initialize authentication"
          echo "   Use 'gh auth status' to check current status"
          echo "   Use 'gh auth refresh' to refresh credentials"
        '';
      })
    ] ++ optionals cfg.enableKeychain [
      libsecret # For git credential-libsecret
    ];

    # Ensure gh config directory exists
    home.file.".config/gh/.keep".text = "";

    # Add activation script for user-level setup
    home.activation.setupGitHubAuth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Only run initialization if token command is configured
      ${optionalString (cfg.tokenCommand != null) ''
        if [ -n "${cfg.tokenCommand}" ]; then
          $DRY_RUN_CMD echo "Setting up GitHub authentication..."

          # Check if already authenticated
          if ! $DRY_RUN_CMD gh auth status >/dev/null 2>&1; then
            $DRY_RUN_CMD echo "GitHub CLI not authenticated, run: github-auth-init"
          fi
        fi
      ''}
    '';
  };
}
