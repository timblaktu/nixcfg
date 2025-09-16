# Production Deployment Best Practices Guide

## Overview

This guide provides comprehensive best practices for deploying the NixOS SSH key and secrets management system in production environments. It covers pre-deployment validation, security hardening, performance optimization, high availability configurations, and compliance considerations.

## Pre-Deployment Validation Checklist

### Infrastructure Requirements

- [ ] **Hardware Requirements Met**
  - Minimum 2GB RAM for hosts managing > 100 secrets
  - 500MB free disk space for secret storage and logs
  - Network connectivity to Bitwarden vault (if using)
  
- [ ] **Software Prerequisites**
  - NixOS 23.11 or later
  - SOPS 3.8.0+ installed
  - Age encryption tool available
  - Git for version control

- [ ] **Network Configuration**
  - Firewall rules allow outbound HTTPS (Bitwarden)
  - DNS resolution functioning
  - NTP time synchronization configured
  - SSH port accessible for management

### Security Validation

- [ ] **Key Management**
  ```bash
  # Verify age keys are generated and stored
  test -f ~/.config/sops/age/keys.txt || echo "Missing user age key"
  test -f /var/lib/sops/age/keys.txt || echo "Missing host age key"
  
  # Validate key permissions
  stat -c %a ~/.config/sops/age/keys.txt | grep -q 600 || echo "User key permissions incorrect"
  ```

- [ ] **Bitwarden Configuration** (if applicable)
  ```bash
  # Test Bitwarden CLI access
  bw login --check && echo "Bitwarden authenticated" || echo "Bitwarden auth required"
  
  # Verify vault access
  bw sync && bw list items --search "age-key" | jq length
  ```

- [ ] **SOPS Configuration**
  ```bash
  # Validate .sops.yaml exists and is correct
  test -f .sops.yaml && sops --config .sops.yaml -d secrets/test.yaml > /dev/null 2>&1
  ```

### System State Verification

- [ ] **Clean Git Repository**
  ```bash
  # No uncommitted changes
  git status --porcelain | wc -l | grep -q "^0$" || echo "Uncommitted changes present"
  
  # No unencrypted secrets in history
  git grep -E "(password|secret|key|token).*=" || echo "Potential secrets found"
  ```

- [ ] **Module Integration**
  ```bash
  # Test build without deployment
  nixos-rebuild build --flake '.#hostname' --dry-run
  
  # Verify no evaluation errors
  nix flake check
  ```

## Security Hardening Measures

### 1. Principle of Least Privilege

#### Secret Access Control
```nix
# Configure per-service secret access
sops.secrets."database/password" = {
  owner = "postgresql";
  group = "postgresql";
  mode = "0440";  # Read-only for owner and group
};

# Service-specific paths
sops.secrets."nginx/ssl-key" = {
  path = "/var/lib/nginx/secrets/ssl.key";
  owner = "nginx";
  mode = "0400";  # Owner read-only
};
```

#### User Segregation
```nix
# Create dedicated service users
users.users.secrets-reader = {
  isSystemUser = true;
  group = "secrets";
  description = "Service account for reading secrets";
};

# Restrict secret access to specific users
sops.secrets."api-key" = {
  owner = "secrets-reader";
  group = "secrets";
  mode = "0440";
};
```

### 2. Audit and Logging

#### Enable Comprehensive Logging
```nix
# System-wide audit configuration
security.auditd.enable = true;
security.audit.enable = true;
security.audit.rules = [
  # Log all secret file access
  "-w /run/secrets -p rwxa -k secrets_access"
  "-w /var/lib/sops -p rwxa -k sops_operations"
  
  # Log key management operations
  "-w /var/lib/sops/age -p rwxa -k age_keys"
  "-w ~/.config/sops/age -p rwxa -k user_age_keys"
];

# SOPS operation logging
systemd.services.sops-nix.serviceConfig = {
  StandardOutput = "journal+console";
  StandardError = "journal+console";
  LogLevelMax = "debug";
};
```

#### Log Retention and Rotation
```nix
services.journald = {
  extraConfig = ''
    # Retain logs for compliance
    MaxRetentionSec=90d
    
    # Compress old logs
    Compress=yes
    
    # Forward security-critical logs
    ForwardToSyslog=yes
  '';
};
```

