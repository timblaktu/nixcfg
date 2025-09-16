# Service Integration Examples

This guide provides real-world examples of integrating SOPS-NiX secrets and SSH key management with common services in NixOS.

## Table of Contents

1. [NetworkManager WiFi Passwords](#networkmanager-wifi-passwords)
2. [PostgreSQL Database Credentials](#postgresql-database-credentials)
3. [Nginx SSL Certificates](#nginx-ssl-certificates)
4. [Docker Registry Authentication](#docker-registry-authentication)
5. [API Keys for Services](#api-keys-for-services)
6. [Backup Encryption Keys](#backup-encryption-keys)
7. [VPN Configurations](#vpn-configurations)
8. [Mail Server Credentials](#mail-server-credentials)

## NetworkManager WiFi Passwords

### Storing WiFi Credentials in SOPS

```yaml
# secrets/common/wifi.yaml
wifi:
  home_network:
    ssid: "MyHomeWiFi"
    psk: "supersecretpassword123"
  office_network:
    ssid: "OfficeSecure"
    psk: "officepass456"
  mobile_hotspot:
    ssid: "MyPhone"
    psk: "phonehotspot789"
```

### NixOS Configuration

```nix
# modules/nixos/wifi-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.wifiSecrets;
in
{
  options.services.wifiSecrets = {
    enable = lib.mkEnableOption "WiFi secrets from SOPS";
    
    networks = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          ssid = lib.mkOption {
            type = lib.types.str;
            description = "Network SSID";
          };
          pskSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret path for PSK";
          };
        };
      });
      default = [];
      description = "List of WiFi networks with SOPS secrets";
    };
  };

  config = lib.mkIf cfg.enable {
    # Configure SOPS secrets
    sops.secrets = lib.listToAttrs (map (network: {
      name = "wifi/${network.ssid}/psk";
      value = {
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "NetworkManager.service" ];
      };
    }) cfg.networks);

    # NetworkManager configuration
    networking.networkmanager = {
      enable = true;
      ensureProfiles.profiles = lib.listToAttrs (map (network: {
        name = network.ssid;
        value = {
          connection = {
            id = network.ssid;
            type = "802-11-wireless";
            autoconnect = true;
          };
          "802-11-wireless" = {
            ssid = network.ssid;
            mode = "infrastructure";
          };
          "802-11-wireless-security" = {
            key-mgmt = "wpa-psk";
            psk = "@${config.sops.secrets."wifi/${network.ssid}/psk".path}@";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      }) cfg.networks);
    };
  };
}
```

### Usage Example

```nix
# hosts/laptop/default.nix
{ config, ... }:
{
  imports = [ ../../modules/nixos/wifi-secrets.nix ];

  sopsNix.defaultSopsFile = ../../secrets/common/wifi.yaml;
  
  services.wifiSecrets = {
    enable = true;
    networks = [
      { ssid = "MyHomeWiFi"; pskSecret = "wifi.home_network.psk"; }
      { ssid = "OfficeSecure"; pskSecret = "wifi.office_network.psk"; }
    ];
  };
}
```

## PostgreSQL Database Credentials

### Storing Database Secrets

```yaml
# secrets/common/databases.yaml
postgres:
  main:
    host: "db.example.com"
    port: 5432
    database: "production"
    username: "app_user"
    password: "VerySecurePassword123!"
  analytics:
    host: "analytics.example.com"
    port: 5432
    database: "analytics"
    username: "analytics_user"
    password: "AnalyticsPass456!"
```

### NixOS Module

```nix
# modules/nixos/postgres-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.postgresSecrets;
in
{
  options.services.postgresSecrets = {
    enable = lib.mkEnableOption "PostgreSQL secrets from SOPS";
    
    databases = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          secretPath = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret path for database credentials";
          };
          connectionFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to write connection string";
          };
          owner = lib.mkOption {
            type = lib.types.str;
            default = "postgres";
            description = "Owner of connection file";
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Create connection string files
    systemd.services = lib.mapAttrs' (name: db: {
      name = "postgres-secret-${name}";
      value = {
        description = "PostgreSQL connection string for ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" ];
        
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        
        script = ''
          # Read secrets
          HOST=$(cat ${config.sops.secrets."postgres/${name}/host".path})
          PORT=$(cat ${config.sops.secrets."postgres/${name}/port".path})
          DB=$(cat ${config.sops.secrets."postgres/${name}/database".path})
          USER=$(cat ${config.sops.secrets."postgres/${name}/username".path})
          PASS=$(cat ${config.sops.secrets."postgres/${name}/password".path})
          
          # Create connection string
          CONNECTION="postgresql://$USER:$PASS@$HOST:$PORT/$DB"
          
          # Write to file
          echo "$CONNECTION" > ${db.connectionFile}
          chown ${db.owner}:${db.owner} ${db.connectionFile}
          chmod 0400 ${db.connectionFile}
        '';
      };
    }) cfg.databases;
    
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: db: {
      "postgres/${name}/host" = { owner = "root"; };
      "postgres/${name}/port" = { owner = "root"; };
      "postgres/${name}/database" = { owner = "root"; };
      "postgres/${name}/username" = { owner = "root"; };
      "postgres/${name}/password" = { owner = "root"; };
    }) cfg.databases);
  };
}
```

## Nginx SSL Certificates

### Storing SSL Certificates and Keys

```yaml
# secrets/common/ssl.yaml
ssl:
  example_com:
    cert: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAKl...
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      MIIEvgIBADANBgkqhkiG9w0B...
      -----END PRIVATE KEY-----
  api_example_com:
    cert: |
      -----BEGIN CERTIFICATE-----
      MIIDYTCCAkmgAwIBAgIJBKm...
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      MIIEvwIBADANBgkqhkiG9w0C...
      -----END PRIVATE KEY-----
```

### Nginx Configuration with SSL

```nix
# modules/nixos/nginx-ssl-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nginxSSLSecrets;
in
{
  options.services.nginxSSLSecrets = {
    enable = lib.mkEnableOption "Nginx SSL from SOPS";
    
    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Domain name";
          };
          certSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret path for certificate";
          };
          keySecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret path for private key";
          };
          extraConfig = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra nginx configuration";
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: vhost: {
      "${vhost.certSecret}" = {
        owner = "nginx";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "nginx.service" ];
      };
      "${vhost.keySecret}" = {
        owner = "nginx";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "nginx.service" ];
      };
    }) cfg.virtualHosts);

    # Configure Nginx
    services.nginx = {
      enable = true;
      virtualHosts = lib.mapAttrs (name: vhost: {
        serverName = vhost.domain;
        forceSSL = true;
        sslCertificate = config.sops.secrets."${vhost.certSecret}".path;
        sslCertificateKey = config.sops.secrets."${vhost.keySecret}".path;
        extraConfig = vhost.extraConfig;
      }) cfg.virtualHosts;
    };
  };
}
```

## Docker Registry Authentication

### Storing Docker Credentials

```yaml
# secrets/common/docker.yaml
docker:
  registries:
    dockerhub:
      username: "myusername"
      password: "mypassword123"
    ghcr:
      username: "github_user"
      token: "ghp_xxxxxxxxxxxxxxxxxxxx"
    private:
      registry: "registry.company.com"
      username: "deploy_user"
      password: "deploypass456"
```

### Docker Authentication Module

```nix
# modules/nixos/docker-auth-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.dockerAuthSecrets;
in
{
  options.services.dockerAuthSecrets = {
    enable = lib.mkEnableOption "Docker registry authentication from SOPS";
    
    registries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of registry names from SOPS";
    };
    
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Users who need docker authentication";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create docker config for each user
    systemd.services = lib.listToAttrs (map (user: {
      name = "docker-auth-${user}";
      value = {
        description = "Docker authentication for ${user}";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" ];
        
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        
        script = ''
          # Create docker config directory
          DOCKER_CONFIG="/home/${user}/.docker"
          mkdir -p "$DOCKER_CONFIG"
          
          # Generate config.json
          cat > "$DOCKER_CONFIG/config.json" <<EOF
          {
            "auths": {
          EOF
          
          ${lib.concatMapStringsSep "\n" (registry: ''
            REGISTRY=$(cat ${config.sops.secrets."docker/registries/${registry}/registry".path} 2>/dev/null || echo "docker.io")
            USERNAME=$(cat ${config.sops.secrets."docker/registries/${registry}/username".path})
            PASSWORD=$(cat ${config.sops.secrets."docker/registries/${registry}/password".path})
            AUTH=$(echo -n "$USERNAME:$PASSWORD" | base64 -w0)
            
            if [ "$REGISTRY" != "$(tail -n1 $DOCKER_CONFIG/config.json | grep -o '"[^"]*"' | head -1 | tr -d '"')" ]; then
              [ -s "$DOCKER_CONFIG/config.json" ] && echo "," >> "$DOCKER_CONFIG/config.json"
            fi
            
            cat >> "$DOCKER_CONFIG/config.json" <<ENTRY
              "$REGISTRY": {
                "auth": "$AUTH"
              }
          ENTRY
          '') cfg.registries}
          
          cat >> "$DOCKER_CONFIG/config.json" <<EOF
            }
          }
          EOF
          
          # Set permissions
          chown -R ${user}:users "$DOCKER_CONFIG"
          chmod 700 "$DOCKER_CONFIG"
          chmod 600 "$DOCKER_CONFIG/config.json"
        '';
      };
    }) cfg.users);
    
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (map (registry: {
      "docker/registries/${registry}/username" = { owner = "root"; };
      "docker/registries/${registry}/password" = { owner = "root"; };
      "docker/registries/${registry}/registry" = { owner = "root"; };
    }) cfg.registries);
  };
}
```

## API Keys for Services

### Storing API Keys

```yaml
# secrets/common/api-keys.yaml
api_keys:
  github:
    token: "ghp_xxxxxxxxxxxxxxxxxxxx"
    webhook_secret: "webhook_secret_123"
  openai:
    api_key: "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
  aws:
    access_key_id: "AKIAIOSFODNN7EXAMPLE"
    secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  slack:
    bot_token: "xoxb-xxxxxxxxxxxx-xxxxxxxxxxxx"
    webhook_url: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX"
```

### API Keys Management Module

```nix
# modules/nixos/api-keys-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.apiKeysSecrets;
in
{
  options.services.apiKeysSecrets = {
    enable = lib.mkEnableOption "API keys from SOPS";
    
    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of key names for this service";
          };
          envFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to environment file";
          };
          owner = lib.mkOption {
            type = lib.types.str;
            default = "root";
            description = "Owner of env file";
          };
          systemdServices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Systemd services to restart on change";
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Create environment files
    systemd.services = lib.mapAttrs' (name: service: {
      name = "api-keys-${name}";
      value = {
        description = "API keys for ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" ];
        before = service.systemdServices;
        
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        
        script = ''
          # Create environment file
          rm -f ${service.envFile}
          touch ${service.envFile}
          
          ${lib.concatMapStringsSep "\n" (key: ''
            KEY_NAME="${lib.toUpper (lib.replaceStrings ["-"] ["_"] key)}"
            KEY_VALUE=$(cat ${config.sops.secrets."api_keys/${name}/${key}".path})
            echo "$KEY_NAME=$KEY_VALUE" >> ${service.envFile}
          '') service.keys}
          
          # Set permissions
          chown ${service.owner}:${service.owner} ${service.envFile}
          chmod 0400 ${service.envFile}
          
          # Restart dependent services
          ${lib.concatMapStringsSep "\n" (svc: ''
            systemctl restart ${svc} || true
          '') service.systemdServices}
        '';
      };
    }) cfg.services;
    
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: service:
      lib.listToAttrs (map (key: {
        name = "api_keys/${name}/${key}";
        value = { owner = "root"; };
      }) service.keys)
    ) cfg.services);
  };
}
```

## Backup Encryption Keys

### Storing Backup Passwords

```yaml
# secrets/common/backups.yaml
backups:
  restic:
    password: "MyVerySecureResticPassword123!"
    s3_access_key: "AKIAIOSFODNN7EXAMPLE"
    s3_secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  borg:
    passphrase: "MyBorgBackupPassphrase456!"
    ssh_key: |
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn...
      -----END OPENSSH PRIVATE KEY-----
```

### Restic Backup Module

```nix
# modules/nixos/restic-backup-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.resticBackupSecrets;
in
{
  options.services.resticBackupSecrets = {
    enable = lib.mkEnableOption "Restic backups with SOPS secrets";
    
    backups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Paths to backup";
          };
          repository = lib.mkOption {
            type = lib.types.str;
            description = "Restic repository URL";
          };
          passwordSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret for repository password";
          };
          s3Credentials = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                accessKeySecret = lib.mkOption {
                  type = lib.types.str;
                  description = "SOPS secret for S3 access key";
                };
                secretKeySecret = lib.mkOption {
                  type = lib.types.str;
                  description = "SOPS secret for S3 secret key";
                };
              };
            });
            default = null;
          };
          timerConfig = lib.mkOption {
            type = lib.types.attrs;
            default = { OnCalendar = "daily"; };
            description = "Systemd timer configuration";
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Configure restic backups
    services.restic.backups = lib.mapAttrs (name: backup: {
      paths = backup.paths;
      repository = backup.repository;
      passwordFile = config.sops.secrets."${backup.passwordSecret}".path;
      
      environmentFile = lib.mkIf (backup.s3Credentials != null) (
        pkgs.writeText "restic-env-${name}" ''
          AWS_ACCESS_KEY_ID=$(cat ${config.sops.secrets."${backup.s3Credentials.accessKeySecret}".path})
          AWS_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets."${backup.s3Credentials.secretKeySecret}".path})
        ''
      );
      
      timerConfig = backup.timerConfig;
      
      initialize = true;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    }) cfg.backups;
    
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: backup:
      lib.mkMerge [
        { "${backup.passwordSecret}" = { owner = "root"; }; }
        (lib.optionalAttrs (backup.s3Credentials != null) {
          "${backup.s3Credentials.accessKeySecret}" = { owner = "root"; };
          "${backup.s3Credentials.secretKeySecret}" = { owner = "root"; };
        })
      ]
    ) cfg.backups);
  };
}
```

## VPN Configurations

### Storing VPN Keys

```yaml
# secrets/common/vpn.yaml
vpn:
  wireguard:
    home:
      private_key: "kODkqNxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxE="
      preshared_key: "FjPXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxRs="
      endpoint: "vpn.example.com:51820"
      public_key: "HIgoxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8="
    office:
      private_key: "mPEkqNxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA="
      preshared_key: "GkQYxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxTs="
  openvpn:
    client_cert: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAKl...
      -----END CERTIFICATE-----
    client_key: |
      -----BEGIN PRIVATE KEY-----
      MIIEvgIBADANBgkqhkiG9w0B...
      -----END PRIVATE KEY-----
```

### WireGuard VPN Module

```nix
# modules/nixos/wireguard-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.wireguardSecrets;
in
{
  options.services.wireguardSecrets = {
    enable = lib.mkEnableOption "WireGuard VPN with SOPS secrets";
    
    interfaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ips = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "IP addresses for the interface";
          };
          privateKeySecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret for private key";
          };
          peers = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                publicKey = lib.mkOption {
                  type = lib.types.str;
                  description = "Peer public key";
                };
                presharedKeySecret = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "SOPS secret for preshared key";
                };
                endpoint = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Endpoint address";
                };
                allowedIPs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Allowed IP ranges";
                };
              };
            });
            default = [];
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    # Configure WireGuard interfaces
    networking.wireguard.interfaces = lib.mapAttrs (name: iface: {
      ips = iface.ips;
      privateKeyFile = config.sops.secrets."${iface.privateKeySecret}".path;
      
      peers = map (peer: {
        publicKey = peer.publicKey;
        presharedKeyFile = lib.mkIf (peer.presharedKeySecret != null)
          config.sops.secrets."${peer.presharedKeySecret}".path;
        endpoint = peer.endpoint;
        allowedIPs = peer.allowedIPs;
        persistentKeepalive = 25;
      }) iface.peers;
    }) cfg.interfaces;
    
    # Configure SOPS secrets
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: iface:
      lib.mkMerge ([
        { "${iface.privateKeySecret}" = { owner = "root"; }; }
      ] ++ (map (peer:
        lib.optionalAttrs (peer.presharedKeySecret != null) {
          "${peer.presharedKeySecret}" = { owner = "root"; };
        }
      ) iface.peers))
    ) cfg.interfaces);
  };
}
```

## Mail Server Credentials

### Storing Mail Credentials

```yaml
# secrets/common/mail.yaml
mail:
  smtp:
    host: "smtp.gmail.com"
    port: 587
    username: "myemail@gmail.com"
    password: "app-specific-password"
  imap:
    host: "imap.gmail.com"
    port: 993
    username: "myemail@gmail.com"
    password: "app-specific-password"
  accounts:
    noreply:
      address: "noreply@example.com"
      smtp_password: "smtp-password-123"
    alerts:
      address: "alerts@example.com"
      smtp_password: "smtp-password-456"
```

### Mail Configuration Module

```nix
# modules/nixos/mail-secrets.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.mailSecrets;
in
{
  options.services.mailSecrets = {
    enable = lib.mkEnableOption "Mail server credentials from SOPS";
    
    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          address = lib.mkOption {
            type = lib.types.str;
            description = "Email address";
          };
          smtpHost = lib.mkOption {
            type = lib.types.str;
            default = "smtp.gmail.com";
            description = "SMTP server hostname";
          };
          smtpPort = lib.mkOption {
            type = lib.types.int;
            default = 587;
            description = "SMTP server port";
          };
          passwordSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret for password";
          };
        };
      });
      default = {};
    };
    
    msmtpConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Generate msmtp configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate msmtp configuration if requested
    programs.msmtp = lib.mkIf cfg.msmtpConfig {
      enable = true;
      accounts = lib.mapAttrs (name: account: {
        host = account.smtpHost;
        port = account.smtpPort;
        from = account.address;
        user = account.address;
        passwordeval = "cat ${config.sops.secrets."${account.passwordSecret}".path}";
        tls = true;
        tls_starttls = true;
        auth = true;
      }) cfg.accounts;
      defaults = {
        aliases = "/etc/aliases";
        port = 587;
        tls = true;
      };
    };
    
    # Configure SOPS secrets
    sops.secrets = lib.mapAttrs' (name: account: {
      name = account.passwordSecret;
      value = {
        owner = config.users.users.${config.services.msmtp.user or "root"}.name or "root";
        mode = "0400";
      };
    }) cfg.accounts;
    
    # Create mail configuration files for other applications
    environment.etc = lib.mapAttrs' (name: account: {
      name = "mail/${name}.conf";
      value = {
        mode = "0400";
        user = "root";
        text = ''
          MAIL_FROM=${account.address}
          MAIL_HOST=${account.smtpHost}
          MAIL_PORT=${toString account.smtpPort}
          MAIL_USER=${account.address}
          MAIL_PASSWORD_FILE=${config.sops.secrets."${account.passwordSecret}".path}
        '';
      };
    }) cfg.accounts;
  };
}
```

## Common Patterns and Best Practices

### 1. Secret Rotation

```nix
# Automatic secret rotation helper
systemd.services.rotate-secrets = {
  description = "Rotate secrets monthly";
  serviceConfig.Type = "oneshot";
  script = ''
    # Trigger re-encryption with new timestamps
    sops updatekeys /etc/nixos/secrets/common/*.yaml
    
    # Rebuild system to apply new secrets
    nixos-rebuild switch
  '';
};

systemd.timers.rotate-secrets = {
  wantedBy = [ "timers.target" ];
  partOf = [ "rotate-secrets.service" ];
  timerConfig.OnCalendar = "monthly";
};
```

### 2. Multi-Host Secret Sharing

```nix
# Share secrets across multiple hosts
{
  sops.secrets."shared/database" = {
    sopsFile = ../../secrets/shared/database.yaml;
    owner = "postgres";
    group = "postgres";
    mode = "0440";
    # Available on all hosts in the cluster
  };
}
```

### 3. Environment-Specific Secrets

```nix
# Use different secrets for dev/staging/prod
{
  sopsNix.defaultSopsFile = 
    if config.networking.hostName == "prod-server" then
      ../../secrets/production/secrets.yaml
    else if config.networking.hostName == "staging-server" then
      ../../secrets/staging/secrets.yaml
    else
      ../../secrets/development/secrets.yaml;
}
```

### 4. Secret Validation

```nix
# Validate secrets before use
systemd.services.validate-secrets = {
  description = "Validate secret formats";
  after = [ "sops-nix.service" ];
  script = ''
    # Check database connection string format
    DB_URL=$(cat ${config.sops.secrets."database/url".path})
    if ! echo "$DB_URL" | grep -qE '^postgresql://'; then
      echo "ERROR: Invalid database URL format"
      exit 1
    fi
    
    # Verify API key length
    API_KEY=$(cat ${config.sops.secrets."api/key".path})
    if [ ''${#API_KEY} -lt 32 ]; then
      echo "ERROR: API key too short"
      exit 1
    fi
  '';
};
```

### 5. Conditional Secret Loading

```nix
# Only load secrets when service is enabled
{
  sops.secrets = lib.optionalAttrs config.services.postgresql.enable {
    "database/password" = {
      owner = "postgres";
      restartUnits = [ "postgresql.service" ];
    };
  };
}
```

## Testing Your Integration

### Manual Testing

```bash
# Verify secret is decrypted
sudo cat /run/secrets.d/1/wifi/home_network/psk

# Check service status
systemctl status NetworkManager

# Verify configuration applied
nmcli connection show

# Test database connection
psql "$(cat /run/secrets.d/1/database/connection)"
```

### Automated Testing

```nix
# tests/integration/service-secrets.nix
{ pkgs, ... }:
{
  name = "service-secrets-integration";
  
  nodes.machine = { config, pkgs, ... }: {
    imports = [ 
      ../../modules/nixos/wifi-secrets.nix
      ../../modules/nixos/postgres-secrets.nix
    ];
    
    # Test configuration
    services.wifiSecrets.enable = true;
    services.postgresSecrets.enable = true;
  };
  
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    
    # Test WiFi secrets
    machine.succeed("test -f /run/secrets.d/1/wifi/home_network/psk")
    
    # Test database secrets
    machine.succeed("test -f /run/secrets.d/1/postgres/main/password")
    
    # Verify NetworkManager has profiles
    machine.succeed("nmcli connection show | grep -q MyHomeWiFi")
  '';
}
```

## Troubleshooting Integration Issues

### Common Problems

1. **Service starts before secrets are ready**
   - Add `after = [ "sops-nix.service" ];` to service configuration
   
2. **Permission denied accessing secrets**
   - Verify owner and mode in SOPS configuration
   - Check service runs with correct user

3. **Secrets not updating after change**
   - Add service to `restartUnits` in secret configuration
   - Run `nixos-rebuild switch` to apply changes

4. **Connection string format issues**
   - Use script to build connection strings from components
   - Validate format before writing to file

## Next Steps

- Review the [Troubleshooting Guide](./troubleshooting-guide.md) for common issues
- See the [Administrator Handbook](./administrator-handbook.md) for daily operations
- Check the [Production Deployment Guide](./production-deployment.md) for scaling considerations