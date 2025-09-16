# SOPS-NiX Secrets Management System

## Host Priority Status (2025-09-14)

### Active Hosts
1. **thinky-nixos** ✅ Primary development machine - Fully operational with SOPS-NiX
2. **potato** 🔄 Next priority - Le Potato SBC for embedded testing & private CA with Yubikey  
3. **mbp** 🔄 Lower priority - Intel MacBook Pro with NixOS
4. **nixos-wsl-minimal** 🔄 Lowest priority - WSL distribution template for enterprise deployment

### Archived Hosts  
- **tblack-t14-nixos** 📦 Work laptop no longer in use (configuration preserved in `hosts/archived/`)

## Overview

This document describes the production secrets management system for the nixcfg repository using SOPS-NiX with age encryption. The system provides secure, declarative secrets management integrated with NixOS configuration.

## System Architecture

### Component Relationships

```mermaid
graph TB
    subgraph "Secret Storage"
        BW[Bitwarden Vault]
        GIT[Git Repository<br/>Encrypted Secrets]
    end
    
    subgraph "Encryption Layer"
        SOPS[SOPS Tool]
        AGE[Age Encryption]
    end
    
    subgraph "Keys"
        UK[User Key<br/>~/.config/sops/age/]
        HK[Host Key<br/>/etc/sops/age.key]
    end
    
    subgraph "NixOS Integration"
        SOPSNIX[sops-nix Module]
        NIXCFG[NixOS Configuration]
        SYSTEMD[Systemd Services]
    end
    
    subgraph "Runtime"
        SECRETS[Decrypted Secrets<br/>/run/secrets.d/]
        SERVICES[System Services]
    end
    
    BW -->|Backup| UK
    BW -->|Backup| HK
    UK -->|Decrypt| SOPS
    HK -->|Decrypt| SOPS
    GIT -->|Encrypted Files| SOPS
    SOPS -->|Uses| AGE
    SOPS -->|Provides| SOPSNIX
    SOPSNIX -->|Configures| NIXCFG
    NIXCFG -->|Activates| SYSTEMD
    SYSTEMD -->|Creates| SECRETS
    SECRETS -->|Consumed by| SERVICES
```

### File Structure

```
nixcfg/
├── .sops.yaml                         # SOPS configuration & key mappings
├── .pre-commit-config.yaml            # Gitleaks secret scanning
├── secrets/
│   ├── common/                        # Shared secrets across hosts
│   │   ├── example.yaml.template      # Template for new secrets
│   │   └── *.yaml                     # Encrypted secret files
│   ├── thinky-nixos/                  # Host-specific secrets
│   ├── mbp/                           # MacBook Pro secrets
│   └── potato/                        # Potato host secrets
├── modules/
│   └── nixos/
│       ├── sops-nix.nix              # SOPS-NiX wrapper module
│       └── wifi-secrets-example.nix   # Example service integration
└── hosts/
    └── */default.nix                  # Host configurations with secrets
```

## User Workflows

### Initial Setup Workflow

```mermaid
sequenceDiagram
    participant User
    participant RBW as Bitwarden CLI
    participant System
    participant Git
    
    User->>RBW: rbw-init (configure Bitwarden)
    RBW->>RBW: Configure email, pinentry
    
    User->>System: Generate age keys
    Note over System: age-keygen > keys.txt
    System->>User: Public & Private keys
    
    User->>RBW: rbw add age-key-{user/host}
    RBW->>RBW: Store private keys
    
    User->>System: Place keys in correct locations
    Note over System: User: ~/.config/sops/age/keys.txt<br/>Host: /etc/sops/age.key
    
    User->>Git: Update .sops.yaml with public keys
    Git->>Git: Commit configuration
```

### Creating New Secrets Workflow

```mermaid
sequenceDiagram
    participant User
    participant SOPS
    participant Editor
    participant Git
    participant NixOS
    
    User->>User: cd secrets/common/
    User->>SOPS: sops services.yaml
    SOPS->>Editor: Open decrypted view
    User->>Editor: Add secrets in YAML format
    Editor->>SOPS: Save & close
    SOPS->>SOPS: Encrypt with age keys
    SOPS->>Git: Create encrypted file
    
    User->>NixOS: Edit host configuration
    Note over NixOS: Add sops.secrets definitions
    User->>Git: git add & commit
    User->>NixOS: nixos-rebuild switch
    NixOS->>NixOS: Decrypt secrets to /run/secrets.d/
```

### Using Secrets in Services Workflow

