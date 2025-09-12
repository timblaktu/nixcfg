# Secrets Management Architecture

## Current State Analysis

### Existing Infrastructure

1. **SOPS-NiX Integration**
   - Already included in flake.nix as input
   - Configuration stub exists at `modules/nixos/sops-integration.nix`
   - `.sops.yaml` configuration file present with placeholder age keys
   - Directory structure: `secrets/` with subdirectories for common and host-specific secrets

2. **Bootstrap Script**
   - `home/files/bin/bootstrap-secrets.sh` - Comprehensive script that:
     - Uses rbw (Rust Bitwarden client) to fetch age keys from Bitwarden
     - Configures rbw with email, pinentry, and API settings
     - Manages age key storage in `~/.config/sops/age/`
     - Supports both regular and enterprise Bitwarden instances

3. **Current Key Management**
   - Age keys are stored in Bitwarden as secure notes
   - Keys are fetched and placed in `~/.config/sops/age/keys.txt`
   - Public keys are referenced in `.sops.yaml` for encryption rules

### Technology Choices

#### SOPS-NiX (Currently Selected)
**Pros:**
- Already integrated in flake
- Uses age encryption (modern, simple)
- Integrates well with NixOS modules
- Secrets decrypted at activation time
- Good documentation and community support

**Cons:**
- Requires manual key management
- No built-in key rotation
- Secrets stored in git (encrypted)

#### Agenix (Alternative)
**Pros:**
- Similar to sops-nix but simpler
- Pure Nix implementation
- Also uses age encryption
- Slightly easier configuration

**Cons:**
- Less feature-rich than sops-nix
- Smaller community
- Also stores secrets in git

#### External Secret Stores (Alternative)
**Options:** HashiCorp Vault, AWS Secrets Manager, Azure Key Vault
**Pros:**
- Centralized management
- Audit logging
- Dynamic secrets
- Key rotation

**Cons:**
- Additional infrastructure
- Network dependency
- More complex setup

## Recommended Architecture

### Phase 1: Foundation (Immediate)
1. **Activate SOPS-NiX** with existing configuration
2. **Install rbw** and pinentry in home-manager
3. **Generate host keys** for each system
4. **Create initial secrets** structure

### Phase 2: Enhancement (Short-term)
1. **Implement secret categories:**
   - System secrets (SSH host keys, machine-id)
   - Service secrets (API keys, database passwords)
   - User secrets (personal tokens, SSH keys)
   
2. **Establish naming conventions:**
   - `secrets/common/` - Shared across all hosts
   - `secrets/<hostname>/` - Host-specific
   - `secrets/users/<username>/` - User-specific

### Phase 3: Advanced (Long-term)
1. **Key rotation strategy**
2. **Backup and recovery procedures**
3. **Consider external secret store integration**

## Implementation Plan

### 1. RBW Installation (Immediate Task)
Add to home-manager configuration:
- rbw package
- pinentry program (pinentry-gtk2, pinentry-qt, or pinentry-curses)
- Configuration for rbw settings
- Shell aliases for common operations

### 2. SOPS-NiX Activation
- Update host configurations to import sops module
- Configure defaultSopsFile per host
- Define initial secrets

### 3. Key Generation
- Generate age keys for each host
- Store public keys in `.sops.yaml`
- Update Bitwarden with private keys

### 4. Secret Migration
- Identify existing plaintext secrets
- Encrypt using sops
- Update configurations to reference encrypted secrets

## Security Considerations

1. **Key Storage:**
   - User keys: Bitwarden (already implemented)
   - Host keys: Generated on first boot, stored locally
   - Backup keys: Offline storage recommended

2. **Access Control:**
   - Use `.sops.yaml` creation rules for granular access
   - Separate keys for users and hosts
   - Principle of least privilege

3. **Git Security:**
   - Never commit plaintext secrets
   - Use `.gitignore` for temporary files
   - Regular audit of repository

4. **Operational Security:**
   - Regular key rotation schedule
   - Audit log monitoring
   - Incident response plan

## Directory Structure

```
nixcfg/
├── .sops.yaml                    # SOPS configuration and key assignments
├── secrets/
│   ├── README.md                 # Documentation
│   ├── common/                   # Shared secrets
│   │   ├── example.yaml.template # Template for new secrets
│   │   └── services.yaml         # Service API keys, tokens
│   ├── mbp/                      # MacBook Pro specific
│   ├── potato/                   # Potato host specific
│   └── thinky-nixos/            # WSL host specific
├── modules/
│   └── nixos/
│       └── sops-integration.nix  # NixOS SOPS module
└── home/
    └── files/
        └── bin/
            └── bootstrap-secrets.sh # Key bootstrap script

```

