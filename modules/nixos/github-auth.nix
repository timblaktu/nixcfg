# GitHub Authentication Module with SOPS Integration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.githubAuth;
in
{
  options.githubAuth = {
    enable = mkEnableOption "GitHub authentication with SOPS secrets";

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

    secretsFile = mkOption {
      type = types.path;
      default = ../../secrets/common/github.yaml;
      description = "Path to SOPS-encrypted GitHub secrets file";
    };

    tokenSecretName = mkOption {
      type = types.str;
      default = "github_token";
      description = "Name of the GitHub token secret in the SOPS file";
    };

    configureGitCredentials = mkOption {
      type = types.bool;
      default = true;
      description = "Configure git credential helper to use GitHub token";
    };

    configureGhCli = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically authenticate gh CLI with token";
    };

    enableSshSigning = mkOption {
      type = types.bool;
      default = false;
      description = "Enable SSH commit signing";
    };

    sshSigningKeySecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of SSH signing key secret in SOPS file";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Users to configure GitHub auth for (empty = all users with home dirs)";
    };

    protocol = mkOption {
      type = types.enum [ "https" "ssh" ];
      default = "https";
      description = "Git protocol to use for GitHub operations";
    };
  };

  config = mkIf cfg.enable {
    # Define SOPS secrets for GitHub authentication
    sops.secrets = {
      "${cfg.tokenSecretName}" = {
        sopsFile = cfg.secretsFile;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    } // optionalAttrs (cfg.enableSshSigning && cfg.sshSigningKeySecret != null) {
      "${cfg.sshSigningKeySecret}" = {
        sopsFile = cfg.secretsFile;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };

    # Activation script to configure GitHub authentication for users
    system.activationScripts.configureGitHubAuth =
      let
        targetUsers =
          if cfg.users == [ ]
          then "tim"  # Default to tim user if no users specified
          else lib.concatStringsSep " " cfg.users;

        tokenPath = config.sops.secrets."${cfg.tokenSecretName}".path;

        sshKeyPath =
          if cfg.enableSshSigning && cfg.sshSigningKeySecret != null
          then config.sops.secrets."${cfg.sshSigningKeySecret}".path
          else null;
      in
      lib.stringAfter [ "users" "sops-install-secrets" ] ''
        echo "🔐 Configuring GitHub authentication..."

        # Wait for SOPS secrets to be available
        max_attempts=30
        attempt=0
        while [ ! -f "${tokenPath}" ] && [ $attempt -lt $max_attempts ]; do
          echo "⏳ Waiting for SOPS secrets to decrypt (attempt $((attempt + 1))/$max_attempts)..."
          sleep 1
          attempt=$((attempt + 1))
        done

        if [ ! -f "${tokenPath}" ]; then
          echo "❌ GitHub token not available from SOPS after $max_attempts attempts"
          echo "   Please ensure SOPS is properly configured and the secrets file exists"
          exit 1
        fi

        # Read the token once (minimize exposure time)
        GITHUB_TOKEN=$(cat "${tokenPath}")

        # Configure for each specified user
        for user in ${targetUsers}; do
          USER_HOME="/home/$user"

          # Skip if user doesn't exist or home directory doesn't exist
          if ! id "$user" >/dev/null 2>&1 || [ ! -d "$USER_HOME" ]; then
            echo "⚠️  Skipping user $user (user or home directory doesn't exist)"
            continue
          fi

          echo "👤 Configuring GitHub auth for user: $user"

          ${optionalString cfg.configureGitCredentials ''
            # Configure git credential helper with GitHub token
            echo "   📝 Setting up git credential helper..."

            # Create git credentials file
            CRED_FILE="$USER_HOME/.git-credentials"
            echo "https://${cfg.username}:$GITHUB_TOKEN@github.com" > "$CRED_FILE.tmp"
            chmod 600 "$CRED_FILE.tmp"
            chown "$user:users" "$CRED_FILE.tmp"
            mv "$CRED_FILE.tmp" "$CRED_FILE"

            # Configure git to use the credential store
            sudo -u "$user" git config --global credential.helper store
            sudo -u "$user" git config --global credential.https://github.com.username "${cfg.username}"

            # Set git protocol preference
            sudo -u "$user" git config --global url."${cfg.protocol}://github.com/".insteadOf "git@github.com:"
            sudo -u "$user" git config --global url."${cfg.protocol}://github.com/".insteadOf "ssh://git@github.com/"
          ''}

          ${optionalString cfg.configureGhCli ''
            # Configure GitHub CLI authentication
            echo "   🔧 Setting up GitHub CLI (gh)..."

            # Create gh config directory
            GH_CONFIG_DIR="$USER_HOME/.config/gh"
            mkdir -p "$GH_CONFIG_DIR"

            # Write hosts.yml with authentication
            cat > "$GH_CONFIG_DIR/hosts.yml.tmp" <<EOF
        github.com:
            user: ${cfg.username}
            oauth_token: $GITHUB_TOKEN
            git_protocol: ${cfg.protocol}
        EOF
            chmod 600 "$GH_CONFIG_DIR/hosts.yml.tmp"
            chown -R "$user:users" "$GH_CONFIG_DIR"
            mv "$GH_CONFIG_DIR/hosts.yml.tmp" "$GH_CONFIG_DIR/hosts.yml"

            # Validate gh auth status (non-blocking)
            if command -v gh >/dev/null 2>&1; then
              if sudo -u "$user" gh auth status >/dev/null 2>&1; then
                echo "   ✅ GitHub CLI authenticated successfully for $user"
              else
                echo "   ⚠️  GitHub CLI authentication may need manual verification"
              fi
            fi
          ''}

          ${optionalString (cfg.enableSshSigning && sshKeyPath != null) ''
            # Configure SSH commit signing
            echo "   🔏 Setting up SSH commit signing..."

            SSH_DIR="$USER_HOME/.ssh"
            mkdir -p "$SSH_DIR"

            # Deploy SSH signing key
            SIGNING_KEY="$SSH_DIR/github_signing"
            cp "${sshKeyPath}" "$SIGNING_KEY"
            chmod 600 "$SIGNING_KEY"
            chown "$user:users" "$SIGNING_KEY"

            # Configure git for SSH signing
            sudo -u "$user" git config --global gpg.format ssh
            sudo -u "$user" git config --global user.signingkey "$SIGNING_KEY"
            sudo -u "$user" git config --global commit.gpgsign true

            # Generate public key for allowed signers
            ssh-keygen -y -f "$SIGNING_KEY" > "$SIGNING_KEY.pub"
            chown "$user:users" "$SIGNING_KEY.pub"

            # Create allowed signers file
            echo "${cfg.email} $(cat $SIGNING_KEY.pub)" > "$SSH_DIR/allowed_signers"
            chown "$user:users" "$SSH_DIR/allowed_signers"
            sudo -u "$user" git config --global gpg.ssh.allowedSignersFile "$SSH_DIR/allowed_signers"
          ''}
        done

        # Clear sensitive data from memory
        unset GITHUB_TOKEN

        echo "✅ GitHub authentication configuration complete"
      '';

    # Install GitHub CLI if gh authentication is enabled
    environment.systemPackages = mkIf cfg.configureGhCli [ pkgs.gh ];

    # Optional: Create systemd service for token rotation reminder
    systemd.timers.github-token-rotation-reminder = mkIf cfg.configureGhCli {
      description = "Reminder to rotate GitHub token";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Remind every 6 months
        OnCalendar = "*-*/6-01 00:00:00";
        Persistent = true;
      };
    };

    systemd.services.github-token-rotation-reminder = mkIf cfg.configureGhCli {
      description = "GitHub token rotation reminder";
      serviceConfig.Type = "oneshot";
      script = ''
        echo "⚠️  GitHub token rotation reminder: Consider rotating your GitHub Personal Access Token"
        echo "   Visit: https://github.com/settings/tokens"
        echo "   Update the token in: sops ${toString cfg.secretsFile}"
      '';
    };
  };
}