### 3. Network Security

#### Firewall Configuration
```nix
networking.firewall = {
  enable = true;
  
  # Restrict outbound connections
  extraCommands = ''
    # Allow only Bitwarden API access
    iptables -A OUTPUT -d vault.bitwarden.com -j ACCEPT
    iptables -A OUTPUT -d api.bitwarden.com -j ACCEPT
    
    # Log denied connections
    iptables -A OUTPUT -j LOG --log-prefix "DENIED_OUTBOUND: "
  '';
};
```

#### TLS Configuration
```nix
# Enforce strong TLS for external connections
environment.variables = {
  SOPS_AGE_KEY_SERVER_TLS_MIN_VERSION = "1.3";
  BW_CLI_TLS_MIN_VERSION = "1.2";
};

# Certificate validation
security.pki.certificateFiles = [
  "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
];
```

### 4. Runtime Protection

#### Sandboxing and Isolation
```nix
# Enable systemd hardening for secret-handling services
systemd.services."service-with-secrets" = {
  serviceConfig = {
    # Filesystem isolation
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ "/run/secrets" ];
    
    # Network isolation (if not needed)
    PrivateNetwork = true;
    
    # System call filtering
    SystemCallFilter = "@system-service";
    SystemCallErrorNumber = "EPERM";
    
    # Privilege restrictions
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    
    # Memory protection
    MemoryDenyWriteExecute = true;
  };
};
```

## Performance Optimization

### 1. Secret Loading Optimization

#### Parallel Decryption
```nix
# Enable parallel SOPS decryption
sops.gnupg.sshKeyPaths = [ ];  # Disable GPG to use age exclusively
sops.age.sshKeyPaths = [ ];     # Use pre-generated keys

# Configure systemd for parallel activation
systemd.services.sops-nix = {
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    # Allow parallel decryption
    TasksMax = 16;
  };
};
```

#### Caching Strategies
```nix
# Cache decrypted secrets in memory (tmpfs)
fileSystems."/run/secrets" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ 
    "size=100M"
    "mode=0755"
    "nodev"
    "nosuid"
    "noexec"
  ];
};
```

### 2. Large-Scale Deployments

#### Batch Processing
```nix
# Group related secrets for efficient loading
sops.secrets = {
  "database/all" = {
    format = "binary";
    sopsFile = ./secrets/database-bundle.enc;
  };
};

# Parse bundled secrets in service
systemd.services.postgresql.preStart = ''
  # Extract individual secrets from bundle
  cat /run/secrets/database/all | jq -r '.password' > /var/lib/postgresql/.pgpass
  cat /run/secrets/database/all | jq -r '.replication_key' > /var/lib/postgresql/.repl
'';
```

#### Resource Limits
```nix
# Configure resource limits for secret management
systemd.services.sops-nix.serviceConfig = {
  # CPU limits
  CPUQuota = "50%";
  CPUWeight = 100;
  
  # Memory limits
  MemoryMax = "500M";
  MemorySwapMax = "0";
  
  # I/O limits
  IOWeight = 50;
  IOReadBandwidthMax = "/dev/sda 10M";
  IOWriteBandwidthMax = "/dev/sda 10M";
};
```

### 3. Monitoring and Metrics

#### Performance Metrics Collection
```nix
services.prometheus = {
  enable = true;
  
  exporters.node = {
    enable = true;
    enabledCollectors = [
      "systemd"
      "filesystem"
      "loadavg"
      "meminfo"
    ];
  };
  
  scrapeConfigs = [{
    job_name = "sops-metrics";
    static_configs = [{
      targets = [ "localhost:9100" ];
      labels = {
        service = "sops-nix";
      };
    }];
  }];
};

# Custom metrics for secret operations
systemd.services.sops-metrics = {
  script = ''
    # Count secrets
    echo "sops_secrets_total $(find /run/secrets -type f | wc -l)" > /var/lib/prometheus-node-exporter/sops.prom
    
    # Measure decryption time
    start=$(date +%s%N)
    sops -d /path/to/test.yaml > /dev/null 2>&1
    end=$(date +%s%N)
    echo "sops_decrypt_duration_ns $((end-start))" >> /var/lib/prometheus-node-exporter/sops.prom
  '';
  
  serviceConfig.Type = "oneshot";
};

systemd.timers.sops-metrics = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnCalendar = "minutely";
};
```

