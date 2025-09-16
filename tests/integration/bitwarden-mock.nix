# Bitwarden Mock Service for Testing
# Provides a mock rbw CLI that returns test data
{ pkgs, lib, ... }:

let
  # Test SSH keys for mock vault
  mockVaultData = {
    users = {
      alice = {
        privateKey = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACDQJZW5tL9Gp7K6kbEaA/uyHZWJqPmqzJgLMSx0YXJKmQAAAJCRjTwWkY08
          FgAAAAtzc2gtZWQyNTUxOQAAACDQJZW5tL9Gp7K6kbEaA/uyHZWJqPmqzJgLMSx0YXJKmQ
          AAAEA8p7XfAwNvofaydOLVZBxfPKAr9BTiKgctfcrsilcH+dAllbm0v0ansrqRsRoD+7Id
          lYmo+arMmAsxLHRhckqZAAAADWFsaWNlQGhvc3QxCg==
          -----END OPENSSH PRIVATE KEY-----
        '';
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAllbm0v0ansrqRsRoD+7IdlYmo+arMmAsxLHRhckqZ alice@host1";
      };
      bob = {
        privateKey = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACBWTQRLXN/fLxphbWThmUF7vRkDvBEAMCy8Y6WPH0d/3gAAAJCT2K1Yk9it
          WAAAAAt zc2gtZWQyNTUxOQAAACBWTQRLXN/fLxphbWThmUF7vRkDvBEAMCy8Y6WPH0d/3g
          AAAECGjJPz6Z3xV5IQV7K6l0xT9K6VUqPvS7X1+BvhbBXJLlZNBEtc398vGmFtZOGZQXu9
          GQO8EQAwLLxjpY8fR3/eAAAAC2JvYkBob3N0MQo=
          -----END OPENSSH PRIVATE KEY-----
        '';
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZNBEtc398vGmFtZOGZQXu9GQO8EQAwLLxjpY8fR3/e bob@host1";
      };
      deploy = {
        privateKey = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACCLFPDg4N3fkZ4HlZnS5W1SQ4F9P9HXsTpGF+J9YdZ6kgAAAJDhE9lT4RPZ
          UwAAAAtzc2gtZWQyNTUxOQAAACCLFPDg4N3fkZ4HlZnS5W1SQ4F9P9HXsTpGF+J9YdZ6kg
          AAAEA1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTU
          -----END OPENSSH PRIVATE KEY-----
        '';
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIsU8ODg3d+RngeVmdLlbVJDgX0/0dexOkYX4n1h1nqS deploy@ci";
      };
    };
    
    passwords = {
      "database-prod" = "prod_password_12345";
      "database-dev" = "dev_password_67890";
      "api-gateway" = "gateway_secret_xyz";
    };
    
    apiKeys = {
      "github-token" = "ghp_1234567890abcdefghijklmnopqrstuvwxyz";
      "gitlab-token" = "glpat-1234567890abcdefghij";
      "aws-access-key" = "AKIAIOSFODNN7EXAMPLE";
    };
  };

  # Mock rbw CLI implementation
  mockRbw = pkgs.writeShellScriptBin "rbw" ''
    #!/usr/bin/env bash
    set -e
    
    # Simple mock Bitwarden CLI for testing
    case "$1" in
      "unlock")
        echo "Vault unlocked" >&2
        exit 0
        ;;
        
      "lock")
        echo "Vault locked" >&2
        exit 0
        ;;
        
      "sync")
        echo "Syncing vault..." >&2
        echo "Sync complete" >&2
        exit 0
        ;;
        
      "list")
        case "''${2:-}" in
          "--fields")
            # List with specific fields
            echo "ssh-private-key-alice"
            echo "ssh-public-key-alice"
            echo "ssh-private-key-bob"
            echo "ssh-public-key-bob"
            echo "ssh-private-key-deploy"
            echo "ssh-public-key-deploy"
            echo "database-prod"
            echo "database-dev"
            echo "api-gateway"
            echo "github-token"
            echo "gitlab-token"
            echo "aws-access-key"
            ;;
          *)
            # Simple list
            echo "alice SSH keys"
            echo "bob SSH keys"
            echo "deploy SSH keys"
            echo "Production Database"
            echo "Development Database"
            echo "API Gateway"
            echo "GitHub Token"
            echo "GitLab Token"
            echo "AWS Access Key"
            ;;
        esac
        exit 0
        ;;
        
      "get")
        item="''${2:-}"
        field="''${3:-}"
        
        case "$item" in
          "ssh-private-key-alice")
            cat <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDQJZW5tL9Gp7K6kbEaA/uyHZWJqPmqzJgLMSx0YXJKmQAAAJCRjTwWkY08