## Implementation Status

### ✅ Phase 1: Foundation (COMPLETED - 2025-09-12)
1. **RBW Installation** - Installed and configured with rbw-init
2. **Age Key Generation** - Generated for user (tim) and host (thinky-nixos)
3. **Bitwarden Storage** - Keys backed up to Bitwarden vault
4. **SOPS Configuration** - Updated .sops.yaml with real public keys
5. **First Secret Created** - Test secret encrypted at `secrets/common/test-secret.yaml`

### ✅ Phase 2: SOPS-NiX Activation (COMPLETED - 2025-09-12)
1. **Created sops-nix.nix module** - Wrapper module for clean configuration
2. **Activated in thinky-nixos** - Added to host imports and configured
3. **Secrets decrypting successfully** - Verified at `/run/secrets.d/1/`
4. **SSH host key imported** - SOPS automatically imported existing SSH key as age key

### Generated Keys
- **User Key (tim)**: `age1s3w0vh40qtjzx677xdda7lv5sqnhrxg9ae306zrkx4deurcvx90sajtlsk`
  - Private key: `~/.config/sops/age/keys.txt`
  - Backed up in Bitwarden as: `age-key-tim-user`
  
- **Host Key (thinky-nixos)**: `age1rz0k6055dsat660rs3y8jdypmjxdjwaya2w4v0x6q7646m6n8atszz0vzx`
  - Private key: `/etc/sops/age.key`
  - Backed up in Bitwarden as: `age-key-thinky-nixos-host`

## Next Steps (Phase 3: Production Usage)

1. **Create production secrets structure**
   - Remove test-secret.yaml
   - Create structured secrets for services, SSH keys, API tokens
   - Use proper naming conventions

2. **Integrate with services**
   - Configure services to use decrypted secrets
   - Set proper ownership and permissions
   - Use systemd EnvironmentFile for service secrets

3. **Generate keys for other hosts**
   - MacBook Pro (mbp) - when setting up nix-darwin
   - Potato host - when configuring
   - Update .sops.yaml with their public keys

4. **Implement key rotation strategy**
   - Document rotation procedures
   - Set up periodic reminders
   - Create rotation scripts

## How to Use Secrets in Services

### Example: Using API Key in a Service
```nix
# In your NixOS configuration:
sops.secrets."github_token" = {
  owner = "git";
  group = "git";
  mode = "0400";
};

systemd.services.my-service = {
  serviceConfig = {
    EnvironmentFile = config.sops.secrets.github_token.path;
  };
};
```

### Example: Using Database Password
```nix
sops.secrets."db_password" = {
  owner = "postgres";
  group = "postgres";
};

services.postgresql = {
  initialScript = pkgs.writeText "init.sql" ''
    ALTER USER postgres PASSWORD '$(cat ${config.sops.secrets.db_password.path})';
  '';
};
```

## Adding New Secrets

1. Create or edit encrypted file:
   ```bash
   sops secrets/common/services.yaml
   ```

2. Add secret definition in host config:
   ```nix
   sops.secrets."my_new_secret" = {
     owner = "user";
     group = "group";
     mode = "0400";
   };
   ```

3. Rebuild system:
   ```bash
   sudo nixos-rebuild switch --flake '.#hostname'
   ```

4. Access decrypted secret:
   ```bash
   cat /run/secrets.d/1/my_new_secret
   ```

## Questions for Decision Making

1. Do you want to stick with SOPS-NiX or consider alternatives?
2. What types of secrets do you need to manage? (SSH keys, API tokens, passwords, certificates?)
3. Do you have preference for pinentry program? (GTK, Qt, or terminal-based?)
4. Should we implement host key generation in the NixOS configuration?
5. Do you need secret sharing between specific host groups?
6. What's your backup strategy for the age keys?

## References

- [SOPS-NiX Documentation](https://github.com/Mic92/sops-nix)
- [Age Encryption](https://github.com/FiloSottile/age)
- [RBW - Rust Bitwarden Client](https://github.com/doy/rbw)
- [NixOS Secrets Management Guide](https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes)