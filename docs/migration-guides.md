# Migration Guides

## Overview

This guide provides step-by-step instructions for migrating from various secret management systems to the NixOS SOPS-NiX based solution. Each migration path includes assessment, planning, execution, and validation phases.

## Table of Contents

1. [From Plain Text Secrets](#from-plain-text-secrets)
2. [From Ansible Vault](#from-ansible-vault)
3. [From HashiCorp Vault](#from-hashicorp-vault)
4. [From Kubernetes Secrets](#from-kubernetes-secrets)
5. [From Environment Variables](#from-environment-variables)
6. [From AWS Secrets Manager](#from-aws-secrets-manager)
7. [From Azure Key Vault](#from-azure-key-vault)
8. [General Migration Best Practices](#general-migration-best-practices)

## From Plain Text Secrets

### Assessment Phase

```bash
# Find all plaintext secrets in your repository
echo "=== Searching for potential secrets ==="

# Common patterns
grep -r -E "(password|secret|token|key|api).*=.*['\"]" . \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=result \
  --exclude="*.md" | head -20

# Configuration files with secrets
find . -type f \( \
  -name "*.conf" -o \
  -name "*.config" -o \
  -name "*.ini" -o \
  -name "*.env" -o \
  -name "*.properties" \
\) -exec grep -l "password\|secret\|token" {} \;

# Count total secrets to migrate
TOTAL_SECRETS=$(grep -r -E "(password|secret|token|key).*=" . \
  --exclude-dir=.git | wc -l)
echo "Total potential secrets found: $TOTAL_SECRETS"
```

### Migration Strategy

#### Step 1: Set Up SOPS-NiX Infrastructure

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { self, nixpkgs, sops-nix }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };
  };
}
```

#### Step 2: Generate Encryption Keys

```bash
# Generate age key for the host
sudo mkdir -p /var/lib/sops/age
sudo age-keygen -o /var/lib/sops/age/keys.txt
sudo chmod 600 /var/lib/sops/age/keys.txt

# Generate user age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Get public keys for .sops.yaml
HOST_KEY=$(sudo age-keygen -y /var/lib/sops/age/keys.txt)
USER_KEY=$(age-keygen -y ~/.config/sops/age/keys.txt)

echo "Host public key: $HOST_KEY"
echo "User public key: $USER_KEY"
```

#### Step 3: Create SOPS Configuration

```yaml
# .sops.yaml
creation_rules:
  - path_regex: secrets/[^/]+\.yaml$
    key_groups:
      - age:
          - age1host_public_key_here  # Host key
          - age1user_public_key_here  # User key
```

#### Step 4: Migrate Secrets

```bash
#!/usr/bin/env bash
# migrate-plaintext-secrets.sh

# Create secrets directory
mkdir -p secrets

# Create initial secrets file
cat > secrets/services.yaml << 'EOF'
# Example structure - replace with your secrets
database:
  password: "PLACEHOLDER"
nginx:
  ssl_cert: |
    PLACEHOLDER
  ssl_key: |
    PLACEHOLDER
services:
  api_key: "PLACEHOLDER"
EOF

# Encrypt the file
sops -e -i secrets/services.yaml

# Now edit with actual values
sops secrets/services.yaml
```

#### Step 5: Update Nix Configuration

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  # Configure SOPS
  sops = {
    defaultSopsFile = ./secrets/services.yaml;
    age.keyFile = "/var/lib/sops/age/keys.txt";
    
    secrets = {
      "database/password" = {
        owner = "postgresql";
        group = "postgresql";
      };
      
      "nginx/ssl_cert" = {
        owner = "nginx";
        path = "/var/lib/nginx/ssl/cert.pem";
      };
      
      "nginx/ssl_key" = {
        owner = "nginx";
        mode = "0400";
        path = "/var/lib/nginx/ssl/key.pem";
      };
      
      "services/api_key" = {};
    };
  };
  
  # Update services to use secrets
  services.postgresql = {
    enable = true;
    # Password now comes from /run/secrets/database/password
  };
  
  services.nginx = {
    enable = true;
    virtualHosts."example.com" = {
      forceSSL = true;
      sslCertificate = config.sops.secrets."nginx/ssl_cert".path;
      sslCertificateKey = config.sops.secrets."nginx/ssl_key".path;
    };
  };
}
```

#### Step 6: Clean Up Plain Text Secrets

```bash
# Create cleanup script
cat > cleanup-plaintext.sh << 'EOF'
#!/usr/bin/env bash

echo "WARNING: This will remove plaintext secrets from git history"
echo "Make sure you have migrated all secrets to SOPS first!"
read -p "Continue? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

# Files to remove from history
FILES_TO_CLEAN=(
  "config/database.conf"
  "secrets.txt"
  ".env"
  # Add your files here
)

# Remove files from git history
for file in "${FILES_TO_CLEAN[@]}"; do
  if git ls-files --error-unmatch "$file" 2>/dev/null; then
    git filter-branch --force --index-filter \
      "git rm --cached --ignore-unmatch $file" \
      --prune-empty --tag-name-filter cat -- --all
  fi
done

# Force push to remote (dangerous!)
echo "Run 'git push --force --all' to update remote"
EOF

chmod +x cleanup-plaintext.sh
```

### Validation

```bash
# Verify no plaintext secrets remain
git grep -E "(password|secret|token|key).*=.*['\"]" || echo "No plaintext secrets found"

# Test secret decryption
sops -d secrets/services.yaml > /dev/null && echo "Decryption successful"

# Verify services can access secrets
sudo systemctl restart postgresql nginx
sudo systemctl status postgresql nginx
```

## From Ansible Vault

### Assessment Phase

```bash
# Find all Ansible vault files
find . -type f -name "*.vault" -o -name "vault.yml" -o -name "*vault*.yml"

# List vault-encrypted files
find . -type f -exec grep -l "^\$ANSIBLE_VAULT" {} \;

# Check ansible.cfg for vault settings
grep -A5 "\[defaults\]" ansible.cfg | grep vault
```

### Migration Strategy

#### Step 1: Export from Ansible Vault

```bash
#!/usr/bin/env bash
# export-ansible-vault.sh

VAULT_PASS_FILE="/path/to/vault-password-file"
EXPORT_DIR="./exported-secrets"

mkdir -p "$EXPORT_DIR"

# Export all vault files
for vault_file in $(find . -type f -exec grep -l "^\$ANSIBLE_VAULT" {} \;); do
  output_file="$EXPORT_DIR/$(basename $vault_file .yml).json"
  
  echo "Decrypting $vault_file to $output_file"
  ansible-vault decrypt --vault-password-file="$VAULT_PASS_FILE" \
    --output="$output_file" "$vault_file"
  
  # Convert YAML to JSON if needed
  if [[ $vault_file == *.yml ]] || [[ $vault_file == *.yaml ]]; then
    yq eval -o=json "$output_file" > "$output_file.tmp"
    mv "$output_file.tmp" "$output_file"
  fi
done
```

#### Step 2: Transform to SOPS Format

```python
#!/usr/bin/env python3
# transform-ansible-secrets.py

import json
import yaml
import os
from pathlib import Path

def transform_ansible_to_sops(input_dir, output_file):
    """Transform Ansible vault exports to SOPS format"""
    
    secrets = {}
    
    for json_file in Path(input_dir).glob("*.json"):
        with open(json_file) as f:
            data = json.load(f)
            
        # Extract service name from filename
        service = json_file.stem
        
        # Transform structure
        if isinstance(data, dict):
            secrets[service] = data
        else:
            secrets[service] = {"value": data}
    
    # Write YAML for SOPS
    with open(output_file, 'w') as f:
        yaml.dump(secrets, f, default_flow_style=False)
    
    print(f"Created {output_file} with {len(secrets)} service sections")

if __name__ == "__main__":
    transform_ansible_to_sops("./exported-secrets", "./secrets/migrated.yaml")
```

#### Step 3: Encrypt with SOPS

```bash
# Encrypt the migrated secrets
sops -e -i secrets/migrated.yaml

# Verify encryption
sops -d secrets/migrated.yaml | head -20
```

#### Step 4: Update Nix Configuration

```nix
# configuration.nix
{ config, lib, pkgs, ... }:
let
  # Map Ansible variables to Nix secrets
  ansibleCompat = {
    # Database settings (was in group_vars/database/vault.yml)
    "database_password" = config.sops.secrets."database/password".path;
    "database_root_password" = config.sops.secrets."database/root_password".path;
    
    # Web server (was in host_vars/webserver/vault.yml)  
    "ssl_private_key" = config.sops.secrets."webserver/ssl_key".path;
    "ssl_certificate" = config.sops.secrets."webserver/ssl_cert".path;
  };
in
{
  sops = {
    defaultSopsFile = ./secrets/migrated.yaml;
    age.keyFile = "/var/lib/sops/age/keys.txt";
    
    # Create secrets matching Ansible structure
    secrets = {
      "database/password" = {
        owner = config.services.postgresql.user;
      };
      "database/root_password" = {
        owner = "root";
        mode = "0400";
      };
      "webserver/ssl_key" = {
        owner = config.services.nginx.user;
        mode = "0400";
      };
      "webserver/ssl_cert" = {
        owner = config.services.nginx.user;
      };
    };
  };
}
```

### Validation

```bash
# Compare secret counts
echo "Ansible vault secrets:"
ansible-vault view inventory/group_vars/all/vault.yml | grep -c ":"

echo "SOPS secrets:"
sops -d secrets/migrated.yaml | grep -c ":"

# Test service functionality
sudo nixos-rebuild test
```

## From HashiCorp Vault

### Assessment Phase

```bash
# Export Vault configuration
vault auth list
vault secrets list
vault policy list

# Count total secrets
for mount in $(vault secrets list -format=json | jq -r 'keys[]'); do
  echo "Mount: $mount"
  vault kv list -format=json "$mount" 2>/dev/null | jq length
done
```

### Migration Strategy

#### Step 1: Export from HashiCorp Vault

```bash
#!/usr/bin/env bash
# export-hashicorp-vault.sh

VAULT_ADDR="https://vault.example.com:8200"
VAULT_TOKEN="s.xxxxxxxxxxxxx"
EXPORT_DIR="./vault-export"

mkdir -p "$EXPORT_DIR"

# Export KV v2 secrets
export_kv_secrets() {
  local mount=$1
  local path=$2
  
  # List all secrets recursively
  vault kv list -format=json "$mount/$path" 2>/dev/null | jq -r '.[]' | while read secret; do
    if [[ $secret == */ ]]; then
      # Recursively export directories
      export_kv_secrets "$mount" "$path$secret"
    else
      # Export individual secret
      output_path="$EXPORT_DIR/$mount/$path$secret.json"
      mkdir -p "$(dirname "$output_path")"
      
      echo "Exporting $mount/$path$secret"
      vault kv get -format=json "$mount/$path$secret" > "$output_path"
    fi
  done
}

# Export all KV v2 mounts
for mount in $(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type=="kv-v2") | .key'); do
  mount=${mount%/}  # Remove trailing slash
  echo "Exporting mount: $mount"
  export_kv_secrets "$mount" ""
done
```

#### Step 2: Transform Vault Structure

```python
#!/usr/bin/env python3
# transform-vault-secrets.py

import json
import yaml
from pathlib import Path
import re

def transform_vault_to_sops(export_dir, output_file):
    """Transform Vault exports to SOPS structure"""
    
    secrets = {}
    
    for json_file in Path(export_dir).rglob("*.json"):
        with open(json_file) as f:
            vault_data = json.load(f)
        
        # Extract actual secret data
        if "data" in vault_data and "data" in vault_data["data"]:
            secret_data = vault_data["data"]["data"]
        else:
            continue
        
        # Build path structure
        rel_path = json_file.relative_to(export_dir)
        path_parts = str(rel_path).replace(".json", "").split("/")
        
        # Create nested structure
        current = secrets
        for part in path_parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Add secret data
        current[path_parts[-1]] = secret_data
    
    # Write YAML
    with open(output_file, 'w') as f:
        yaml.dump(secrets, f, default_flow_style=False)
    
    print(f"Transformed {len(list(Path(export_dir).rglob('*.json')))} secrets")

if __name__ == "__main__":
    transform_vault_to_sops("./vault-export", "./secrets/from-vault.yaml")
```

#### Step 3: Create Transition Module

```nix
# vault-compat.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.vaultCompat;
  
  # Vault path to SOPS path mapping
  vaultPathMap = {
    "secret/database/prod" = "database/prod";
    "secret/web/ssl" = "web/ssl";
    "kv/app/config" = "app/config";
  };
  
  # Helper to get SOPS path from Vault path
  getSopsPath = vaultPath:
    vaultPathMap.${vaultPath} or (lib.replaceStrings ["/"] ["."] vaultPath);
in
{
  options.vaultCompat = {
    enable = lib.mkEnableOption "HashiCorp Vault compatibility layer";
    
    secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "Vault-style secret definitions";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Map Vault secrets to SOPS
    sops.secrets = lib.mapAttrs' (name: value:
      lib.nameValuePair (getSopsPath name) {
        inherit (value) owner group mode;
        format = "yaml";
        sopsFile = ./secrets/from-vault.yaml;
        key = getSopsPath name;
      }
    ) cfg.secrets;
    
    # Compatibility environment variables
    environment.systemPackages = [
      (pkgs.writeScriptBin "vault-compat" ''
        #!${pkgs.bash}/bin/bash
        # Vault CLI compatibility wrapper
        case "$1" in
          read)
            sops -d ${config.sops.defaultSopsFile} | \
              yq eval ".${getSopsPath "$2"}" -
            ;;
          *)
            echo "Vault has been migrated to SOPS"
            echo "Use: sops ${config.sops.defaultSopsFile}"
            ;;
        esac
      '')
    ];
  };
}
```

### Validation

```bash
# Verify secret migration
echo "Vault secret count:"
vault list -format=json secret/ | jq length

echo "SOPS secret count:"
sops -d secrets/from-vault.yaml | yq eval '.. | select(. == "*") | path | join("/")' | wc -l

# Test compatibility wrapper
vault-compat read secret/database/prod
```

## From Kubernetes Secrets

### Assessment Phase

```bash
# List all secrets in cluster
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' | \
  sort

# Export secret types
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[].type' | \
  sort -u

# Count secrets by namespace
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[].metadata.namespace' | \
  sort | uniq -c
```

### Migration Strategy  

#### Step 1: Export Kubernetes Secrets

```bash
#!/usr/bin/env bash
# export-k8s-secrets.sh

EXPORT_DIR="./k8s-secrets-export"
NAMESPACES=$(kubectl get namespaces -o json | jq -r '.items[].metadata.name')

mkdir -p "$EXPORT_DIR"

for ns in $NAMESPACES; do
  echo "Exporting secrets from namespace: $ns"
  mkdir -p "$EXPORT_DIR/$ns"
  
  kubectl get secrets -n "$ns" -o json | \
    jq -r '.items[] | @base64' | \
    while read secret_b64; do
      secret=$(echo "$secret_b64" | base64 -d)
      name=$(echo "$secret" | jq -r '.metadata.name')
      
      # Skip service account tokens
      if [[ $(echo "$secret" | jq -r '.type') == "kubernetes.io/service-account-token" ]]; then
        continue
      fi
      
      # Decode secret data
      echo "$secret" | jq '.data | map_values(@base64d)' > "$EXPORT_DIR/$ns/$name.json"
    done
done
```

#### Step 2: Transform K8s Secrets

```python
#!/usr/bin/env python3
# transform-k8s-secrets.py

import json
import yaml
import base64
from pathlib import Path

def transform_k8s_to_sops(export_dir, output_file):
    """Transform K8s secrets to SOPS format"""
    
    secrets = {}
    
    for ns_dir in Path(export_dir).iterdir():
        if not ns_dir.is_dir():
            continue
            
        namespace = ns_dir.name
        secrets[namespace] = {}
        
        for secret_file in ns_dir.glob("*.json"):
            with open(secret_file) as f:
                secret_data = json.load(f)
            
            secret_name = secret_file.stem
            
            # Handle different secret types
            if "tls.crt" in secret_data and "tls.key" in secret_data:
                # TLS secrets
                secrets[namespace][f"{secret_name}-tls"] = {
                    "cert": secret_data["tls.crt"],
                    "key": secret_data["tls.key"]
                }
            elif ".dockerconfigjson" in secret_data:
                # Docker registry secrets
                secrets[namespace][f"{secret_name}-docker"] = {
                    "config": secret_data[".dockerconfigjson"]
                }
            else:
                # Generic secrets
                secrets[namespace][secret_name] = secret_data
    
    # Write YAML
    with open(output_file, 'w') as f:
        yaml.dump(secrets, f, default_flow_style=False)
    
    print(f"Transformed secrets from {len(secrets)} namespaces")

if __name__ == "__main__":
    transform_k8s_to_sops("./k8s-secrets-export", "./secrets/from-k8s.yaml")
```

#### Step 3: Create NixOS Services Configuration

```nix
# k8s-migrated-services.nix
{ config, lib, pkgs, ... }:
{
  # Map K8s namespaces to NixOS services
  sops = {
    defaultSopsFile = ./secrets/from-k8s.yaml;
    age.keyFile = "/var/lib/sops/age/keys.txt";
    
    secrets = {
      # Production namespace → PostgreSQL
      "production/postgres-credentials/username" = {
        owner = "postgresql";
      };
      "production/postgres-credentials/password" = {
        owner = "postgresql";
        mode = "0400";
      };
      
      # Ingress namespace → Nginx
      "ingress-nginx/wildcard-cert-tls/cert" = {
        owner = "nginx";
        path = "/var/lib/nginx/certs/wildcard.crt";
      };
      "ingress-nginx/wildcard-cert-tls/key" = {
        owner = "nginx";
        mode = "0400";
        path = "/var/lib/nginx/certs/wildcard.key";
      };
      
      # Monitoring namespace → Prometheus
      "monitoring/grafana-admin/password" = {
        owner = "grafana";
      };
    };
  };
  
  # Configure services with migrated secrets
  services.postgresql = {
    enable = true;
    # Use secrets at /run/secrets/production/postgres-credentials/*
  };
  
  services.nginx = {
    enable = true;
    virtualHosts."*.example.com" = {
      forceSSL = true;
      sslCertificate = config.sops.secrets."ingress-nginx/wildcard-cert-tls/cert".path;
      sslCertificateKey = config.sops.secrets."ingress-nginx/wildcard-cert-tls/key".path;
    };
  };
}
```

### Validation

```bash
# Compare secret counts
echo "K8s secrets:"
kubectl get secrets --all-namespaces --no-headers | wc -l

echo "Migrated secrets:"
sops -d secrets/from-k8s.yaml | yq eval '... comments=""' | grep -c "^[^ ]"

# Verify service functionality
sudo nixos-rebuild test
```

## From Environment Variables

### Assessment Phase

```bash
# Find .env files
find . -name ".env*" -type f

# Check systemd services for environment files
grep -r "EnvironmentFile=" /etc/systemd/system/

# Check current environment
env | grep -E "(PASSWORD|SECRET|TOKEN|KEY|API)" | wc -l

# Docker compose files with env vars
find . -name "docker-compose*.yml" -exec grep -l "environment:" {} \;
```

### Migration Strategy

#### Step 1: Collect Environment Variables

```bash
#!/usr/bin/env bash
# collect-env-vars.sh

ENVS_DIR="./collected-envs"
mkdir -p "$ENVS_DIR"

# Collect from .env files
for env_file in $(find . -name ".env*" -type f); do
  service=$(basename $(dirname "$env_file"))
  cp "$env_file" "$ENVS_DIR/${service}.env"
done

# Extract from docker-compose
for compose_file in $(find . -name "docker-compose*.yml"); do
  service=$(basename $(dirname "$compose_file"))
  
  yq eval '.services | to_entries | .[] | .value.environment // {}' "$compose_file" | \
    grep -v "^---$" > "$ENVS_DIR/${service}-compose.env"
done

# Extract from systemd
for service_file in /etc/systemd/system/*.service; do
  if grep -q "EnvironmentFile=" "$service_file"; then
    service=$(basename "$service_file" .service)
    env_file=$(grep "EnvironmentFile=" "$service_file" | cut -d= -f2)
    
    if [[ -f "$env_file" ]]; then
      cp "$env_file" "$ENVS_DIR/${service}-systemd.env"
    fi
  fi
done
```

#### Step 2: Convert to SOPS Format

```python
#!/usr/bin/env python3
# convert-env-to-sops.py

import os
import yaml
from pathlib import Path
from dotenv import dotenv_values

def parse_env_file(env_file):
    """Parse .env file handling various formats"""
    
    # Try python-dotenv first
    try:
        return dotenv_values(env_file)
    except:
        pass
    
    # Manual parsing for complex cases
    env_vars = {}
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes
                    value = value.strip('"').strip("'")
                    env_vars[key] = value
    
    return env_vars

def convert_envs_to_sops(envs_dir, output_file):
    """Convert environment files to SOPS format"""
    
    secrets = {}
    
    for env_file in Path(envs_dir).glob("*.env"):
        service = env_file.stem.replace('-systemd', '').replace('-compose', '')
        
        env_vars = parse_env_file(env_file)
        
        if env_vars:
            if service not in secrets:
                secrets[service] = {}
            
            # Group by category
            for key, value in env_vars.items():
                if 'DATABASE' in key or 'DB_' in key or 'POSTGRES' in key or 'MYSQL' in key:
                    if 'database' not in secrets[service]:
                        secrets[service]['database'] = {}
                    secrets[service]['database'][key.lower()] = value
                elif 'AWS_' in key or 'S3_' in key:
                    if 'aws' not in secrets[service]:
                        secrets[service]['aws'] = {}
                    secrets[service]['aws'][key.lower()] = value
                elif 'SMTP' in key or 'MAIL' in key or 'EMAIL' in key:
                    if 'mail' not in secrets[service]:
                        secrets[service]['mail'] = {}
                    secrets[service]['mail'][key.lower()] = value
                else:
                    secrets[service][key.lower()] = value
    
    # Write YAML
    with open(output_file, 'w') as f:
        yaml.dump(secrets, f, default_flow_style=False)
    
    print(f"Converted {len(secrets)} services' environment variables")

if __name__ == "__main__":
    convert_envs_to_sops("./collected-envs", "./secrets/from-env.yaml")
```

#### Step 3: Create NixOS Module

```nix
# env-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.envSecrets;
  
  # Helper to create environment file from secrets
  mkEnvFile = service: secrets:
    pkgs.writeText "${service}.env" (
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: 
          "${lib.toUpper name}=${value}"
        ) secrets
      )
    );
in
{
  options.envSecrets = {
    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      description = "Environment variables for services";
    };
  };
  
  config = {
    # Create SOPS secrets for all env vars
    sops.secrets = lib.flatten (
      lib.mapAttrsToList (service: envs:
        lib.mapAttrsToList (name: value:
          lib.nameValuePair "${service}/env/${name}" {
            sopsFile = ./secrets/from-env.yaml;
            key = "${service}.${name}";
          }
        ) envs
      ) cfg.services
    );
    
    # Create systemd environment files
    systemd.services = lib.mapAttrs (service: envs: {
      serviceConfig.EnvironmentFile = [
        (mkEnvFile service envs)
      ];
    }) cfg.services;
  };
}
```

#### Step 4: Update Service Configurations

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  imports = [ ./env-secrets.nix ];
  
  # Define which services need env vars
  envSecrets.services = {
    webapp = {
      database_url = config.sops.secrets."webapp/env/database_url".path;
      redis_url = config.sops.secrets."webapp/env/redis_url".path;
      secret_key_base = config.sops.secrets."webapp/env/secret_key_base".path;
    };
    
    worker = {
      queue_url = config.sops.secrets."worker/env/queue_url".path;
      aws_access_key_id = config.sops.secrets."worker/env/aws_access_key_id".path;
      aws_secret_access_key = config.sops.secrets."worker/env/aws_secret_access_key".path;
    };
  };
  
  # Services automatically get environment files
  systemd.services.webapp = {
    # EnvironmentFile automatically created
    script = ''
      exec ${pkgs.webapp}/bin/webapp
    '';
  };
}
```

### Validation

```bash
# Check all env vars migrated
echo "Original env vars:"
cat collected-envs/*.env | grep -c "="

echo "Migrated secrets:"
sops -d secrets/from-env.yaml | grep -c ":"

# Verify service has access
sudo systemctl show webapp -p Environment
```

## From AWS Secrets Manager

### Migration Strategy

```bash
#!/usr/bin/env bash
# migrate-from-aws-secrets.sh

# Export all secrets
aws secretsmanager list-secrets --query 'SecretList[].Name' --output text | \
while read secret_name; do
  echo "Exporting $secret_name"
  
  aws secretsmanager get-secret-value \
    --secret-id "$secret_name" \
    --query 'SecretString' \
    --output text > "aws-secrets/${secret_name}.json"
done

# Transform to SOPS
for secret_file in aws-secrets/*.json; do
  secret_name=$(basename "$secret_file" .json)
  
  # Create SOPS structure
  jq --arg name "$secret_name" '{($name): .}' "$secret_file"
done | jq -s 'add' > secrets/from-aws.yaml

# Encrypt with SOPS
sops -e -i secrets/from-aws.yaml
```

## From Azure Key Vault

### Migration Strategy

```bash
#!/usr/bin/env bash
# migrate-from-azure.sh

KEYVAULT_NAME="mykeyvault"

# List all secrets
az keyvault secret list --vault-name "$KEYVAULT_NAME" \
  --query "[].name" -o tsv | \
while read secret_name; do
  echo "Exporting $secret_name"
  
  # Get secret value
  az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "$secret_name" \
    --query "value" -o tsv > "azure-secrets/${secret_name}.txt"
done

# Create SOPS structure
echo "---" > secrets/from-azure.yaml
for secret_file in azure-secrets/*.txt; do
  secret_name=$(basename "$secret_file" .txt)
  secret_value=$(cat "$secret_file")
  
  echo "${secret_name}: |" >> secrets/from-azure.yaml
  echo "  ${secret_value}" >> secrets/from-azure.yaml
done

# Encrypt
sops -e -i secrets/from-azure.yaml
```

## General Migration Best Practices

### 1. Planning Phase

```bash
#!/usr/bin/env bash
# migration-assessment.sh

echo "=== Secret Migration Assessment ==="

# Inventory current secrets
echo "Current secret storage:"
echo -n "Plain text files: "
find . -type f \( -name "*.conf" -o -name "*.env" \) | wc -l

echo -n "Encrypted files: "
find . -type f -name "*.gpg" -o -name "*.enc" | wc -l

echo -n "Vault entries: "
vault list -format=json secret/ 2>/dev/null | jq length || echo "0"

# Estimate migration effort
TOTAL_SECRETS=$(find . -type f -exec grep -l "password\|secret\|key" {} \; | wc -l)
echo "Estimated secrets to migrate: $TOTAL_SECRETS"
echo "Estimated time: $(( TOTAL_SECRETS * 5 )) minutes"

# Check dependencies
echo -e "\nDependency check:"
for tool in sops age nix; do
  if command -v $tool &> /dev/null; then
    echo "✓ $tool installed"
  else
    echo "✗ $tool missing"
  fi
done
```

### 2. Staging Migration

```nix
# staging-migration.nix
{ config, lib, pkgs, ... }:
{
  # Run old and new systems in parallel during migration
  services.migration = {
    enable = true;
    
    # Keep old system running
    oldSystem = {
      enable = true;
      configPath = "/etc/old-system";
    };
    
    # New SOPS-based system
    newSystem = {
      enable = true;
      testMode = true;  # Don't affect production
    };
    
    # Validation checks
    validators = [
      {
        name = "secret-parity";
        script = ''
          OLD_COUNT=$(find /etc/old-system -name "*.secret" | wc -l)
          NEW_COUNT=$(find /run/secrets -type f | wc -l)
          
          if [[ $OLD_COUNT -ne $NEW_COUNT ]]; then
            echo "Secret count mismatch: old=$OLD_COUNT new=$NEW_COUNT"
            exit 1
          fi
        '';
      }
    ];
  };
}
```

### 3. Rollback Plan

```bash
#!/usr/bin/env bash
# rollback-migration.sh

echo "=== Migration Rollback ==="

# Backup current state
tar czf backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  /var/lib/sops \
  /run/secrets \
  secrets/

# Restore previous configuration
git checkout HEAD~1 configuration.nix

# Rebuild without SOPS
nixos-rebuild switch --rollback

# Verify services running
systemctl status postgresql nginx
```

### 4. Validation Checklist

```bash
#!/usr/bin/env bash
# validate-migration.sh

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
  if eval "$2"; then
    echo "✓ $1"
    ((CHECKS_PASSED++))
  else
    echo "✗ $1"
    ((CHECKS_FAILED++))
  fi
}

echo "=== Migration Validation ==="

# Check secrets are encrypted
check "Secrets encrypted" "sops -d secrets/*.yaml > /dev/null 2>&1"

# Check no plaintext secrets in git
check "No plaintext in git" "! git grep -E '(password|secret|key).*=' --cached"

# Check services have access
check "PostgreSQL has database password" "test -f /run/secrets/database/password"
check "Nginx has SSL certificate" "test -f /run/secrets/nginx/ssl_cert"

# Check permissions
check "Secret permissions correct" "stat -c %a /run/secrets/* | grep -qv 777"

# Check services running
check "All services running" "systemctl is-active postgresql nginx"

echo ""
echo "Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"

exit $CHECKS_FAILED
```

### 5. Documentation Template

```markdown
# Migration Record

## Migration Details
- **Date**: YYYY-MM-DD
- **Source System**: [Ansible Vault / Kubernetes / etc.]
- **Target System**: NixOS with SOPS-NiX
- **Total Secrets Migrated**: X
- **Migration Duration**: X hours

## Pre-Migration State
- Secret storage method: 
- Number of secrets: 
- Services affected: 

## Migration Process
1. Assessment completed: ✓/✗
2. Backup created: ✓/✗
3. Secrets exported: ✓/✗
4. Secrets transformed: ✓/✗
5. SOPS encryption: ✓/✗
6. Service configuration: ✓/✗
7. Validation passed: ✓/✗

## Post-Migration Validation
- [ ] All secrets accessible
- [ ] Services functioning
- [ ] No plaintext leaks
- [ ] Audit trail working
- [ ] Rollback tested

## Lessons Learned
- 
- 
- 

## Follow-Up Actions
- [ ] Remove old secret storage
- [ ] Update documentation
- [ ] Train team on new system
- [ ] Schedule key rotation
```

## Troubleshooting Common Migration Issues

### Issue 1: Character Encoding Problems

```bash
# Fix encoding issues during migration
iconv -f ISO-8859-1 -t UTF-8 old-secrets.txt > utf8-secrets.txt

# Validate YAML after conversion
yamllint secrets/migrated.yaml
```

### Issue 2: Large Secret Files

```bash
# Split large secret files
split -b 100K large-secrets.yaml secrets-part-

# Merge in SOPS
for part in secrets-part-*; do
  sops -e "$part" > "$part.enc"
done
```

### Issue 3: Complex Secret Structures

```python
# Flatten nested structures
def flatten_dict(d, parent_key='', sep='_'):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)
```

## Summary

This migration guide provides comprehensive strategies for moving from various secret management systems to NixOS with SOPS-NiX. Key principles:

1. **Assessment First**: Understand current state before migrating
2. **Incremental Migration**: Move services gradually, not all at once
3. **Parallel Running**: Keep old system during transition
4. **Validation Critical**: Test thoroughly before decommissioning old system
5. **Documentation Essential**: Record process for future reference

The modular nature of NixOS and SOPS-NiX makes it possible to maintain compatibility layers during migration, ensuring zero-downtime transitions for critical services.