# Bitwarden-based GitHub Authentication Module
# Secure GitHub authentication using Bitwarden/rbw following existing patterns
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.bitwardenGitHub;
in
{
  options.bitwardenGitHub = {
    enable = mkEnableOption "Bitwarden-based GitHub authentication";

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of users to configure GitHub authentication for.
        Each user must have rbw configured and unlocked.
      '';
      example = [ "tim" ];
    };

    bitwarden = {
      tokenName = mkOption {
        type = types.str;
        default = "github-token";
        description = ''
          Name of the GitHub token entry in Bitwarden.
          Can be a simple name or include folder path.
        '';
        example = "Infrastructure/github-token";
      };

      folder = mkOption {
        type = types.nullOr types.str;
        default = "Infrastructure/Tokens";
        description = ''
          Bitwarden folder containing GitHub tokens.
          Set to null if not using folders.
        '';
      };

      multiAccount = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to support multiple GitHub accounts.
          If true, expects entries named github-token-<username>.
        '';
      };
    };

    gitProtocol = mkOption {
      type = types.enum [ "https" "ssh" ];
      default = "https";
      description = "Protocol to use for git operations";
    };

    configureGit = mkOption {
      type = types.bool;
      default = true;
      description = "Configure git to use GitHub credentials from Bitwarden";
    };

    configureGh = mkOption {
      type = types.bool;
      default = true;
      description = "Configure GitHub CLI to use token from Bitwarden";
    };

    persistent = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to persist credentials to disk.
        If false, credentials are only available during the session.
        More secure but requires rbw unlock on each boot.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      rbw
      git
    ] ++ optional cfg.configureGh gh;

    # Create the GitHub authentication bootstrap script
    environment.etc."github-auth/bootstrap-github.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Colors for output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        NC='\033[0m' # No Color

        USER="''${1:-$(whoami)}"
        VERBOSE="''${VERBOSE:-false}"

        echo -e "''${GREEN}🔐 Bootstrapping GitHub authentication for $USER...''${NC}"

        # Check if rbw is available and unlocked
        if ! command -v rbw >/dev/null 2>&1; then
          echo -e "''${RED}❌ rbw not found. Please install rbw.''${NC}"
          exit 1
        fi

        if ! rbw unlocked 2>/dev/null; then
          echo -e "''${YELLOW}🔓 Bitwarden vault is locked. Unlocking...''${NC}"
          rbw unlock || exit 1
        fi

        # Determine token name based on configuration
        ${if cfg.bitwarden.multiAccount then ''
          TOKEN_NAME="${cfg.bitwarden.tokenName}-$USER"
        '' else ''
          TOKEN_NAME="${cfg.bitwarden.tokenName}"
        ''}

        # Fetch token from Bitwarden
        [[ "$VERBOSE" == "true" ]] && echo "Fetching token: $TOKEN_NAME"

        if TOKEN=$(rbw get "$TOKEN_NAME" 2>/dev/null); then
          echo -e "''${GREEN}✅ GitHub token retrieved from Bitwarden''${NC}"
        else
          echo -e "''${RED}❌ Failed to retrieve GitHub token from Bitwarden''${NC}"
          echo "   Ensure '$TOKEN_NAME' exists in your Bitwarden vault"
          exit 1
        fi

        ${optionalString cfg.configureGit ''
          # Configure git credential helper to use the token
          echo -e "''${GREEN}📝 Configuring git credentials...''${NC}"

          # Use git credential helper with a custom askpass script
          cat > ~/.git-askpass-bitwarden <<'EOF'
        #!/usr/bin/env bash
        # This script is called by git when it needs credentials
        # It fetches the GitHub token from Bitwarden on demand

        case "$1" in
          *"Username"*)
            # For GitHub, username doesn't matter with token auth
            echo "${if cfg.bitwarden.multiAccount then "$USER" else "git"}"
            ;;
          *"Password"*)
            # Fetch fresh token from Bitwarden
            rbw get "${if cfg.bitwarden.multiAccount then ''${cfg.bitwarden.tokenName}-$USER'' else cfg.bitwarden.tokenName}" 2>/dev/null || echo ""
            ;;
        esac
        EOF
          chmod 700 ~/.git-askpass-bitwarden

          # Configure git to use our askpass script
          git config --global core.askpass ~/.git-askpass-bitwarden
          git config --global credential.https://github.com.helper ""
          git config --global credential.https://github.com.username "${if cfg.bitwarden.multiAccount then "$USER" else "token"}"

          ${optionalString (cfg.gitProtocol == "https") ''
            # Force HTTPS instead of SSH
            git config --global url."https://github.com/".insteadOf "git@github.com:"
            git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
          ''}

          echo -e "''${GREEN}✅ Git configured for GitHub authentication''${NC}"
        ''}

        ${optionalString cfg.configureGh ''
          # Configure GitHub CLI
          echo -e "''${GREEN}🔧 Configuring GitHub CLI...''${NC}"

          # Use gh's built-in authentication with token from stdin
          echo "$TOKEN" | gh auth login --with-token --hostname github.com --git-protocol ${cfg.gitProtocol}

          if gh auth status >/dev/null 2>&1; then
            echo -e "''${GREEN}✅ GitHub CLI authenticated successfully''${NC}"
            gh auth status
          else
            echo -e "''${RED}❌ GitHub CLI authentication failed''${NC}"
            exit 1
          fi
        ''}

        ${optionalString (!cfg.persistent) ''
          # Clear token from memory
          unset TOKEN
          echo -e "''${YELLOW}📝 Note: Credentials are session-only. Run this script after each reboot.''${NC}"
        ''}

        echo -e "''${GREEN}✅ GitHub authentication setup complete!''${NC}"
        echo ""
        echo "You can now:"
        echo "  • Clone private repos: git clone https://github.com/owner/repo"
        echo "  • Use GitHub CLI: gh repo list"
        echo "  • Push to repos: git push"
      '';
    };

    # Create a systemd service for automatic authentication (optional)
    systemd.services."github-auth-bootstrap@" = mkIf cfg.persistent {
      description = "Bootstrap GitHub authentication for user %i";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "%i";
        ExecStart = "/etc/github-auth/bootstrap-github.sh %i";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Activation script for system-wide setup
    system.activationScripts.setupGitHubAuth = mkIf (cfg.users != [ ]) (
      stringAfter [ "users" "groups" ] ''
        echo "🔐 Setting up GitHub authentication for configured users..."

        ${concatMapStrings (user: ''
          if id "${user}" >/dev/null 2>&1; then
            echo "Setting up GitHub auth for ${user}..."

            # Create convenience script in user's home
            USER_HOME="/home/${user}"
            if [ -d "$USER_HOME" ]; then
              ln -sf /etc/github-auth/bootstrap-github.sh "$USER_HOME/.local/bin/github-auth-init" 2>/dev/null || true

              ${optionalString cfg.persistent ''
                # Enable the service for this user
                systemctl enable "github-auth-bootstrap@${user}.service" 2>/dev/null || true
              ''}
            fi
          fi
        '') cfg.users}
      ''
    );

    # Helper script for testing authentication
    environment.etc."github-auth/test-github.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "🧪 Testing GitHub authentication..."
        echo ""

        # Test git access
        echo "1️⃣ Testing git HTTPS access..."
        if git ls-remote https://github.com/octocat/Hello-World.git >/dev/null 2>&1; then
          echo "   ✅ Git can access public repos"

          # Try a private repo (will fail if not authenticated)
          if git ls-remote https://github.com/$USER/test-private.git >/dev/null 2>&1; then
            echo "   ✅ Git can access private repos"
          else
            echo "   ⚠️  Cannot confirm private repo access (repo may not exist)"
          fi
        else
          echo "   ❌ Git cannot access GitHub"
        fi

        ${optionalString cfg.configureGh ''
          # Test gh CLI
          echo ""
          echo "2️⃣ Testing GitHub CLI..."
          if gh auth status >/dev/null 2>&1; then
            echo "   ✅ GitHub CLI is authenticated"
            USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
            echo "   Authenticated as: $USER"
          else
            echo "   ❌ GitHub CLI is not authenticated"
            echo "   Run: github-auth-init"
          fi
        ''}

        echo ""
        echo "📊 To initialize authentication, run: github-auth-init"
      '';
    };

    # Warnings and assertions
    warnings = optional (cfg.users == [ ])
      "bitwardenGitHub is enabled but no users are specified. Add users to bitwardenGitHub.users.";

    assertions = [
      {
        assertion = cfg.configureGh -> elem pkgs.gh config.environment.systemPackages;
        message = "GitHub CLI (gh) must be installed when bitwardenGitHub.configureGh is true";
      }
    ];
  };
}