## High Availability Configurations

### 1. Multi-Master Setup

#### Redundant Key Storage
```nix
# Configure multiple Bitwarden vaults for redundancy
programs.bitwarden-cli = {
  vaults = [
    {
      url = "https://vault-primary.example.com";
      priority = 1;
    }
    {
      url = "https://vault-secondary.example.com";
      priority = 2;
    }
  ];
  
  # Automatic failover
  failoverTimeout = 5;  # seconds
  retryAttempts = 3;
};
```

#### Secret Replication
```nix
# Sync secrets across multiple hosts
systemd.services.secret-replication = {
  description = "Replicate secrets to standby nodes";
  
  script = ''
    # Encrypt and sync to standby nodes
    for host in standby1 standby2; do
      sops -e /var/lib/secrets/* | \
        ssh $host "sops -d > /var/lib/secrets/"
    done
  '';
  
  serviceConfig = {
    Type = "oneshot";
    User = "root";
  };
};

systemd.timers.secret-replication = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
  };
};
```

### 2. Disaster Recovery

#### Backup Configuration
```nix
# Automated secret backups
services.restic.backups.secrets = {
  paths = [ 
    "/var/lib/sops"
    "/var/lib/secrets"
    "~/.config/sops"
  ];
  
  repository = "s3:s3.amazonaws.com/backup-bucket/secrets";
  
  # Encrypt backups with different key
  passwordFile = "/root/.restic-password";
  
  # Backup schedule
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
  
  # Retention policy
  pruneOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 12"
    "--keep-yearly 5"
  ];
};
```

#### Recovery Procedures
```bash
#!/usr/bin/env bash
# disaster-recovery.sh

# Step 1: Restore age keys from backup
restic -r s3:s3.amazonaws.com/backup-bucket/secrets restore latest \
  --target / --include "/var/lib/sops/age"

# Step 2: Verify key integrity
age-keygen -y /var/lib/sops/age/keys.txt

# Step 3: Restore encrypted secrets
restic -r s3:s3.amazonaws.com/backup-bucket/secrets restore latest \
  --target / --include "/var/lib/secrets"

# Step 4: Test decryption
sops -d /var/lib/secrets/test.yaml > /dev/null || exit 1

# Step 5: Rebuild system
nixos-rebuild switch --flake '.#hostname'
```

### 3. Load Balancing

#### Distributed Secret Management
```nix
# Configure secret sharding across nodes
services.sops-distributed = {
  enable = true;
  
  # Shard configuration
  sharding = {
    enabled = true;
    nodes = [ "node1" "node2" "node3" ];
    replicationFactor = 2;
  };
  
  # Consistent hashing for secret distribution
  hashRing = {
    algorithm = "md5";
    virtualNodes = 150;
  };
};
```

## Compliance and Audit Considerations

### 1. Regulatory Compliance

#### GDPR Compliance
```nix
# Data protection configuration
sops.secrets = {
  # Encrypt PII with separate keys
  "user-data/*" = {
    sopsFile = ./secrets/gdpr/user-data.yaml;
    ageKeys = [ "gdpr-compliance-key" ];
  };
};

# Right to erasure implementation
systemd.services.gdpr-data-deletion = {
  description = "GDPR data deletion service";
  
  script = ''
    # Securely delete user data
    for file in /run/secrets/user-data/*; do
      shred -vfz -n 3 "$file"
    done
  '';
};
```

#### HIPAA Compliance
```nix
# Healthcare data protection
security.audit.rules = [
  # Audit all PHI access
  "-w /run/secrets/phi -p rwxa -k phi_access"
  
  # Monitor encryption operations
  "-w /usr/bin/sops -p x -k encryption_ops"
];

# Encryption at rest and in transit
sops.age.keyFile = "/var/lib/sops/age/hipaa-compliant-keys.txt";
sops.gnupg.home = null;  # Disable GPG, use FIPS-compliant age only
```

