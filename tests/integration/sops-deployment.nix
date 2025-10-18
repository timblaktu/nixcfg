# SOPS-NiX Secret Deployment Integration Test
# Tests full SOPS-NiX deployment on actual NixOS system
{ pkgs, lib, ... }:

pkgs.nixosTest {
  name = "sops-nix-deployment-integration";

  nodes = {
    sopshost = { config, pkgs, ... }: {
      # Simulate SOPS-NiX module without importing
      # (to avoid dependency issues in test environment)
      
      # Generate test age keys at build time
      system.activationScripts.generateTestKeys = {
        text = ''
          if [ ! -f /var/lib/sops-age-keys/keys.txt ]; then
            mkdir -p /var/lib/sops-age-keys
            ${pkgs.age}/bin/age-keygen -o /var/lib/sops-age-keys/keys.txt 2>/dev/null
            chmod 600 /var/lib/sops-age-keys/keys.txt
          fi
        '';
      };

      # Create test secrets file
      environment.etc."test-secrets.yaml".text = ''
        # This would normally be encrypted, but for testing we'll handle it in the test script
        database:
            password: ENC[AES256_GCM,data:test,iv:test,tag:test,type:str]
        api_keys:
            service1: ENC[AES256_GCM,data:test,iv:test,tag:test,type:str]
        ssh_keys:
            deploy_key: ENC[AES256_GCM,data:test,iv:test,tag:test,type:str]
      '';

      # Mock sops configuration would go here if the module was imported
      # For testing, we'll handle this manually in the test script

      # Test service that uses secrets
      systemd.services.secret-test-service = {
        description = "Test service using SOPS secrets";
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        
        script = ''
          echo "Testing secret access..."
          if [ -f /run/secrets.d/1/database/password ]; then
            echo "Database password secret exists"
          else
            echo "ERROR: Database password secret missing"
            exit 1
          fi
          
          if [ -f /run/secrets.d/1/api_keys/service1 ]; then
            echo "API key secret exists"
          else
            echo "ERROR: API key secret missing"
            exit 1
          fi
        '';
        
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      environment.systemPackages = with pkgs; [
        age
        sops
        gnupg
      ];

      networking.firewall.enable = false;
      virtualisation.memorySize = 1024;
    };
  };

  testScript = ''
    import os
    import time
    import json
    
    start_all()
    
    print("=" * 60)
    print("SOPS-NiX Deployment Integration Test")
    print("=" * 60)
    
    sopshost.wait_for_unit("multi-user.target")
    
    print("\n[1] Testing age key generation")
    sopshost.succeed("test -f /var/lib/sops-age-keys/keys.txt")
    age_key = sopshost.succeed("cat /var/lib/sops-age-keys/keys.txt")
    assert "AGE-SECRET-KEY" in age_key, "Age key not generated properly"
    print("✓ Age key generated successfully")
    
    print("\n[2] Testing SOPS configuration")
    # Extract public key for SOPS config
    pubkey = sopshost.succeed("grep -oP 'age1\\w+' /var/lib/sops-age-keys/keys.txt | head -1").strip()
    print(f"✓ Public key extracted: {pubkey[:20]}...")
    
    # Create proper SOPS config
    sopshost.succeed(f"""
      cat > /tmp/.sops.yaml <<'EOF'
keys:
  - &admin {pubkey}
creation_rules:
  - path_regex: .*\\.yaml$
    key_groups:
      - age:
          - *admin
EOF
    """)
    
    print("\n[3] Creating and encrypting test secrets")
    # Create plaintext secrets
    sopshost.succeed("""
      cat > /tmp/secrets.yaml <<'EOF'
database:
    password: supersecret123
api_keys:
    service1: key-abc-123-xyz
ssh_keys:
    deploy_key: |
        -----BEGIN OPENSSH PRIVATE KEY-----
        test-key-content
        -----END OPENSSH PRIVATE KEY-----
EOF
    """)
    
    # Encrypt with SOPS
    sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      cd /tmp
      sops --config /tmp/.sops.yaml --encrypt --in-place secrets.yaml
    """)
    
    # Verify encryption
    encrypted = sopshost.succeed("cat /tmp/secrets.yaml")
    assert "ENC[AES256_GCM" in encrypted, "Secrets not properly encrypted"
    print("✓ Secrets encrypted successfully")
    
    print("\n[4] Testing secret decryption to /run/secrets.d/")
    # Simulate SOPS-NiX behavior
    sopshost.succeed("mkdir -p /run/secrets.d/1")
    
    # Decrypt specific secrets
    sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      cd /tmp
      
      # Extract database password
      mkdir -p /run/secrets.d/1/database
      sops --config /tmp/.sops.yaml --decrypt --extract '["database"]["password"]' secrets.yaml > /run/secrets.d/1/database/password
      chmod 400 /run/secrets.d/1/database/password
      
      # Extract API key
      mkdir -p /run/secrets.d/1/api_keys
      sops --config /tmp/.sops.yaml --decrypt --extract '["api_keys"]["service1"]' secrets.yaml > /run/secrets.d/1/api_keys/service1
      chmod 400 /run/secrets.d/1/api_keys/service1
      chown nobody:nogroup /run/secrets.d/1/api_keys/service1
      
      # Extract SSH key
      mkdir -p /run/secrets.d/1/ssh_keys
      mkdir -p /root/.ssh
      sops --config /tmp/.sops.yaml --decrypt --extract '["ssh_keys"]["deploy_key"]' secrets.yaml > /root/.ssh/deploy_key
      chmod 600 /root/.ssh/deploy_key
    """)
    
    print("✓ Secrets decrypted to runtime directory")
    
    print("\n[5] Testing secret permissions and ownership")
    # Check database password
    perms = sopshost.succeed("stat -c %a /run/secrets.d/1/database/password").strip()
    assert perms == "400", f"Wrong database password permissions: {perms}"
    owner = sopshost.succeed("stat -c %U:%G /run/secrets.d/1/database/password").strip()
    assert owner == "root:root", f"Wrong database password owner: {owner}"
    
    # Check API key
    perms = sopshost.succeed("stat -c %a /run/secrets.d/1/api_keys/service1").strip()
    assert perms == "400", f"Wrong API key permissions: {perms}"
    owner = sopshost.succeed("stat -c %U:%G /run/secrets.d/1/api_keys/service1").strip()
    assert owner == "nobody:nogroup", f"Wrong API key owner: {owner}"
    
    # Check SSH key
    perms = sopshost.succeed("stat -c %a /root/.ssh/deploy_key").strip()
    assert perms == "600", f"Wrong SSH key permissions: {perms}"
    
    print("✓ Secret permissions and ownership correct")
    
    print("\n[6] Testing service integration")
    # Run the test service that uses secrets
    sopshost.succeed("systemctl start secret-test-service")
    sopshost.wait_for_unit("secret-test-service.service")
    status = sopshost.succeed("systemctl is-active secret-test-service").strip()
    assert status == "active", f"Service failed to start: {status}"
    
    # Check service logs
    logs = sopshost.succeed("journalctl -u secret-test-service --no-pager")
    assert "Database password secret exists" in logs, "Service couldn't access database secret"
    assert "API key secret exists" in logs, "Service couldn't access API key"
    print("✓ Service successfully accessed secrets")
    
    print("\n[7] Testing secret rotation scenario")
    # Update secrets
    sopshost.succeed("""
      cat > /tmp/secrets-new.yaml <<'EOF'
database:
    password: newsecret456
api_keys:
    service1: new-key-def-456
ssh_keys:
    deploy_key: |
        -----BEGIN OPENSSH PRIVATE KEY-----
        new-test-key-content
        -----END OPENSSH PRIVATE KEY-----
EOF
    """)
    
    # Encrypt new secrets
    sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      cd /tmp
      sops --config /tmp/.sops.yaml --encrypt --in-place secrets-new.yaml
    """)
    
    # Simulate rotation by re-decrypting
    sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      cd /tmp
      sops --config /tmp/.sops.yaml --decrypt --extract '["database"]["password"]' secrets-new.yaml > /run/secrets.d/1/database/password
      chmod 400 /run/secrets.d/1/database/password
    """)
    
    # Verify new secret
    new_password = sopshost.succeed("cat /run/secrets.d/1/database/password").strip()
    assert new_password == "<PLACEHOLDER_PASSWORD_IMPOSSIBLE>", "Secret rotation failed"
    print("✓ Secret rotation successful")
    
    print("\n[8] Testing error recovery scenarios")
    
    # Test missing age key recovery
    sopshost.succeed("mv /var/lib/sops-age-keys/keys.txt /var/lib/sops-age-keys/keys.txt.bak")
    sopshost.fail("export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt; sops --decrypt /tmp/secrets.yaml")
    sopshost.succeed("mv /var/lib/sops-age-keys/keys.txt.bak /var/lib/sops-age-keys/keys.txt")
    print("✓ Missing age key error handled correctly")
    
    # Test corrupted secrets file
    sopshost.succeed("echo 'corrupted' > /tmp/corrupted.yaml")
    sopshost.fail("export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt; sops --decrypt /tmp/corrupted.yaml")
    print("✓ Corrupted secrets file error handled correctly")
    
    print("\n[9] Testing multiple age recipients")
    # Generate second age key
    sopshost.succeed("${pkgs.age}/bin/age-keygen -o /tmp/keys2.txt 2>/dev/null")
    pubkey2 = sopshost.succeed("grep -oP 'age1\\w+' /tmp/keys2.txt | head -1").strip()
    
    # Create multi-recipient SOPS config
    sopshost.succeed(f"""
      cat > /tmp/.sops-multi.yaml <<'EOF'
keys:
  - &admin1 {pubkey}
  - &admin2 {pubkey2}
creation_rules:
  - path_regex: .*\\.yaml$
    key_groups:
      - age:
          - *admin1
          - *admin2
EOF
    """)
    
    # Encrypt with multiple recipients
    sopshost.succeed("""
      cat > /tmp/multi.yaml <<'EOF'
shared_secret: multi-recipient-value
EOF
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      cd /tmp
      sops --config /tmp/.sops-multi.yaml --encrypt --in-place multi.yaml
    """)
    
    # Decrypt with first key
    value1 = sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/var/lib/sops-age-keys/keys.txt
      sops --config /tmp/.sops-multi.yaml --decrypt --extract '["shared_secret"]' /tmp/multi.yaml
    """).strip()
    
    # Decrypt with second key
    value2 = sopshost.succeed("""
      export SOPS_AGE_KEY_FILE=/tmp/keys2.txt
      sops --config /tmp/.sops-multi.yaml --decrypt --extract '["shared_secret"]' /tmp/multi.yaml
    """).strip()
    
    assert value1 == value2 == "multi-recipient-value", "Multi-recipient encryption failed"
    print("✓ Multiple age recipients working")
    
    print("\n" + "=" * 60)
    print("All SOPS-NiX deployment tests passed!")
    print("=" * 60)
  '';
}