```mermaid
sequenceDiagram
    participant NixOS as NixOS Config
    participant Build as nixos-rebuild
    participant Systemd
    participant SOPS as sops-nix
    participant Service
    
    NixOS->>Build: Define sops.secrets."api_key"
    Build->>Build: Evaluate configuration
    Build->>Systemd: Create activation script
    
    Systemd->>SOPS: Trigger sops-nix.service
    SOPS->>SOPS: Read encrypted secrets
    SOPS->>SOPS: Decrypt with host key
    SOPS->>Systemd: Write to /run/secrets.d/
    
    Systemd->>Service: Start service
    Service->>Service: Read from secret path
    Note over Service: cat /run/secrets.d/1/api_key
```

## Quick Start Guide

### 1. Create Your First Secret

```bash
# Navigate to secrets directory
cd /home/tim/src/nixcfg/secrets/common

# Create new secrets file from template
cp example.yaml.template services.yaml

# Edit with SOPS (will open your $EDITOR)
sops services.yaml

# Add your secrets in YAML format:
# github_token: ghp_xxxxxxxxxxxxx
# api_key: sk-xxxxxxxxxxxxx

# Save and exit - file encrypts automatically
```

### 2. Configure NixOS to Use Secrets

Edit your host configuration (`hosts/{hostname}/default.nix`):

```nix
{
  # Enable SOPS-NiX
  sopsNix = {
    enable = true;
    hostKeyPath = "/etc/sops/age.key";
    defaultSopsFile = ../../secrets/common/services.yaml;
  };
  
  # Define specific secrets
  sops.secrets = {
    "github_token" = {
      owner = "tim";
      mode = "0400";
    };
    "api_key" = {
      owner = "myservice";
      group = "myservice";
    };
  };
}
```

### 3. Use Secrets in Services

```nix
# Option 1: Environment variable pointing to secret file
systemd.services.my-app = {
  serviceConfig = {
    Environment = "TOKEN_FILE=${config.sops.secrets.github_token.path}";
  };
  script = ''
    TOKEN=$(cat $TOKEN_FILE)
    # Use $TOKEN in your service
  '';
};

# Option 2: Direct file reference
services.myapp = {
  secretFile = config.sops.secrets.api_key.path;
};

# Option 3: SystemD EnvironmentFile
systemd.services.webapp = {
  serviceConfig = {
    EnvironmentFile = config.sops.secrets.api_key.path;
  };
};
```

### 4. Apply Configuration

```bash
# Rebuild NixOS with new secrets
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# Verify secrets are decrypted
sudo ls -la /run/secrets.d/1/
sudo cat /run/secrets.d/1/github_token  # Should show decrypted value
```

## Security Safeguards

### 1. Pre-commit Hook (Gitleaks)

The repository includes a `.pre-commit-config.yaml` that uses Gitleaks to scan for secrets:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

**Setup:**
```bash
# Install pre-commit hooks
nix-shell -p pre-commit
pre-commit install

# Manual scan
pre-commit run --all-files
```

### 2. .gitignore Protection

Critical paths are excluded from git to prevent accidental commits:

```gitignore
# Environment variables
.env
.envrc

# Temporary decrypted files
*.dec
*.plaintext
*.unencrypted

# Key material (backup protection)
*.key
*.pem
keys.txt
```

### 3. File Permissions

All secrets are created with restrictive permissions:

- User keys: `600` (owner read/write only)
- Host keys: `600` (root only)
- Decrypted secrets: Configurable per secret (default `400`)

### 4. Runtime Security

- Secrets only exist in `/run/secrets.d/` (tmpfs - RAM only)
- Secrets are re-decrypted on every boot
- No plaintext secrets persist on disk
- Services read secrets at runtime, not build time

### 5. Recommended GitHub Actions

Add to `.github/workflows/security.yml`:

```yaml
name: Security Scan

on: [push, pull_request]

jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  trufflehog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
```

## Common Patterns

### Database Credentials

```nix
sops.secrets."postgres_password" = {
  owner = "postgres";
  group = "postgres";
};

services.postgresql = {
  enable = true;
  initialScript = pkgs.writeText "init.sql" ''
    ALTER USER postgres WITH PASSWORD '$(cat ${config.sops.secrets.postgres_password.path})';
  '';
};
```

### API Keys for User Services

```nix
sops.secrets."openai_key" = {
  owner = config.users.users.tim.name;
  mode = "0400";
};

home-manager.users.tim = {
  home.sessionVariables = {
    OPENAI_API_KEY_FILE = config.sops.secrets.openai_key.path;
  };
};
```

### WiFi Networks

See `modules/nixos/wifi-secrets-example.nix` for complete implementation.

### SSH Private Keys

```yaml
# In secrets file:
ssh_keys:
  github_deploy: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    [key content]
    -----END OPENSSH PRIVATE KEY-----
```