FgAAAAtzc2gtZWQyNTUxOQAAACDQJZW5tL9Gp7K6kbEaA/uyHZWJqPmqzJgLMSx0YXJKmQ
AAAEA8p7XfAwNvofaydOLVZBxfPKAr9BTiKgctfcrsilcH+dAllbm0v0ansrqRsRoD+7Id
lYmo+arMmAsxLHRhckqZAAAADWFsaWNlQGhvc3QxCg==
-----END OPENSSH PRIVATE KEY-----
EOF
            ;;
            
          "ssh-public-key-alice")
            echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAllbm0v0ansrqRsRoD+7IdlYmo+arMmAsxLHRhckqZ alice@host1"
            ;;
            
          "ssh-private-key-bob")
            cat <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBWTQRLXN/fLxphbWThmUF7vRkDvBEAMCy8Y6WPH0d/3gAAAJCT2K1Yk9it
WAAAAAt zc2gtZWQyNTUxOQAAACBWTQRLXN/fLxphbWThmUF7vRkDvBEAMCy8Y6WPH0d/3g
AAAECGjJPz6Z3xV5IQV7K6l0xT9K6VUqPvS7X1+BvhbBXJLlZNBEtc398vGmFtZOGZQXu9
GQO8EQAwLLxjpY8fR3/eAAAAC2JvYkBob3N0MQo=
-----END OPENSSH PRIVATE KEY-----
EOF
            ;;
            
          "ssh-public-key-bob")
            echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZNBEtc398vGmFtZOGZQXu9GQO8EQAwLLxjpY8fR3/e bob@host1"
            ;;
            
          "ssh-private-key-deploy")
            cat <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCLFPDg4N3fkZ4HlZnS5W1SQ4F9P9HXsTpGF+J9YdZ6kgAAAJDhE9lT4RPZ
UwAAAAtzc2gtZWQyNTUxOQAAACCLFPDg4N3fkZ4HlZnS5W1SQ4F9P9HXsTpGF+J9YdZ6kg
AAAEA1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTU
-----END OPENSSH PRIVATE KEY-----
EOF
            ;;
            
          "ssh-public-key-deploy")
            echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIsU8ODg3d+RngeVmdLlbVJDgX0/0dexOkYX4n1h1nqS deploy@ci"
            ;;
            
          "database-prod")
            echo "prod_password_12345"
            ;;
            
          "database-dev")
            echo "dev_password_67890"
            ;;
            
          "api-gateway")
            echo "gateway_secret_xyz"
            ;;
            
          "github-token")
            echo "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
            ;;
            
          "gitlab-token")
            echo "glpat-1234567890abcdefghij"
            ;;
            
          "aws-access-key")
            echo "AKIAIOSFODNN7EXAMPLE"
            ;;
            
          *)
            echo "Error: Item '$item' not found in vault" >&2
            exit 1
            ;;
        esac
        exit 0
        ;;
        
      "add")
        name="''${2:-}"
        echo "Item '$name' added to vault" >&2
        exit 0
        ;;
        
      "edit")
        name="''${2:-}"
        echo "Item '$name' updated in vault" >&2
        exit 0
        ;;
        
      "remove")
        name="''${2:-}"
        echo "Item '$name' removed from vault" >&2
        exit 0
        ;;
        
      "generate")
        length="''${2:-16}"
        echo "$(head -c 100 /dev/urandom | base64 | tr -d '/+=' | head -c $length)"
        exit 0
        ;;
        
      *)
        echo "Usage: rbw [unlock|lock|sync|list|get|add|edit|remove|generate] [args...]" >&2
        exit 1
        ;;
    esac
  '';
in
{
  # Export the mock rbw package
  inherit mockRbw mockVaultData;
  
  # NixOS module for testing
  nixosModule = { config, pkgs, ... }: {
    environment.systemPackages = [ mockRbw ];
    
    # Mock Bitwarden environment
    environment.variables = {
      RBW_MOCK_MODE = "1";
      BITWARDEN_VAULT_UNLOCKED = "1";
    };
    
    # Create mock config directory
    system.activationScripts.mockBitwardenSetup = ''
      mkdir -p /root/.config/rbw
      cat > /root/.config/rbw/config.json <<EOF
      {
        "email": "test@example.com",
        "base_url": "https://vault.bitwarden.com",
        "identity_url": "https://identity.bitwarden.com",
        "lock_timeout": 3600,
        "pinentry": "tty"
      }
      EOF
    '';
  };
}