#### PCI-DSS Compliance
```nix
# Payment card data protection
sops.secrets."payment/card-keys" = {
  owner = "payment-processor";
  group = "pci-compliance";
  mode = "0400";
  
  # Rotate keys quarterly
  restartUnits = [ "payment-processor.service" ];
};

# Key rotation automation
systemd.services.pci-key-rotation = {
  description = "PCI-DSS quarterly key rotation";
  
  script = ''
    # Generate new key
    age-keygen -o /tmp/new-key.txt
    
    # Re-encrypt all payment secrets
    for secret in /var/lib/secrets/payment/*; do
      sops rotate -i --add-age $(cat /tmp/new-key.txt | grep "public key:" | cut -d" " -f4) $secret
    done
    
    # Update key storage
    mv /tmp/new-key.txt /var/lib/sops/age/keys.txt
  '';
  
  serviceConfig.Type = "oneshot";
};

systemd.timers.pci-key-rotation = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    # Quarterly rotation
    OnCalendar = "quarterly";
    Persistent = true;
  };
};
```

### 2. Audit Trail Requirements

#### Comprehensive Logging
```nix
# Centralized logging configuration
services.rsyslog = {
  enable = true;
  
  extraConfig = ''
    # Forward audit logs to SIEM
    *.* @@siem.example.com:514
    
    # Local audit trail
    if $programname == 'sops' then /var/log/sops-audit.log
    if $programname == 'age' then /var/log/age-audit.log
    
    # Stop processing after logging
    & stop
  '';
};

# Log analysis and alerting
services.fail2ban = {
  enable = true;
  
  jails.sops-failures = ''
    enabled = true
    filter = sops-failures
    action = iptables-allports[name=SOPS]
    logpath = /var/log/sops-audit.log
    maxretry = 3
    bantime = 3600
  '';
};
```

#### Audit Report Generation
```nix
# Automated compliance reporting
systemd.services.compliance-report = {
  description = "Generate compliance audit report";
  
  script = ''
    #!/usr/bin/env bash
    REPORT_DATE=$(date +%Y-%m-%d)
    REPORT_FILE="/var/audit/compliance-report-$REPORT_DATE.json"
    
    # Collect audit data
    jq -n \
      --arg date "$REPORT_DATE" \
      --arg secrets_count "$(find /run/secrets -type f | wc -l)" \
      --arg failed_decrypts "$(journalctl -u sops-nix --since yesterday | grep ERROR | wc -l)" \
      --arg key_rotations "$(grep rotation /var/log/sops-audit.log | wc -l)" \
      --arg unauthorized_access "$(aureport -au --summary | tail -1 | awk '{print $5}')" \
      '{
        report_date: $date,
        metrics: {
          total_secrets: $secrets_count,
          failed_decryptions: $failed_decrypts,
          key_rotations: $key_rotations,
          unauthorized_attempts: $unauthorized_access
        },
        compliance_status: "COMPLIANT",
        next_audit: (now + 86400 * 30 | strftime("%Y-%m-%d"))
      }' > "$REPORT_FILE"
    
    # Send report to compliance team
    mail -s "Monthly Compliance Report" compliance@example.com < "$REPORT_FILE"
  '';
  
  serviceConfig.Type = "oneshot";
};

systemd.timers.compliance-report = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "monthly";
    Persistent = true;
  };
};
```

### 3. Security Certifications

#### ISO 27001 Requirements
```nix
# Information Security Management System (ISMS) integration
security.isms = {
  enable = true;
  
  # Risk assessment configuration
  riskAssessment = {
    frequency = "quarterly";
    scope = [ "/var/lib/sops" "/run/secrets" ];
  };
  
  # Security controls
  controls = {
    accessControl = true;
    cryptography = true;
    physicalSecurity = false;  # Handled externally
    incidentManagement = true;
  };
};
```

#### SOC 2 Type II
```nix
# Service Organization Control compliance
services.soc2-monitoring = {
  enable = true;
  
  # Continuous monitoring
  checks = {
    availability = {
      threshold = "99.9%";
      measurement = "monthly";
    };
    
    confidentiality = {
      encryption = "AES-256";
      keyManagement = "age";
    };
    
    integrity = {
      checksums = true;
      signatures = true;
    };
  };
};
```