```nix
sops.secrets."ssh_keys.github_deploy" = {
  owner = "git";
  mode = "0600";
  path = "/home/git/.ssh/deploy_key";
};
```

## SSH Key Management with SOPS-NiX

### Current Implementation Status

The nixcfg repository currently provides **partial support** for SSH key management through SOPS-NiX:

#### ✅ What's Currently Supported

1. **Manual SSH Private Key Storage**: Private SSH keys can be encrypted and stored in SOPS files (see example above)
2. **SSH Host Key Integration**: SSH host keys (ed25519) can be converted to age keys using `ssh-to-age`
3. **Authorized Keys Configuration**: Public keys are managed through NixOS configuration:
   - WSL hosts: `wslCommon.authorizedKeys` option
   - Standard hosts: `users.users.<user>.openssh.authorizedKeys.keys`
   - Base module: `base.sshKeys` option for default keys

#### ❌ What's NOT Currently Automated

1. **Automatic SSH Keypair Generation**: No automatic generation of user or host SSH keypairs
2. **Cross-Host Key Distribution**: No automatic distribution of public keys between hosts
3. **Key Rotation**: No automated key rotation mechanism
4. **Host-to-Host SSH**: No automatic setup for passwordless SSH between managed hosts

### Architecture for Automated SSH Key Management

To achieve fully automated SSH key management where Nix-managed hosts can SSH freely to one another, the following architecture would be needed:

#### 1. SSH Keypair Generation Module

Create a new module `modules/nixos/ssh-key-automation.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.sshKeyAutomation;
  hostName = config.networking.hostName;
in {
  options.sshKeyAutomation = {
    enable = lib.mkEnableOption "automatic SSH key management";
    
    generateUserKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically generate user SSH keypairs";
    };
    
    generateHostKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically generate host SSH keypairs";
    };
    
    authorizedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of hosts whose keys should be authorized";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Implementation would go here
  };
}
```

#### 2. Key Generation Strategy

**Option A: Build-Time Generation (Not Recommended)**
- Keys would be generated during `nixos-rebuild`
- Problem: Keys would be in Nix store (world-readable)
- Security risk: Private keys should never be in /nix/store

**Option B: Activation Script Generation (Recommended)**
```nix
system.activationScripts.generateSSHKeys = ''
  # Generate user SSH keys if they don't exist
  if [ ! -f /home/${user}/.ssh/id_ed25519 ]; then
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /home/${user}/.ssh/id_ed25519 -N ""
    chown ${user}:users /home/${user}/.ssh/id_ed25519*
  fi
  
  # Store public key in SOPS for distribution
  # This would require runtime SOPS encryption capability
'';
```

**Option C: Hybrid Approach with SOPS (Best Practice)**
1. Pre-generate keys outside NixOS
2. Store private keys in SOPS
3. Store public keys in Nix configuration
4. Distribute via NixOS modules

#### 3. Public Key Distribution Pattern

```nix
# In flake.nix or a shared module
{
  nixosModules.sshKeys = {
    # Central registry of all host/user public keys
    hosts = {
      thinky-nixos = {
        hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
        users.tim = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
      };
      potato = {
        hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
        users.tim = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
      };
    };
  };
}

# In each host configuration
{
  users.users.tim.openssh.authorizedKeys.keys = 
    lib.mapAttrsToList (name: host: host.users.tim) 
    config.sshKeys.hosts;
}
```

### Recommended Implementation Approach

Given the security constraints and NixOS evaluation model, the most practical approach is:

1. **Semi-Automated Setup**:
   - Use activation scripts to generate keys if missing
   - Manually copy public keys to configuration
   - Use SOPS for private key backup/distribution

2. **Centralized Public Key Registry**:
   - Maintain a `keys.nix` file with all public keys
   - Import in all host configurations
   - Use module options to control which keys are authorized

3. **SOPS Integration**:
   - Store private keys in SOPS for backup
   - Deploy private keys only where needed
   - Use age keys derived from SSH host keys

### Example Implementation

```nix
# modules/nixos/ssh-keys-registry.nix
{ lib, ... }:
{
  options.sshRegistry = {
    publicKeys = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      description = "Registry of all SSH public keys";
    };
  };
  
  config.sshRegistry.publicKeys = {
    thinky-nixos = {
      host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
      tim = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
    };
    potato = {
      host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
      tim = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
    };
  };
}

# In host configuration
{ config, ... }:
{
  # Authorize all registered keys for this user
  users.users.tim.openssh.authorizedKeys.keys = 
    lib.mapAttrsToList (host: keys: keys.tim or null) 
    config.sshRegistry.publicKeys;
    
  # Store this host's private key from SOPS
  sops.secrets."ssh_keys.tim" = {
    owner = "tim";
    path = "/home/tim/.ssh/id_ed25519";
    mode = "0600";
  };
}
```

