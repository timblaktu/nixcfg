# SOPS-NiX Secrets Management System

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

## References

- [SOPS Documentation](https://github.com/getsops/sops)
- [SOPS-NiX Repository](https://github.com/Mic92/sops-nix)
- [Age Encryption](https://github.com/FiloSottile/age)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [RBW - Rust Bitwarden CLI](https://github.com/doy/rbw)