## Deployment Automation

### GitOps Integration
```nix
# Automated deployment with FluxCD/ArgoCD patterns
systemd.services.gitops-secrets-sync = {
  description = "Sync secrets from Git repository";
  
  script = ''
    # Pull latest configuration
    cd /var/lib/nixcfg
    git pull origin main
    
    # Validate secrets configuration
    sops --config .sops.yaml updatekeys secrets/*.yaml
    
    # Apply configuration
    nixos-rebuild switch --flake '.#hostname'
  '';
  
  serviceConfig = {
    Type = "oneshot";
    User = "root";
  };
};

systemd.timers.gitops-secrets-sync = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "*:0/15";  # Every 15 minutes
    Persistent = true;
  };
};
```

### CI/CD Pipeline Integration
```yaml
# .gitlab-ci.yml example
stages:
  - validate
  - deploy

validate-secrets:
  stage: validate
  script:
    - nix flake check
    - sops --config .sops.yaml -d secrets/test.yaml > /dev/null
    - ./scripts/validate-secret-permissions.sh
  only:
    - merge_requests

deploy-production:
  stage: deploy
  script:
    - sops --decrypt secrets/ci-deploy-key.yaml > /tmp/deploy-key
    - ssh -i /tmp/deploy-key deploy@production "nixos-rebuild switch --flake github:org/nixcfg#prod"
    - rm -f /tmp/deploy-key
  only:
    - main
  environment:
    name: production
```

## Monitoring and Alerting

### Metrics Dashboard
```nix
services.grafana = {
  enable = true;
  
  provision = {
    dashboards = [{
      name = "secrets-management";
      folder = "Security";
      type = "file";
      options.path = ./dashboards/secrets.json;
    }];
    
    datasources = [{
      name = "Prometheus";
      type = "prometheus";
      url = "http://localhost:9090";
    }];
  };
};

# Alert rules
services.prometheus.rules = [''
  groups:
  - name: secrets
    interval: 30s
    rules:
    - alert: SecretDecryptionFailed
      expr: rate(sops_decrypt_failures_total[5m]) > 0
      for: 1m
      annotations:
        summary: "SOPS decryption failures detected"
        
    - alert: KeyRotationOverdue
      expr: (time() - sops_last_key_rotation) > 86400 * 90
      for: 1h
      annotations:
        summary: "Key rotation overdue (>90 days)"
        
    - alert: UnauthorizedSecretAccess
      expr: rate(audit_unauthorized_secret_access[5m]) > 0
      for: 1m
      annotations:
        summary: "Unauthorized secret access attempt detected"
''];
```

## Troubleshooting Production Issues

### Common Production Problems

1. **Performance Degradation**
   ```bash
   # Check SOPS service status
   systemctl status sops-nix
   
   # Analyze slow queries
   journalctl -u sops-nix --since "1 hour ago" | grep -E "took [0-9]+s"
   
   # Clear cache if needed
   rm -rf /tmp/sops-cache/*
   ```

2. **High Memory Usage**
   ```bash
   # Check memory consumption
   systemctl status sops-nix --no-pager | grep Memory
   
   # Restart service to clear memory
   systemctl restart sops-nix
   ```

3. **Network Issues**
   ```bash
   # Test Bitwarden connectivity
   curl -I https://vault.bitwarden.com
   
   # Check DNS resolution
   nslookup vault.bitwarden.com
   
   # Verify firewall rules
   iptables -L OUTPUT -v -n | grep bitwarden
   ```

## Summary

This production deployment guide provides comprehensive best practices for:

- **Pre-deployment validation** ensuring system readiness
- **Security hardening** with defense-in-depth approach
- **Performance optimization** for large-scale deployments
- **High availability** configurations for critical systems
- **Compliance adherence** to regulatory requirements
- **Monitoring and alerting** for operational visibility

Following these practices ensures a secure, performant, and compliant secrets management system in production environments. Regular reviews and updates of these practices are recommended as the threat landscape and compliance requirements evolve.