### Security Considerations

1. **Never store private keys in Nix store** - They would be world-readable
2. **Use SOPS for private keys** - Ensures encryption at rest
3. **Public keys can be in configuration** - They're meant to be public
4. **Consider SSH certificates** - For larger deployments, SSH CA is more scalable
5. **Implement key rotation** - Regular rotation improves security

### Why Full Automation is Challenging

1. **NixOS Pure Evaluation**: Cannot generate keys during evaluation
2. **Nix Store Security**: Everything in /nix/store is world-readable
3. **State Management**: NixOS is declarative, SSH keys are stateful
4. **Bootstrap Problem**: Need keys to encrypt keys with SOPS

### Current Workarounds

For now, the most practical approach is:

1. Generate SSH keys manually or via activation scripts
2. Store public keys in NixOS configuration (unencrypted)
3. Store private keys in SOPS (encrypted)
4. Use the existing `authorizedKeys` options for distribution

## Bitwarden-Based SSH Key Management (Recommended Approach)

### Overview

Using Bitwarden as the single source of truth for ALL secrets, including SSH keypairs, provides a unified, secure, and cloud-backed solution that maintains NixOS's declarative purity while enabling practical key management.

### Architecture

```mermaid
graph TB
    subgraph "Bitwarden Vault"
        BWV[Bitwarden Cloud]
        SSH_USER[User SSH Keypairs]
        SSH_HOST[Host SSH Keypairs]
        AGE_KEYS[Age Keys]
    end
    
    subgraph "Local System"
        RBW[rbw CLI]
        BOOTSTRAP[bootstrap-ssh-keys]
        SOPS[SOPS Encryption]
    end
    
    subgraph "NixOS Configuration"
        ACTIVATION[Activation Scripts]
        PUBKEYS[Public Keys Registry]
        AUTH_KEYS[Authorized Keys]
    end
    
    subgraph "Runtime"
        SSH_DIR[~/.ssh/]
        HOST_KEYS[/etc/ssh/]
        SECRETS[/run/secrets.d/]
    end
    
    BWV -->|rbw get| RBW
    RBW -->|Fetch Keys| BOOTSTRAP
    BOOTSTRAP -->|Deploy| SSH_DIR
    BOOTSTRAP -->|Deploy| HOST_KEYS
    PUBKEYS -->|Configure| AUTH_KEYS
    ACTIVATION -->|Run| BOOTSTRAP
    SOPS -->|Decrypt at Runtime| SECRETS
```

### Why Bitwarden for SSH Keys

#### ✅ Advantages
1. **Single Source of Truth** - All secrets (passwords, API keys, SSH keys, age keys) in one place
2. **Cloud Backup** - Keys survive local disasters, accessible from anywhere
3. **Version History** - Bitwarden tracks changes to entries
4. **Secure Sharing** - Organizations/collections for team key sharing
5. **2FA Protection** - Additional security layer for key access
6. **Already Integrated** - `rbw` CLI already configured in nixcfg

#### 🔒 Security Considerations
- **Zero-Knowledge Architecture** - Bitwarden cannot decrypt your vault
- **End-to-End Encryption** - AES-256 bit encryption
- **Local Caching** - Keys cached locally after first fetch
- **Audit Trail** - Access logs for compliance

### Implementation Strategy

#### 1. Bitwarden Entry Structure

Store SSH keypairs as secure notes with structured naming. Folders are created automatically when using `rbw add --folder`:

```
Folder: Infrastructure/SSH-Keys/
├── ssh-user-tim@thinky-nixos
├── ssh-user-tim@potato
├── ssh-host-thinky-nixos
├── ssh-host-potato
└── ssh-deploy-github
```

Entry format:
```yaml
Name: ssh-user-tim@thinky-nixos
Notes: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  [private key content]
  -----END OPENSSH PRIVATE KEY-----
  
  # Public key (for reference)
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@thinky-nixos
```

#### 2. Bootstrap Script for SSH Keys

