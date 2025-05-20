# Secrets Management (sops-nix)

This directory will contain encrypted secrets managed by sops-nix.

## Setup

1. Install sops and age:
   ```
   nix-shell -p sops age
   ```

2. Generate age keys:
   ```
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

3. Create a .sops.yaml file in the repo root:
   ```yaml
   keys:
     - &user_tim age1xyz123... # Your public key here
     - &host_mbp age1abc456... # MBP host key
     # Add more keys as needed
     
   creation_rules:
     - path_regex: secrets/[^/]+\.(yaml|json|env|ini)$
       key_groups:
       - age:
         - *user_tim
         - *host_mbp
   ```

4. Create your first encrypted secret:
   ```
   sops secrets/mysecret.yaml
   ```

5. Reference secrets in your NixOS config:
   ```nix
   {
     sops.defaultSopsFile = ../secrets/mysecret.yaml;
     sops.secrets.example_key = {};
   }
   ```

See the sops-nix documentation for more details: https://github.com/Mic92/sops-nix
