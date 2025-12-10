# GitHub Authentication with Bitwarden and SOPS-NiX

## Overview

This guide explains how to set up automatic GitHub authentication on NixOS machines using either:
1. **Bitwarden** (recommended) - Dynamic token retrieval, more secure
2. **SOPS-NiX** - Static encrypted tokens, simpler but less flexible

Both methods ensure you can immediately authenticate to GitHub CLI and push/pull from private repos on newly provisioned machines.

## Method 1: Bitwarden Integration (Recommended)

This method stores GitHub tokens in Bitwarden and retrieves them on-demand, following the same pattern as SSH key management.

### Advantages
- ✅ Single source of truth (Bitwarden) for all secrets
- ✅ Tokens never stored in plaintext on disk
- ✅ Easy token rotation - just update in Bitwarden
- ✅ Supports multiple GitHub accounts
- ✅ Works across all your machines instantly

### Setup Steps

#### 1. Store GitHub Token in Bitwarden

```bash
# Generate a GitHub Personal Access Token
# Go to: https://github.com/settings/tokens/new
# Scopes needed: repo, workflow, read:org, gist
# Set expiration: 1 year (rotate regularly)

# Store in Bitwarden
rbw add --folder "Infrastructure/Tokens" github-token
# Enter the token when prompted

# For multiple accounts
rbw add --folder "Infrastructure/Tokens" github-token-work
rbw add --folder "Infrastructure/Tokens" github-token-personal
```

#### 2. Enable in NixOS Configuration

```nix
# In your host configuration (e.g., hosts/thinky-nixos/default.nix)
{ config, lib, pkgs, ... }:
{
  imports = [
    # ... other imports
    ../../modules/nixos/bitwarden-github-auth.nix
  ];

  # Enable Bitwarden GitHub authentication
  bitwardenGitHub = {
    enable = true;
    users = [ "tim" ];  # Users to configure

    # Optional: customize settings
    bitwarden = {
      tokenName = "github-token";  # Entry name in Bitwarden
      folder = "Infrastructure/Tokens";
      multiAccount = false;  # Set true for multiple GitHub accounts
    };

    configureGit = true;   # Configure git credentials
    configureGh = true;    # Configure GitHub CLI
    gitProtocol = "https"; # or "ssh"
    persistent = false;    # If true, persists across reboots
  };

  # Ensure rbw is configured (usually in home-manager)
  # See existing rbw configuration in home/common/system.nix
}
```

#### 3. Apply Configuration

```bash
# Rebuild NixOS
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# Initialize GitHub authentication (first time)
github-auth-init

# Test authentication
/etc/github-auth/test-github.sh
```

#### 4. Usage

After setup, you can immediately:
```bash
# Clone private repos
git clone https://github.com/yourusername/private-repo

# Use GitHub CLI
gh repo list
gh pr create
gh issue list

# Push to repos (credentials fetched from Bitwarden automatically)
git push
```

### How It Works

1. **On-demand token retrieval**: When git needs credentials, it calls a custom askpass script
2. **Askpass script**: Fetches token from Bitwarden using `rbw`
3. **No plaintext storage**: Tokens only exist in memory during operations
4. **Automatic authentication**: GitHub CLI is authenticated using the token

## Method 2: SOPS-NiX (Alternative)

For environments where Bitwarden isn't available or you prefer static encrypted secrets.

### Setup Steps

#### 1. Create GitHub Secrets File