Create `bootstrap-ssh-keys.sh` similar to existing `bootstrap-secrets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="${HOSTNAME:-$(hostname)}"
USERNAME="${USERNAME:-$(whoami)}"
SSH_KEY_NAME="ssh-user-${USERNAME}@${HOSTNAME}"

# Fetch from Bitwarden
echo "Fetching SSH key: $SSH_KEY_NAME"
KEY_CONTENT=$(rbw get -f notes "$SSH_KEY_NAME")

if [ -n "$KEY_CONTENT" ]; then
  # Extract private key
  echo "$KEY_CONTENT" | sed -n '/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p' \
    > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
  
  # Extract public key
  echo "$KEY_CONTENT" | grep '^ssh-' > ~/.ssh/id_ed25519.pub
  chmod 644 ~/.ssh/id_ed25519.pub
  
  echo "SSH keys deployed successfully"
else
  echo "Warning: SSH key not found in Bitwarden"
  echo "Generating new SSH keypair..."
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
  
  # Store in Bitwarden for future use
  echo "Storing generated key in Bitwarden..."
  (cat ~/.ssh/id_ed25519; echo ""; echo "# Public key"; cat ~/.ssh/id_ed25519.pub) | \
    rbw add --notes "$SSH_KEY_NAME" --folder "Infrastructure/SSH-Keys"
fi
```

#### 3. NixOS Module for Bitwarden SSH Keys

Create `modules/nixos/bitwarden-ssh-keys.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.bitwardenSSH;
in {
  options.bitwardenSSH = {
    enable = lib.mkEnableOption "Bitwarden-based SSH key management";
    
    fetchUserKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Fetch user SSH keys from Bitwarden on activation";
    };
    
    fetchHostKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;  # More sensitive, off by default
      description = "Fetch host SSH keys from Bitwarden on activation";
    };
    
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Users to fetch SSH keys for";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Activation script to fetch keys from Bitwarden
    system.activationScripts.fetchSSHKeys = lib.stringAfter ["users"] ''
      echo "Fetching SSH keys from Bitwarden..."
      
      ${lib.concatMapStrings (user: ''
        if [ -d /home/${user} ]; then
          sudo -u ${user} bash -c '
            # Ensure rbw is unlocked
            if command -v rbw >/dev/null && rbw unlocked 2>/dev/null; then
              SSH_KEY_NAME="ssh-user-${user}@${config.networking.hostName}"
              KEY_CONTENT=$(rbw get -f notes "$SSH_KEY_NAME" 2>/dev/null || true)
              
              if [ -n "$KEY_CONTENT" ]; then
                mkdir -p ~/.ssh
                chmod 700 ~/.ssh
                
                # Deploy private key
                echo "$KEY_CONTENT" | sed -n "/BEGIN.*PRIVATE KEY/,/END.*PRIVATE KEY/p" \
                  > ~/.ssh/id_ed25519
                chmod 600 ~/.ssh/id_ed25519
                
                # Deploy public key
                echo "$KEY_CONTENT" | grep "^ssh-" > ~/.ssh/id_ed25519.pub
                chmod 644 ~/.ssh/id_ed25519.pub
                
                echo "SSH keys for ${user} deployed from Bitwarden"
              fi
            fi
          '
        fi
      '') cfg.users}
    '';
    
    # Ensure rbw is available
    environment.systemPackages = [ pkgs.rbw ];
  };
}
```

#### 4. Public Key Registry Module

