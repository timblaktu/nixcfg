# Administrator Handbook

Complete operational guide for managing SSH keys and secrets in production NixOS environments.

## Table of Contents

1. [Day-1 Setup](#day-1-setup)
2. [Daily Operations](#daily-operations)
3. [Key Rotation Schedule](#key-rotation-schedule)
4. [User Management](#user-management)
5. [Host Onboarding](#host-onboarding)
6. [Incident Response](#incident-response)
7. [Upgrade Procedures](#upgrade-procedures)
8. [Monitoring and Alerts](#monitoring-and-alerts)
9. [Backup and Recovery](#backup-and-recovery)
10. [Operational Checklists](#operational-checklists)

## Day-1 Setup

### Initial System Deployment

#### Prerequisites Checklist

- [ ] NixOS 23.11 or later installed
- [ ] Git repository for configuration
- [ ] Bitwarden account (optional but recommended)
- [ ] SSH access to target systems
- [ ] Age encryption tool installed

#### Step 1: Repository Setup

```bash
# Clone the configuration repository
git clone https://github.com/your-org/nixcfg.git
cd nixcfg

# Initialize git-crypt or SOPS structure
mkdir -p secrets/{common,hosts,users}

# Create .sops.yaml configuration
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets/common/.*\.yaml$
    age: age1yourpublickey...
  - path_regex: secrets/hosts/.*\.yaml$
    age: age1hostkey...
EOF
```

#### Step 2: Generate Initial Keys

```bash
# Generate age key for admin user
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key for .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt

# Generate SSH host key if not present
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Convert SSH host key to age
sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key \
  > /root/.config/sops/age/keys.txt
```

#### Step 3: Create First Secrets

```bash
# Create initial secrets file
sops secrets/common/initial.yaml

# Add basic structure:
# database:
#   password: "initial-password"
# api:
#   key: "api-key-here"
```

#### Step 4: Configure NixOS

```nix
# /etc/nixos/configuration.nix or flake.nix
{
  imports = [
    ./modules/sops-nix.nix
    ./modules/ssh-keys.nix
  ];

  sops.defaultSopsFile = ./secrets/common/initial.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  
  # Enable SSH key management
  services.sshKeyManagement = {
    enable = true;
    users = [ "admin" "deploy" ];
  };
}
```

#### Step 5: Initial Deployment

```bash
# Build and test configuration
nixos-rebuild dry-build

# Deploy to system
sudo nixos-rebuild switch

# Verify secrets are available
sudo ls -la /run/secrets.d/
```

### First-Time Security Setup

```bash
# 1. Store keys in Bitwarden
bw create item --organizationid null \
  --type 2 \
  --name "NixOS Age Key - $(hostname)" \
  --notes "$(cat ~/.config/sops/age/keys.txt)"

# 2. Set up key backup
./scripts/backup-keys.sh

# 3. Initialize audit log
sudo touch /var/log/secrets-audit.log
sudo chmod 600 /var/log/secrets-audit.log

# 4. Set up monitoring
sudo systemctl enable secrets-monitor.service
```

## Daily Operations

### Routine Tasks

#### Morning Checks (5 minutes)

```bash
# Check system status
systemctl status sops-nix.service
systemctl status ssh-key-manager.service

# Verify secrets are accessible
sudo test -f /run/secrets.d/1/database/password && echo "✓ Secrets OK"

# Check for failed services
systemctl --failed

# Review overnight logs
journalctl --since "yesterday 18:00" -p warning
```

#### Adding a New Secret

```bash
# 1. Edit secrets file
sops secrets/common/services.yaml

# 2. Add new secret in YAML format
# new_service:
#   api_key: "key-value"
#   password: "pass-value"

# 3. Update NixOS configuration
cat >> modules/services/new-service.nix <<'EOF'
{ config, ... }:
{
  sops.secrets."new_service/api_key" = {
    owner = "new-service";
    mode = "0400";
  };
}
EOF

# 4. Deploy changes
sudo nixos-rebuild switch

# 5. Verify secret is available
sudo cat /run/secrets.d/1/new_service/api_key
```

#### Updating Existing Secrets

```bash
# 1. Create backup
cp secrets/common/services.yaml secrets/common/services.yaml.$(date +%Y%m%d)

# 2. Edit and update
sops secrets/common/services.yaml

# 3. Deploy immediately for critical services
sudo nixos-rebuild switch

# 4. Restart affected services
sudo systemctl restart affected-service.service

# 5. Verify service health
systemctl status affected-service.service
```

### Common Administrative Commands

```bash
# View all managed users
cat /etc/nixos/modules/users/ssh-keys-registry.nix | grep "keys ="

# Check SOPS status
sops --version
sops -d secrets/common/services.yaml | head -n 5

# List all secrets
find secrets/ -name "*.yaml" -type f

# Audit secret access
sudo ausearch -f /run/secrets.d/ --start today

# Check system state
nix-store --verify --check-contents

# Garbage collection
sudo nix-collect-garbage -d
```

## Key Rotation Schedule

### Rotation Policy

| Key Type | Rotation Frequency | Responsible Party | Automation |
|----------|-------------------|-------------------|------------|
| SSH Host Keys | Annual | System Admin | Manual |
| User SSH Keys | 90 days | User/Admin | Semi-auto |
| Age Encryption Keys | Annual | Security Team | Manual |
| Service API Keys | 30-90 days | Service Owner | Automated |
| Database Passwords | 90 days | DBA Team | Semi-auto |
| TLS Certificates | Before expiry | System Admin | Automated |

### Monthly Rotation Procedure

```bash
#!/bin/bash
# Monthly key rotation script

set -e

echo "Starting monthly key rotation - $(date)"

# 1. Rotate service passwords
for service in postgresql mysql redis; do
  echo "Rotating $service password..."
  
  # Generate new password
  NEW_PASS=$(openssl rand -base64 32)
  
  # Update in SOPS
  sops set secrets/common/services.yaml \
    "['$service']['password']" "$NEW_PASS"
  
  # Deploy
  sudo nixos-rebuild switch
  
  # Update service
  case $service in
    postgresql)
      sudo -u postgres psql -c "ALTER USER app PASSWORD '$NEW_PASS';"
      ;;
    mysql)
      mysql -u root -e "ALTER USER 'app'@'localhost' IDENTIFIED BY '$NEW_PASS';"
      ;;
    redis)
      redis-cli CONFIG SET requirepass "$NEW_PASS"
      ;;
  esac
done

# 2. Rotate API keys (example)
./scripts/rotate-api-keys.sh

# 3. Generate rotation report
cat > /var/log/rotation-$(date +%Y%m).log <<EOF
Rotation completed: $(date)
Services rotated: postgresql, mysql, redis
Next rotation: $(date -d "+30 days" +%Y-%m-%d)
EOF

echo "Rotation complete"
```

### Annual Key Rotation

```bash
# Annual comprehensive rotation

# 1. Generate new age key
age-keygen -o ~/.config/sops/age/keys.txt.new

# 2. Add new key to .sops.yaml
NEW_AGE_PUBLIC=$(age-keygen -y ~/.config/sops/age/keys.txt.new)
# Edit .sops.yaml to add new key alongside old

# 3. Update all secrets with new key
for file in secrets/**/*.yaml; do
  sops updatekeys "$file"
done

# 4. Test decryption with new key
mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.old
mv ~/.config/sops/age/keys.txt.new ~/.config/sops/age/keys.txt

# 5. Deploy and verify
sudo nixos-rebuild switch

# 6. After verification, remove old key from .sops.yaml
# and run updatekeys again
```

## User Management

### Adding a New User

```bash
# 1. Have user generate SSH key
# On user's machine:
ssh-keygen -t ed25519 -C "user@example.com"

# 2. Add to registry
cat >> modules/users/ssh-keys-registry.nix <<EOF

  newuser = {
    keys = [
      "ssh-ed25519 AAAAC3... user@example.com"
    ];
    trustedBy = [ "admin" ];
  };
EOF

# 3. Create user account
cat >> hosts/$(hostname)/users.nix <<EOF
  users.users.newuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];  # If admin
    openssh.authorizedKeys.keys = 
      config.users.users.newuser.openssh.authorizedKeys.keys;
  };
EOF

# 4. Grant secret access if needed
cat >> modules/secrets/user-access.nix <<EOF
  sops.secrets."service/api_key".owner = "newuser";
EOF

# 5. Deploy
sudo nixos-rebuild switch

# 6. Verify
id newuser
sudo -u newuser ssh-add -l
```

### Removing a User

```bash
# 1. Revoke secret access
# Remove from all sops.secrets.*.owner entries

# 2. Remove from registry
# Delete user block from ssh-keys-registry.nix

# 3. Disable account immediately
sudo usermod -L olduser

# 4. Archive user data
sudo tar -czf /backup/olduser-$(date +%Y%m%d).tar.gz /home/olduser/

# 5. Remove user configuration
# Remove from hosts/*/users.nix

# 6. Deploy changes
sudo nixos-rebuild switch

# 7. Clean up after verification
sudo userdel -r olduser
```

### Managing User Permissions

```nix
# Fine-grained secret access control
{
  # Read-only access to specific secrets
  sops.secrets."database/readonly_password" = {
    owner = "analyst";
    group = "analytics";
    mode = "0440";
  };

  # Admin full access
  sops.secrets."admin/master_key" = {
    owner = "root";
    group = "wheel";
    mode = "0440";
  };

  # Service-specific access
  sops.secrets."app/config" = {
    owner = "app-service";
    group = "app-service";
    mode = "0400";
    restartUnits = [ "app.service" ];
  };
}
```

## Host Onboarding

### Adding a New Host

```bash
# On the new host:

# 1. Install NixOS base system
# Follow standard installation

# 2. Generate host SSH key
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# 3. Generate age key from SSH key
sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key \
  > /root/.config/sops/age/keys.txt

# 4. Get public age key
sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
# Copy this output

# On management system:

# 5. Add host to .sops.yaml
cat >> .sops.yaml <<EOF
  - path_regex: secrets/hosts/newhost/.*\.yaml$
    age: age1newHostPublicKey...
EOF

# 6. Create host configuration
mkdir -p hosts/newhost
cp hosts/template/* hosts/newhost/

# 7. Update flake.nix
# Add newhost to nixosConfigurations

# 8. Create host-specific secrets
sops secrets/hosts/newhost/secrets.yaml

# 9. Deploy configuration
nixos-rebuild switch --flake .#newhost --target-host newhost

# 10. Verify
ssh newhost "sudo systemctl status sops-nix"
```

### Host Decommissioning

```bash
# 1. Backup secrets and configuration
rsync -av oldhost:/etc/nixos/ /backup/oldhost-nixos/
sops -d secrets/hosts/oldhost/secrets.yaml > /backup/oldhost-secrets.txt

# 2. Revoke host access
# Remove host key from .sops.yaml

# 3. Update all shared secrets
for file in secrets/common/*.yaml; do
  sops updatekeys "$file"
done

# 4. Remove from infrastructure
# Remove from flake.nix
# Delete hosts/oldhost/

# 5. Commit changes
git add -A
git commit -m "Decommission host: oldhost"

# 6. Wipe host (if physical access)
dd if=/dev/urandom of=/dev/sda bs=1M
```

## Incident Response

### Compromised Key Response

```bash
#!/bin/bash
# Emergency key rotation after compromise

set -e

echo "INCIDENT: Key compromise detected - $(date)"

# 1. Generate new keys immediately
age-keygen -o ~/.config/sops/age/keys.txt.emergency
NEW_KEY=$(age-keygen -y ~/.config/sops/age/keys.txt.emergency)

# 2. Update .sops.yaml with ONLY new key
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*\.yaml$
    age: $NEW_KEY
EOF

# 3. Re-encrypt all secrets
for file in secrets/**/*.yaml; do
  # Decrypt with old key
  sops -d "$file" > "/tmp/$(basename $file).plain"
  # Re-encrypt with new key
  mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.compromised
  mv ~/.config/sops/age/keys.txt.emergency ~/.config/sops/age/keys.txt
  sops -e "/tmp/$(basename $file).plain" > "$file"
  shred -u "/tmp/$(basename $file).plain"
done

# 4. Deploy immediately to all hosts
for host in $(nix flake show --json | jq -r '.nixosConfigurations | keys[]'); do
  echo "Updating host: $host"
  nixos-rebuild switch --flake .#$host --target-host $host
done

# 5. Rotate all managed secrets
./scripts/rotate-all-passwords.sh

# 6. Audit access logs
sudo aureport -au --start today

# 7. Document incident
cat > /var/log/incident-$(date +%Y%m%d-%H%M).log <<EOF
Incident: Key compromise
Time: $(date)
Action: Emergency rotation completed
Affected systems: All
New key fingerprint: $NEW_KEY
EOF

echo "Emergency rotation complete"
```

### Secret Leak Response

```bash
# If a secret is exposed (e.g., in logs, commits)

# 1. Identify exposed secret
EXPOSED_SECRET="database/password"

# 2. Generate replacement immediately
NEW_VALUE=$(openssl rand -base64 32)

# 3. Update secret
sops set secrets/common/services.yaml "['database']['password']" "$NEW_VALUE"

# 4. Deploy immediately
sudo nixos-rebuild switch

# 5. Update affected service
sudo -u postgres psql -c "ALTER USER app PASSWORD '$NEW_VALUE';"

# 6. Scan for other exposures
git log -p | grep -i password
grep -r "password" /var/log/

# 7. Clean up
# Remove from git history if needed
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/file" \
  --prune-empty --tag-name-filter cat -- --all
```

### System Breach Protocol

```bash
# Full system compromise response

# 1. Isolate affected systems
iptables -I INPUT -j DROP
iptables -I OUTPUT -j DROP
iptables -I INPUT -s management.local -j ACCEPT

# 2. Preserve evidence
dd if=/dev/sda of=/mnt/backup/forensics-$(date +%Y%m%d).img

# 3. Rotate ALL credentials
./scripts/emergency-rotation-all.sh

# 4. Rebuild from clean source
cd /tmp
git clone https://github.com/your-org/nixcfg.git clean-config
cd clean-config

# 5. Generate entirely new key infrastructure
./scripts/regenerate-all-keys.sh

# 6. Deploy fresh systems
nixos-rebuild boot --flake .

# 7. Restore data from verified backups
# Only after verification of integrity
```

## Upgrade Procedures

### System Updates

```bash
# Safe upgrade procedure

# 1. Update flake inputs
nix flake update

# 2. Build without switching
nixos-rebuild build

# 3. Review changes
nix diff-closures /run/current-system ./result

# 4. Test in VM first
nixos-rebuild build-vm
./result/bin/run-*-vm

# 5. Create restore point
sudo nix-env -p /nix/var/nix/profiles/before-upgrade --set /run/current-system

# 6. Apply upgrade
sudo nixos-rebuild switch

# 7. Verify services
systemctl status sops-nix
systemctl status ssh-key-manager
systemctl --failed

# 8. Rollback if needed
sudo nixos-rebuild switch --rollback
```

### Module Version Upgrades

```bash
# Upgrading SOPS-NiX or other modules

# 1. Check changelog
curl https://raw.githubusercontent.com/Mic92/sops-nix/master/CHANGELOG.md

# 2. Update flake input
nix flake lock --update-input sops-nix

# 3. Review breaking changes
git diff flake.lock

# 4. Update configuration if needed
# Adjust for any API changes

# 5. Test thoroughly
nixos-rebuild dry-build
nixos-rebuild test

# 6. Staged rollout
# Deploy to test host first
nixos-rebuild switch --flake .#test-host --target-host test-host

# 7. Monitor for issues
journalctl -f -u sops-nix

# 8. Complete rollout
for host in production-hosts; do
  nixos-rebuild switch --flake .#$host --target-host $host
  sleep 60  # Pause between hosts
done
```

## Monitoring and Alerts

### Health Checks

```nix
# monitoring.nix
{ config, pkgs, ... }:
{
  systemd.services.secrets-health-check = {
    description = "Secrets system health check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeScript "health-check" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Check SOPS service
        systemctl is-active sops-nix.service || exit 1
        
        # Verify secrets accessible
        test -d /run/secrets.d/ || exit 1
        
        # Check age key
        test -f /root/.config/sops/age/keys.txt || exit 1
        
        # Test decryption
        sops -d /etc/nixos/secrets/common/test.yaml > /dev/null || exit 1
        
        echo "Health check passed"
      '';
    };
  };

  systemd.timers.secrets-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
```

### Alert Configuration

```nix
# alerts.nix
{
  services.prometheus.alertmanager.configuration = {
    route.receiver = "team-pager";
    receivers = [{
      name = "team-pager";
      webhook_configs = [{
        url = "https://alerts.example.com/webhook";
      }];
    }];
  };

  services.prometheus.rules = [
    {
      alert = "SecretsServiceDown";
      expr = ''systemd_unit_state{name="sops-nix.service",state="active"} != 1'';
      for = "5m";
      annotations = {
        summary = "Secrets service is down";
        description = "SOPS-NiX service has been down for 5 minutes";
      };
    }
    {
      alert = "SecretRotationOverdue";
      expr = ''time() - secrets_last_rotation_timestamp > 86400 * 90'';
      annotations = {
        summary = "Secret rotation overdue";
        description = "Secrets haven't been rotated in 90 days";
      };
    }
  ];
}
```

### Logging Configuration

```nix
{
  # Enhanced logging for audit
  services.journald.extraConfig = ''
    Storage=persistent
    Compress=yes
    MaxRetentionSec=1year
  '';

  # Audit rules for secret access
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-w /run/secrets.d/ -p r -k secret_access"
    "-w /root/.config/sops/ -p rwa -k secret_modify"
  ];
}
```

## Backup and Recovery

### Backup Strategy

```bash
#!/bin/bash
# Daily backup script

BACKUP_DIR="/mnt/backup/secrets-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 1. Backup encrypted secrets
cp -r /etc/nixos/secrets/ "$BACKUP_DIR/"

# 2. Backup configuration
git -C /etc/nixos bundle create "$BACKUP_DIR/nixos-config.bundle" --all

# 3. Backup age keys (encrypted)
tar -czf - ~/.config/sops/age/ | \
  age -e -r age1backup... > "$BACKUP_DIR/age-keys.tar.gz.age"

# 4. Create manifest
cat > "$BACKUP_DIR/manifest.txt" <<EOF
Backup Date: $(date)
Hostname: $(hostname)
NixOS Version: $(nixos-version)
Secrets Count: $(find /etc/nixos/secrets -name "*.yaml" | wc -l)
Git Commit: $(git -C /etc/nixos rev-parse HEAD)
EOF

# 5. Create checksum
sha256sum "$BACKUP_DIR"/* > "$BACKUP_DIR/checksums.txt"

# 6. Sync to remote
rsync -av "$BACKUP_DIR" backup-server:/backups/

echo "Backup completed: $BACKUP_DIR"
```

### Recovery Procedures

```bash
# Disaster recovery from backup

# 1. Boot from NixOS installer
# 2. Mount filesystems
mount /dev/sda1 /mnt
mount /dev/sda2 /mnt/boot

# 3. Restore configuration
cd /mnt/etc/nixos
git clone /path/to/backup/nixos-config.bundle .

# 4. Restore age keys
age -d -i recovery-key.txt /path/to/backup/age-keys.tar.gz.age | \
  tar -xzf - -C /root/

# 5. Restore secrets
cp -r /path/to/backup/secrets/ /mnt/etc/nixos/

# 6. Rebuild system
nixos-install --flake /mnt/etc/nixos#hostname

# 7. Verify after reboot
nixos-rebuild dry-build
systemctl status sops-nix
```

## Operational Checklists

### Daily Checklist

- [ ] Check system status dashboard
- [ ] Review overnight alerts
- [ ] Verify backup completion
- [ ] Check failed systemd services
- [ ] Review security logs for anomalies
- [ ] Test random secret accessibility
- [ ] Update documentation for any changes

### Weekly Checklist

- [ ] Review user access changes
- [ ] Audit secret access logs
- [ ] Test backup restoration (random file)
- [ ] Check for available system updates
- [ ] Review and approve pending PRs
- [ ] Update rotation schedule if needed
- [ ] Performance metrics review

### Monthly Checklist

- [ ] Rotate service passwords
- [ ] Full backup verification
- [ ] Security audit of all secrets
- [ ] Review and update documentation
- [ ] Test disaster recovery procedure
- [ ] Update team on any process changes
- [ ] Capacity planning review

### Quarterly Checklist

- [ ] Comprehensive security audit
- [ ] Key rotation (90-day keys)
- [ ] Review and update access policies
- [ ] DR drill with full recovery
- [ ] Infrastructure review and planning
- [ ] Team training on new features
- [ ] Compliance reporting

## Quick Reference

### Emergency Contacts

```yaml
On-Call Rotation:
  Primary: +1-555-0100
  Secondary: +1-555-0101
  Manager: +1-555-0102

Escalation:
  L1: Sysadmin Team
  L2: Security Team
  L3: Infrastructure Director

External Support:
  NixOS Consulting: support@nixos-consulting.com
  Security Firm: incident@security-firm.com
```

### Common Paths

```yaml
Secrets:
  Runtime: /run/secrets.d/
  Source: /etc/nixos/secrets/
  Age Keys: ~/.config/sops/age/keys.txt
  System Age: /root/.config/sops/age/keys.txt

Configurations:
  Main: /etc/nixos/configuration.nix
  Flake: /etc/nixos/flake.nix
  Modules: /etc/nixos/modules/

Logs:
  System: /var/log/messages
  Journal: journalctl
  Audit: /var/log/audit/audit.log
  Secrets: /var/log/secrets-audit.log

Backups:
  Local: /var/backup/secrets/
  Remote: backup-server:/backups/
  Archives: /mnt/backup/archives/
```

### Essential Commands

```bash
# Status checks
systemctl status sops-nix
journalctl -u sops-nix -n 50

# Secret management
sops secrets/common/services.yaml
sops updatekeys secrets/common/services.yaml
sudo ls -la /run/secrets.d/

# Deployment
nixos-rebuild dry-build
sudo nixos-rebuild switch
sudo nixos-rebuild boot

# Recovery
sudo nixos-rebuild switch --rollback
nix-store --verify --check-contents
nix-collect-garbage -d

# Monitoring
systemctl --failed
ausearch -f /run/secrets.d/
journalctl -p err -S today
```

## Best Practices Summary

1. **Always test changes in dry-build first**
2. **Maintain audit logs of all secret access**
3. **Rotate keys on schedule, not just on compromise**
4. **Keep backups encrypted and test restoration regularly**
5. **Document all changes and incidents**
6. **Use principle of least privilege for access control**
7. **Monitor continuously and alert on anomalies**
8. **Maintain an up-to-date runbook for emergencies**
9. **Train team members on procedures regularly**
10. **Review and update security policies quarterly**

Remember: Security is not a state, it's a process. Stay vigilant and keep improving.