```bash
# Copy the template
cd secrets/common
cp github.yaml.template github.yaml

# Edit with SOPS (will encrypt automatically)
sops github.yaml

# Add your GitHub token:
github_token: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### 2. Create Simple Module

```nix
# modules/nixos/github-sops-auth.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.githubSopsAuth;
in
{
  options.githubSopsAuth = {
    enable = lib.mkEnableOption "GitHub auth via SOPS";
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    # Define the secret
    sops.secrets."github_token" = {
      sopsFile = ../../secrets/common/github.yaml;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # Create auth script
    system.activationScripts.githubAuth = lib.stringAfter ["sops-install-secrets"] ''
      TOKEN_PATH="${config.sops.secrets.github_token.path}"

      if [ -f "$TOKEN_PATH" ]; then
        TOKEN=$(cat "$TOKEN_PATH")

        # Configure for each user
        ${lib.concatMapStrings (user: ''
          if [ -d /home/${user} ]; then
            # Setup git credentials
            echo "https://token:$TOKEN@github.com" > /home/${user}/.git-credentials
            chmod 600 /home/${user}/.git-credentials
            chown ${user}:users /home/${user}/.git-credentials

            # Configure gh CLI
            sudo -u ${user} sh -c "echo '$TOKEN' | gh auth login --with-token"
          fi
        '') cfg.users}
      fi
    '';
  };
}
```

#### 3. Enable in Host Configuration

```nix
{
  imports = [ ../../modules/nixos/github-sops-auth.nix ];

  githubSopsAuth = {
    enable = true;
    users = [ "tim" ];
  };

  # Also ensure SOPS-NiX is enabled
  sopsNix = {
    enable = true;
    hostKeyPath = "/etc/sops/age.key";
  };
}
```

## Comparison: Bitwarden vs SOPS-NiX

| Feature | Bitwarden | SOPS-NiX |
|---------|-----------|----------|
| **Security** | ✅ Tokens never on disk | ⚠️ Encrypted on disk |
| **Token Rotation** | ✅ Update in Bitwarden | ❌ Re-encrypt & redeploy |
| **Multi-machine** | ✅ Instant sync | ❌ Manual update each host |
| **Offline Access** | ❌ Needs unlock | ✅ Always available |
| **Setup Complexity** | Medium | Low |
| **Dependencies** | rbw, internet | age keys |

## Best Practices

1. **Token Scopes**: Use minimal required scopes
   - `repo` - Full control of private repos
   - `workflow` - Update GitHub Actions
   - `read:org` - Read org membership
   - `gist` - Create gists

2. **Token Rotation**:
   - Set expiration to 1 year maximum
   - Rotate every 6 months
   - Use the systemd timer reminder (included in module)

3. **Security**:
   - Never commit tokens to git (use `.gitignore`)
   - Use Bitwarden method for better security
   - Enable 2FA on your GitHub account
   - Use different tokens for different purposes

4. **Multiple Accounts**:
   ```nix
   bitwardenGitHub = {
     enable = true;
     bitwarden.multiAccount = true;
     # Expects: github-token-tim, github-token-work, etc.
   };
   ```

## Troubleshooting

### Token Not Working
```bash
# Check token validity
gh auth status

# Re-authenticate
github-auth-init

# Test with curl
curl -H "Authorization: token $(rbw get github-token)" https://api.github.com/user
```

### Bitwarden Locked
```bash
# Unlock Bitwarden
rbw unlock

# Then reinitialize
github-auth-init
```

### Permission Denied on Push
- Ensure token has `repo` scope
- Check repository permissions
- Verify you're using HTTPS not SSH (or vice versa)

### Multiple GitHub Accounts
```bash
# Switch between accounts
git config user.email "work@company.com"
rbw get github-token-work | gh auth login --with-token
```

## Integration with Existing Modules

This authentication system integrates with:
- **home/common/git.nix** - Git configuration
- **modules/nixos/bitwarden-ssh-keys.nix** - SSH key management pattern
- **modules/nixos/sops-nix.nix** - SOPS secrets management

## Migration from Manual Setup

If you currently:
- **Store tokens in `.env` files**: Move to Bitwarden/SOPS
- **Use SSH keys only**: Add HTTPS token auth for better CLI integration
- **Have tokens in shell config**: Remove and use this module

## Next Steps

1. Choose your method (Bitwarden recommended)
2. Set up your GitHub token
3. Enable the module in your host configuration
4. Test with `github-auth-init`
5. Enjoy seamless GitHub authentication on all machines!

## Security Notes

- Tokens are more convenient but less secure than SSH keys
- Use both: SSH keys for git operations, tokens for GitHub CLI
- Consider using GitHub's new fine-grained personal access tokens
- Enable GitHub's security features: 2FA, signed commits, vigilant mode