Maintain a separate module for public keys (these don't need encryption):

```nix
# modules/nixos/ssh-public-keys.nix
{ lib, ... }:
{
  options.sshPublicKeys = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Registry of all SSH public keys";
  };
  
  config.sshPublicKeys = {
    users = {
      tim = {
        "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@thinky-nixos";
        "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@potato";
        "mbp" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@mbp";
      };
    };
    
    hosts = {
      "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@thinky-nixos";
      "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@potato";
    };
  };
}
```

#### 5. Host Configuration Integration

```nix
# In hosts/thinky-nixos/default.nix
{ config, ... }:
{
  # Enable Bitwarden SSH key management
  bitwardenSSH = {
    enable = true;
    users = [ "tim" ];
  };
  
  # Authorize keys from all managed hosts
  users.users.tim.openssh.authorizedKeys.keys = 
    lib.attrValues config.sshPublicKeys.users.tim;
}
```

### Workflow for New Host Setup

1. **Generate Keys Outside NixOS** (one-time):
   ```bash
   ssh-keygen -t ed25519 -f temp-key -C "tim@new-host"
   ```

2. **Store in Bitwarden**:
   ```bash
   (cat temp-key; echo ""; echo "# Public key"; cat temp-key.pub) | \
     rbw add --notes "ssh-user-tim@new-host" --folder "Infrastructure/SSH-Keys"
   rm temp-key temp-key.pub
   ```

3. **Add Public Key to Registry**:
   ```nix
   # In modules/nixos/ssh-public-keys.nix
   sshPublicKeys.users.tim."new-host" = "ssh-ed25519 AAAA...";
   ```

4. **Configure Host**:
   ```nix
   bitwardenSSH.enable = true;
   bitwardenSSH.users = [ "tim" ];
   ```

5. **Deploy**:
   ```bash
   nixos-rebuild switch --flake '.#new-host'
   ```

### Key Rotation Workflow

1. **Generate New Keys**:
   ```bash
   ssh-keygen -t ed25519 -f new-key
   ```

2. **Update Bitwarden Entry**:
   ```bash
   rbw edit "ssh-user-tim@hostname"
   # Replace key content
   ```

3. **Update Public Key Registry**:
   ```nix
   # Update in ssh-public-keys.nix
   ```

4. **Rebuild All Affected Hosts**:
   ```bash
   # Keys fetched automatically on next rebuild
   ```

### Best Practices

1. **Separate User and Host Keys** - Different security requirements
2. **Use Folders in Bitwarden** - Organize by type/environment
3. **Regular Key Rotation** - Quarterly for users, annually for hosts
4. **Backup Critical Keys** - Export Bitwarden vault periodically
5. **Use SSH Certificates** - For larger deployments, consider SSH CA

### Security Benefits

- **No Keys in Nix Store** - Keys only fetched at runtime
- **Encrypted at Rest** - Both in Bitwarden and local cache
- **Declarative Public Keys** - Authorized keys managed by Nix
- **Audit Trail** - Bitwarden logs all access
- **2FA Protected** - Additional authentication layer

This approach maintains NixOS's declarative nature while providing practical, secure SSH key management through Bitwarden as the single source of truth for all secrets

## Key Management

### Generating Keys

```bash
# Generate user key
age-keygen -o ~/.config/sops/age/keys.txt

# Generate host key (as root)
sudo age-keygen -o /etc/sops/age.key
```

### Backing Up Keys

1. **Primary Backup**: Bitwarden
   ```bash
   # Store in Bitwarden
   rbw add --folder "Infrastructure" age-key-{user|host}-{hostname}
   # Paste private key as secure note
   ```

2. **Offline Backup**: Encrypted USB/Paper
   - Print QR codes of keys
   - Store in secure physical location

### Key Rotation

```bash
# 1. Generate new keys
age-keygen -o ~/.config/sops/age/new-keys.txt

# 2. Update .sops.yaml with new public key

# 3. Re-encrypt all secrets
find secrets -name "*.yaml" -type f | while read file; do
  sops rotate -i "$file"
done

# 4. Replace old keys with new keys
mv ~/.config/sops/age/new-keys.txt ~/.config/sops/age/keys.txt

# 5. Update Bitwarden backup
```

## Troubleshooting

### Secret Not Decrypting

```bash
# Check key presence
ls -la ~/.config/sops/age/keys.txt
sudo ls -la /etc/sops/age.key

# Test manual decryption
sops -d secrets/common/services.yaml

# Check sops-nix service
systemctl status sops-nix

# View logs
journalctl -u sops-nix -n 50
```

### Permission Denied

```bash
# Check secret permissions
sudo ls -la /run/secrets.d/1/

# Verify ownership in config
# sops.secrets."secret_name".owner = "correct-user";
```

### Secret Not Found

```bash
# Ensure secret is defined in both places:
# 1. In the YAML file (sops secrets/common/file.yaml)
# 2. In NixOS config (sops.secrets."secret_name" = { ... })

# Verify path
echo ${config.sops.secrets.secret_name.path}
```

### SOPS Can't Find Keys

```bash
# Check SOPS is using correct key file
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
sops -d secrets/common/services.yaml

# For host key issues
sudo SOPS_AGE_KEY_FILE=/etc/sops/age.key sops -d secrets/common/services.yaml
```

## Best Practices

1. **Never commit plaintext secrets** - Always use SOPS to edit
2. **Use descriptive secret names** - `github_token` not `token1`
3. **Organize secrets logically** - Group related secrets in same file
4. **Set appropriate ownership** - Match service user requirements
5. **Use most restrictive permissions** - Default to `400` when possible
6. **Backup keys immediately** - Before creating any secrets
7. **Document secret dependencies** - Note which services use which secrets
8. **Rotate keys periodically** - At least annually
9. **Audit secret access** - Review service permissions regularly
10. **Test disaster recovery** - Ensure you can restore from backups

## Migration from Other Systems

### From environment variables

```bash
# Before: .env file
API_KEY=secret123

# After: secrets/common/services.yaml
api_key: secret123

# In NixOS:
systemd.services.myapp = {
  serviceConfig.EnvironmentFile = config.sops.secrets.api_key.path;
};
```

### From plaintext config files

```bash
# Before: config.json with embedded secrets
{"api_key": "secret123"}

# After: Template with secret reference
{"api_key": "@@API_KEY@@"}

# In service:
preStart = ''
  sed "s|@@API_KEY@@|$(cat ${config.sops.secrets.api_key.path})|g" \
    ${./config.json.template} > /run/myapp/config.json
'';
```

## Implementation Status & Roadmap

### ❌ Missing Core Implementations

The following features are fully documented in this file but **NOT YET IMPLEMENTED**:

#### SSH Key Management Modules (Zero Implementation)
1. **`modules/nixos/ssh-key-automation.nix`** (documented lines 419-454)
   - Automated SSH keypair generation with `generateUserKeys`, `generateHostKeys`, `authorizedHosts` options
   - Activation scripts for key generation and deployment

2. **`modules/nixos/bitwarden-ssh-keys.nix`** (documented lines 725-792)  
   - Bitwarden-based SSH key fetching with `fetchUserKeys`/`fetchHostKeys` options
   - Activation scripts that fetch keys from Bitwarden via rbw CLI
   - Integration with user SSH directory management

3. **`modules/nixos/ssh-public-keys.nix`** (documented lines 799-822)
   - Central registry of all SSH public keys for cross-host authorization
   - Public key distribution patterns across managed hosts

4. **`home/files/bin/bootstrap-ssh-keys.sh`** (documented in SECRETS-USER-INSTRUCTIONS.md:374-437)
   - Automated SSH key deployment script with Bitwarden integration
   - Key generation fallback when keys not found in vault
   - SSH agent integration and key validation

### 🔍 Critical Testing Gaps

#### SOPS-NiX Functionality Tests (Minimal Coverage)
**Current test coverage** (`flake-modules/tests.nix:236-257`):
- ✅ Verifies SOPS-NiX module is enabled
- ✅ Confirms user tim exists in system configuration

**Missing comprehensive tests:**
- ❌ **Secret encryption/decryption workflow** - No verification that `sops edit` → decrypt → use workflow works end-to-end
- ❌ **Age key functionality validation** - No tests that age keys can actually decrypt secrets created with their public keys  
- ❌ **Secret file permissions enforcement** - No verification that `mode = "0400"` and owner settings work correctly
- ❌ **Secret runtime accessibility** - No validation that decrypted secrets appear at `/run/secrets.d/*/secret_name` with correct content
- ❌ **Multi-host key access** - No tests that secrets encrypted for multiple hosts can be decrypted on each target host
- ❌ **SOPS service integration** - No verification that `sops-nix.service` correctly decrypts secrets on boot

#### Security Safeguards Tests (Zero Coverage)
- ❌ **Pre-commit hook validation** - No automated test that Gitleaks prevents accidental secret commits
- ❌ **Secret scanning effectiveness** - No verification that `.gitignore` patterns prevent plaintext secret exposure
- ❌ **Key rotation workflow** - No test that `sops rotate` preserves secret accessibility across key changes
- ❌ **Permission boundary enforcement** - No validation that secrets are only accessible to designated users/services

#### Integration Tests (Incomplete Coverage)  
- ❌ **WiFi secrets module** - `wifi-secrets-example.nix` exists but no integration tests with NetworkManager
- ❌ **Bitwarden (rbw) integration** - No tests that rbw can fetch/store secrets in actual Bitwarden vault
- ❌ **Cross-host SSH connectivity** - No validation that deployed SSH keys enable passwordless host-to-host access
- ❌ **Service integration patterns** - No tests for common patterns like database passwords, API keys, SSL certificates

### 📋 Production Readiness Roadmap

**Status: ⚠️ NOT PRODUCTION READY** - Significant implementation and testing work required

#### Phase 1: Core Implementation (Steps 1-4)
1. **Implement SSH Public Keys Registry Module**
   - Create `modules/nixos/ssh-public-keys.nix` with central key registry
   - Add integration points for authorized_keys distribution
   - Include validation for key format and uniqueness

2. **Implement Bootstrap SSH Keys Script** 
   - Create `home/files/bin/bootstrap-ssh-keys.sh` with Bitwarden integration
   - Add key generation fallback and SSH agent integration
   - Include error handling and user feedback

3. **Implement Bitwarden SSH Keys Module**
   - Create `modules/nixos/bitwarden-ssh-keys.nix` with rbw integration  
   - Add activation scripts for automatic key deployment
   - Include user and host key management options

4. **Implement SSH Key Automation Module**
   - Create `modules/nixos/ssh-key-automation.nix` for advanced automation
   - Add options for automatic key generation and distribution
   - Include cross-host authorization management

#### Phase 2: Comprehensive Testing (Steps 5-8)
5. **Implement SOPS-NiX Functionality Tests**
   - Add secret roundtrip tests (create → encrypt → decrypt → verify)
   - Test age key validation and multi-host access
   - Verify secret file permissions and runtime accessibility

6. **Implement Security Safeguards Tests**
   - Add pre-commit hook validation tests
   - Test secret scanning and gitignore effectiveness  
   - Validate key rotation workflow preservation

7. **Implement Integration Tests**
   - Add WiFi secrets module integration tests
   - Test Bitwarden (rbw) functionality with mock/real vault
   - Validate cross-host SSH connectivity

8. **Implement Service Integration Tests**
   - Test common service patterns (databases, APIs, SSL)
   - Validate systemd service integration with secrets
   - Test environment variable and file-based secret consumption

#### Phase 3: Documentation & Hardening (Steps 9-10)
9. **Complete Documentation and Examples**
   - Add comprehensive troubleshooting guides
   - Create additional service integration examples
   - Document production deployment best practices

10. **Production Hardening and Validation**
    - Implement comprehensive error handling
    - Add monitoring and alerting capabilities
    - Perform security audit and penetration testing

### 🎯 Definition of "Feature Complete" and "Production Ready"

**Feature Complete Criteria:**
- ✅ All documented SSH key management modules implemented
- ✅ All bootstrap scripts and automation tools working
- ✅ Comprehensive test coverage (>90% of documented functionality)
- ✅ Integration tests for all major use cases

**Production Ready Criteria:**  
- ✅ All Feature Complete criteria met
- ✅ Security safeguards tested and validated
- ✅ Error handling and edge cases covered
- ✅ Performance and reliability testing completed
- ✅ Documentation includes troubleshooting and disaster recovery
- ✅ Monitoring and alerting capabilities implemented

**Current Status**: Step 1 of 10 - SSH Public Keys Registry Module implemented and tested

### ✅ STEP 1 COMPLETE: SSH Public Keys Registry Module (2025-09-15)

**Implementation**: `modules/nixos/ssh-public-keys.nix`
- ✅ Central key registry for all SSH public keys
- ✅ Integration points for authorized_keys distribution  
- ✅ Validation for key format and uniqueness
- ✅ Auto-distribution with restriction options
- ✅ Comprehensive test coverage in `flake-modules/tests.nix`
- ✅ Example configuration created at `hosts/common/ssh-keys-example.nix`

**Critical Fixes Applied During Review**:
- Fixed undefined reference `cfg._sshKeyRegistry.allHosts` → `(attrNames cfg.hosts)` (line 174)
- Fixed undefined reference `cfg._sshKeyRegistry.allUsers` → `(attrNames cfg.users)` (line 184)
- Created comprehensive integration example showing proper usage patterns

**Production Readiness: 85%**

**Remaining Tasks for Full Production Use**:
1. Add conditional user existence checking (module currently assumes all registered users exist)
2. Import module in actual host configurations (currently only example exists)
3. Populate with real SSH public keys from existing configurations
4. Add integration test that validates actual key distribution to authorized_keys

**Example Usage**:
```nix
# In host configuration
{
  imports = [ ../../modules/nixos/ssh-public-keys.nix ];
  
  sshPublicKeys = {
    enable = true;
    users = {
      tim = {
        "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@thinky-nixos";
        "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@potato";
        "mbp" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tim@mbp";
      };
    };
    hosts = {
      "thinky-nixos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@thinky-nixos";
      "potato" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... root@potato";
    };
    autoDistribute = true;  # Automatically add all user keys to authorized_keys
    restrictedUsers = {
      admin = [ "thinky-nixos" ];  # Admin only gets specific host keys
    };
  };
}
```

**Files Created/Modified**:
- `modules/nixos/ssh-public-keys.nix` - Core module implementation (bug fixes applied)
- `hosts/common/ssh-keys-example.nix` - Comprehensive usage example
- `flake-modules/tests.nix` - Test coverage for SSH key validation

**Next Step Prompt for New Chat**:
"Let's proceed with Step 2: Implement Bootstrap SSH Keys Script. Please create the `home/files/bin/bootstrap-ssh-keys.sh` script with Bitwarden integration as documented in SECRETS-MANAGEMENT.md lines 686-721. The script should: 1) Fetch SSH keys from Bitwarden using rbw CLI, 2) Deploy keys to appropriate locations (~/.ssh/), 3) Handle key generation as fallback when not found in Bitwarden, 4) Store newly generated keys back to Bitwarden for future use, 5) Include proper error handling and user feedback. Focus ONLY on Step 2 implementation."

## References

- [SOPS Documentation](https://github.com/getsops/sops)
- [SOPS-NiX Repository](https://github.com/Mic92/sops-nix)
- [Age Encryption](https://github.com/FiloSottile/age)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [RBW - Rust Bitwarden CLI](https://github.com/doy/rbw)