# modules/programs/secrets-management [NDnd]/secrets-management.nix
# Secrets management configuration for NixOS, Darwin, and home-manager
#
# Provides:
#   flake.modules.nixos.secrets-management - sops-nix integration helpers
#   flake.modules.darwin.secrets-management - sops-nix integration for Darwin
#   flake.modules.homeManager.secrets-management - rbw and sops tools configuration
#
# Features:
#   - rbw (Rust Bitwarden CLI) configuration and helper scripts
#   - SOPS-nix integration boilerplate
#   - Age key management utilities
#   - Cross-platform secret tooling
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.secrets-management ];
#   secretsManagement = {
#     enable = true;
#     rbw.email = "user@example.com";
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === NixOS Secrets Management Module ===
    # Provides sops-nix integration and age key management for NixOS
    nixos.secrets-management = { config, lib, pkgs, ... }:
      let
        cfg = config.secretsManagement;
      in
      {
        options.secretsManagement = {
          enable = lib.mkEnableOption "secrets management for NixOS";

          sops = {
            defaultSopsFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Default SOPS secrets file for this host.
                If set, configures sops.defaultSopsFile.
              '';
              example = lib.literalExpression "./secrets/host-secrets.yaml";
            };

            ageKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/sops-nix/key.txt";
              description = ''
                Path to the age private key file used to decrypt secrets.
                This should be deployed securely before first boot.
              '';
            };

            generateHostKeys = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether to use system SSH host keys for SOPS.
                When enabled, derives age key from /etc/ssh/ssh_host_ed25519_key.
              '';
            };
          };
        };

        config = lib.mkIf cfg.enable {
          # Configure sops-nix (assumes inputs.sops-nix is imported at host level)
          # The host must import inputs.sops-nix.nixosModules.sops

          # Age key path
          sops.age.keyFile = lib.mkDefault cfg.sops.ageKeyFile;

          # Generate host key from SSH if enabled
          sops.age.sshKeyPaths = lib.mkIf cfg.sops.generateHostKeys [
            "/etc/ssh/ssh_host_ed25519_key"
          ];

          # Default secrets file if configured
          sops.defaultSopsFile = lib.mkIf (cfg.sops.defaultSopsFile != null)
            (lib.mkDefault cfg.sops.defaultSopsFile);

          # Ensure secrets directory has correct permissions
          systemd.tmpfiles.rules = [
            "d /var/lib/sops-nix 0700 root root -"
          ];
        };
      };

    # === Darwin Secrets Management Module ===
    # Provides sops-nix integration for Darwin
    darwin.secrets-management = { config, lib, pkgs, ... }:
      let
        cfg = config.secretsManagement;
      in
      {
        options.secretsManagement = {
          enable = lib.mkEnableOption "secrets management for Darwin";

          sops = {
            defaultSopsFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Default SOPS secrets file for this host.
                If set, configures sops.defaultSopsFile.
              '';
            };

            ageKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/sops-nix/key.txt";
              description = ''
                Path to the age private key file used to decrypt secrets.
              '';
            };
          };
        };

        config = lib.mkIf cfg.enable {
          # Configure sops-nix (assumes inputs.sops-nix is imported at host level)
          # The host must import inputs.sops-nix.darwinModules.sops

          sops.age.keyFile = lib.mkDefault cfg.sops.ageKeyFile;
          sops.defaultSopsFile = lib.mkIf (cfg.sops.defaultSopsFile != null)
            (lib.mkDefault cfg.sops.defaultSopsFile);
        };
      };

    # === Home Manager Secrets Management Module ===
    # Provides rbw (Rust Bitwarden CLI) and SOPS configuration for user environment
    homeManager.secrets-management = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.secretsManagement;
      in
      {
        options.secretsManagement = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable secrets management configuration";
          };

          rbw = {
            email = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "user@example.com";
              description = "Email address for Bitwarden account";
            };

            baseUrl = mkOption {
              type = types.str;
              default = "https://vault.bitwarden.com";
              description = "Base URL for Bitwarden server";
            };

            identityUrl = mkOption {
              type = types.str;
              default = "https://identity.bitwarden.com";
              description = "Identity/authentication server URL";
            };

            uiUrl = mkOption {
              type = types.str;
              default = "https://vault.bitwarden.com";
              description = "Web vault URL";
            };

            notificationsUrl = mkOption {
              type = types.str;
              default = "https://notifications.bitwarden.com";
              description = "Notifications server URL";
            };

            pinentry = mkOption {
              type = types.str;
              default = "pinentry";
              example = "pinentry-gtk2";
              description = "Pinentry program to use for password prompts";
            };

            lockTimeout = mkOption {
              type = types.int;
              default = 3600; # 1 hour
              description = "Time in seconds before the vault is automatically locked";
            };

            syncInterval = mkOption {
              type = types.int;
              default = 3600; # 1 hour
              description = "Time in seconds between automatic syncs";
            };
          };

          # SOPS helper scripts configuration
          sops = {
            ageKeysDir = mkOption {
              type = types.str;
              default = "$HOME/.config/sops/age";
              description = "Directory to store age keys";
            };

            enableHelperScripts = mkOption {
              type = types.bool;
              default = true;
              description = "Install sops-keygen and sops-backup-to-bitwarden helper scripts";
            };
          };

          # Shell integration
          shell = {
            enableHints = mkOption {
              type = types.bool;
              default = true;
              description = "Show rbw initialization hints in shell startup";
            };
          };
        };

        config = mkIf cfg.enable {
          # RBW configuration file
          home.file.".config/rbw/config.json" = mkIf (cfg.rbw.email != null) {
            text = builtins.toJSON {
              inherit (cfg.rbw) email;
              base_url = cfg.rbw.baseUrl;
              identity_url = cfg.rbw.identityUrl;
              ui_url = cfg.rbw.uiUrl;
              notifications_url = cfg.rbw.notificationsUrl;
              inherit (cfg.rbw) pinentry;
              lock_timeout = cfg.rbw.lockTimeout;
              sync_interval = cfg.rbw.syncInterval;
              sso_id = null;
              client_cert_path = null;
            };
          };

          # Helper script for rbw initialization
          home.file.".local/bin/rbw-init" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              # Initialize rbw configuration
              if [ ! -f "$HOME/.config/rbw/config.json" ]; then
                echo "Initializing rbw configuration..."

                # Get email if not configured
                if [ -z "''${RBW_EMAIL:-}" ]; then
                  read -p "Enter your Bitwarden email: " RBW_EMAIL
                fi

                # Configure rbw
                rbw config set email "$RBW_EMAIL"
                rbw config set base_url "''${RBW_BASE_URL:-${cfg.rbw.baseUrl}}"
                rbw config set identity_url "''${RBW_IDENTITY_URL:-${cfg.rbw.identityUrl}}"
                rbw config set ui_url "''${RBW_UI_URL:-${cfg.rbw.uiUrl}}"
                rbw config set notifications_url "''${RBW_NOTIFICATIONS_URL:-${cfg.rbw.notificationsUrl}}"
                rbw config set pinentry "''${RBW_PINENTRY:-${cfg.rbw.pinentry}}"
                rbw config set lock_timeout ${toString cfg.rbw.lockTimeout}
                rbw config set sync_interval ${toString cfg.rbw.syncInterval}
              fi

              # Check if logged in
              if ! rbw unlocked >/dev/null 2>&1; then
                echo "Logging into Bitwarden..."
                rbw login || rbw unlock
              fi

              # Sync vault
              echo "Syncing Bitwarden vault..."
              rbw sync

              echo "RBW initialization complete!"
            '';
          };

          # Helper script for SOPS key generation
          home.file.".local/bin/sops-keygen" = mkIf cfg.sops.enableHelperScripts {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              KEYS_DIR="''${KEYS_DIR:-${cfg.sops.ageKeysDir}}"
              # Expand $HOME if present
              KEYS_DIR="''${KEYS_DIR/#\$HOME/$HOME}"

              if [ -f "$KEYS_DIR/keys.txt" ]; then
                echo "Age key already exists at $KEYS_DIR/keys.txt"
                echo "Public key:"
                age-keygen -y "$KEYS_DIR/keys.txt"
                exit 0
              fi

              echo "Generating new age key..."
              mkdir -p "$KEYS_DIR"
              chmod 700 "$KEYS_DIR"

              age-keygen -o "$KEYS_DIR/keys.txt"
              chmod 600 "$KEYS_DIR/keys.txt"

              echo ""
              echo "Age key generated successfully!"
              echo "Private key stored at: $KEYS_DIR/keys.txt"
              echo ""
              echo "Public key for .sops.yaml:"
              age-keygen -y "$KEYS_DIR/keys.txt"
              echo ""
              echo "Add this public key to your .sops.yaml file"
            '';
          };

          # Helper script to backup age key to Bitwarden
          home.file.".local/bin/sops-backup-to-bitwarden" = mkIf cfg.sops.enableHelperScripts {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              KEYS_DIR="''${KEYS_DIR:-${cfg.sops.ageKeysDir}}"
              KEYS_DIR="''${KEYS_DIR/#\$HOME/$HOME}"
              KEY_FILE="$KEYS_DIR/keys.txt"
              BW_ENTRY_NAME="''${BW_ENTRY_NAME:-NixOS Age Key - $(hostname)}"

              if [ ! -f "$KEY_FILE" ]; then
                echo "Error: No age key found at $KEY_FILE"
                echo "Run 'sops-keygen' first to generate a key"
                exit 1
              fi

              # Ensure rbw is unlocked
              if ! rbw unlocked >/dev/null 2>&1; then
                echo "Unlocking Bitwarden vault..."
                rbw unlock || rbw login
              fi

              # Check if entry already exists
              if rbw get "$BW_ENTRY_NAME" >/dev/null 2>&1; then
                echo "Warning: Entry '$BW_ENTRY_NAME' already exists in Bitwarden"
                read -p "Overwrite? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                  echo "Cancelled"
                  exit 0
                fi
                rbw remove "$BW_ENTRY_NAME"
              fi

              # Read the key content
              KEY_CONTENT=$(cat "$KEY_FILE")

              # Create the entry in Bitwarden
              echo "Creating Bitwarden entry: $BW_ENTRY_NAME"
              echo "$KEY_CONTENT" | rbw add --notes "$BW_ENTRY_NAME" --folder "NixOS Keys"

              echo "Age key successfully backed up to Bitwarden!"
              echo "Entry name: $BW_ENTRY_NAME"
            '';
          };

          # Add to shell initialization - bash
          programs.bash.initExtra = mkIf cfg.shell.enableHints (mkAfter ''
            # Add local bin to PATH if not already there
            [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

            # RBW initialization hint
            if ! command -v rbw >/dev/null 2>&1; then
              echo "Note: rbw is not available. Run 'home-manager switch' to install it."
            elif [ ! -f "$HOME/.config/rbw/config.json" ]; then
              echo "Tip: Run 'rbw-init' to set up your Bitwarden CLI"
            fi
          '');

          # Add to shell initialization - zsh
          programs.zsh.initContent = mkIf cfg.shell.enableHints (mkAfter ''
            # Add local bin to PATH if not already there
            [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

            # RBW initialization hint
            if ! command -v rbw >/dev/null 2>&1; then
              echo "Note: rbw is not available. Run 'home-manager switch' to install it."
            elif [ ! -f "$HOME/.config/rbw/config.json" ]; then
              echo "Tip: Run 'rbw-init' to set up your Bitwarden CLI"
            fi
          '');
        };
      };
  };
}
