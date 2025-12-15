# GitHub Authentication with Bitwarden and SOPS-NiX

## Overview

This guide explains how to set up automatic GitHub authentication on NixOS machines using either:
1. **Bitwarden** (recommended) - Dynamic token retrieval, more secure
2. **SOPS-NiX** - Static encrypted tokens, simpler but less flexible

Both methods ensure you can immediately authenticate to GitHub CLI and push/pull from private repos on newly provisioned machines.

> **Quick Start**: If you want to get up and running in 5 minutes, jump to the [Quick Start Guide](#quick-start-guide) section below.

## Table of Contents
- [Quick Start Guide](#quick-start-guide)
- [Method 1: Bitwarden Integration](#method-1-bitwarden-integration-recommended)
- [Method 2: SOPS-NiX](#method-2-sops-nix-alternative)
- [Architecture](#architecture)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [History & References](#history--references)

---

## Quick Start Guide

Get GitHub authentication working in 5 minutes!

### Prerequisites
- ✅ NixOS system with this nixcfg flake
- ✅ Bitwarden account (free tier works)
- ✅ `rbw` configured (already set up in nixcfg)

### Step 1: Create GitHub Token (2 minutes)

1. Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
2. Click **"Generate new token (classic)"**
3. Settings:
   - **Note**: `NixOS Authentication`
   - **Expiration**: `90 days` (or custom)
   - **Scopes**: Check these boxes:
     - ✅ `repo` (Full control of private repositories)
     - ✅ `workflow` (Update GitHub Action workflows)
     - ✅ `read:org` (Read org and team membership)
4. Click **"Generate token"**
5. **COPY THE TOKEN NOW** (you won't see it again!)

### Step 2: Store Token in Bitwarden (1 minute)

```bash
# Make sure Bitwarden is unlocked
rbw unlock

# Store your GitHub token
rbw add github-token --folder "Infrastructure/Tokens"
# When prompted, paste your token from Step 1

# Verify it's stored
rbw get github-token  # Should show your token
```

### Step 3: Enable in Your Home-Manager Config (1 minute)

The module is already enabled in `home/modules/base.nix` for all users. No additional configuration needed!

### Step 4: Apply Configuration (1 minute)

```bash
# Apply home-manager configuration
home-manager switch --flake '.#tim@thinky-nixos'

# Test it works
gh auth status
# Should show: ✓ Logged in to github.com as YOUR-USERNAME

# Test CLI
gh repo list
gh pr list

# Test git operations (no password needed!)
git clone https://github.com/timblaktu/private-repo
```

### After Each Reboot

Since we're using the secure non-persistent mode:
```bash
# Unlock Bitwarden if needed
rbw unlock

# Authentication is automatic - just start using gh/git!
```

That's it! For detailed configuration options and advanced usage, continue reading below.

---

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

## Architecture

### Wrapper-Based Design (Current Implementation)

The authentication system uses a **wrapper script architecture** that eliminates configuration redundancy and provides a single source of truth for credentials.

#### Key Components

1. **Wrapper Scripts**:
   - `gh-with-auth`: Wraps the `gh` CLI, injecting `GH_TOKEN` from Bitwarden at runtime
   - `glab-with-auth`: Wraps the `glab` CLI, injecting `GITLAB_TOKEN` from Bitwarden at runtime

2. **Dual-Purpose Design**:
   ```
   CLI Operations:  gh → gh-with-auth → fetches token → exec real gh
   Git Operations:  git → gh auth git-credential (via wrapper) → fetches token → provides to git
   ```

3. **Single Configuration Point**:
   - Bitwarden item/field specified ONCE in wrapper definition
   - Same wrapper used for both CLI and git credential operations
   - No duplication, no staleness

#### How It Works

**CLI Example (gh repo list)**:
```bash
$ gh repo list
→ gh-with-auth wrapper executes
→ Fetches token from Bitwarden: $(rbw get github-token)
→ Exports: GH_TOKEN="ghp_xxxx..."
→ Execs: /nix/store/.../gh/bin/gh repo list
→ gh CLI sees GH_TOKEN and uses it
```

**Git Example (git clone)**:
```bash
$ git clone https://github.com/user/repo
→ git needs credentials for github.com
→ Calls credential helper: !gh auth git-credential
→ gh-with-auth wrapper executes (same wrapper!)
→ Fetches token from Bitwarden: $(rbw get github-token)
→ Exports: GH_TOKEN="ghp_xxxx..."
→ Execs: /nix/store/.../gh/bin/gh auth git-credential
→ gh provides token to git in credential helper protocol
→ git uses token for authentication
```

#### Benefits

- ✅ **Single Source of Truth**: Token location defined once per service
- ✅ **No Duplication**: Same wrapper for CLI and git operations
- ✅ **Always Fresh**: Tokens fetched from Bitwarden on every operation
- ✅ **No Storage**: Tokens never written to disk
- ✅ **Simplified Code**: ~150 lines removed vs. custom credential helpers
- ✅ **Leverages Official Integration**: Uses `gh/glab auth git-credential` built-in commands

#### Previous Architectures

**Version 1 (Removed)**: NixOS system modules with activation scripts - wrong scope, over-engineered
**Version 2 (Removed)**: Custom credential helpers with shell aliases - redundant configuration
**Version 3 (Current)**: Wrapper-based unified approach - optimal design

For historical context, see the [History & References](#history--references) section below.

## Integration with Existing Modules

This authentication system integrates with:
- **home/modules/github-auth.nix** - Main authentication module with wrapper generation
- **home/common/git.nix** - Git configuration (credential helper setup)
- **home/modules/secrets-management.nix** - Bitwarden/rbw configuration pattern
- **modules/nixos/sops-nix.nix** - SOPS secrets management (alternative mode)

## Migration from Manual Setup

If you currently:
- **Store tokens in `.env` files**: Move to Bitwarden/SOPS
- **Use SSH keys only**: Add HTTPS token auth for better CLI integration
- **Have tokens in shell config**: Remove and use this module
- **Use old NixOS system modules**: Switch to home-manager module (see git history)

## History & References

This authentication system has evolved through several design iterations:

### Design Evolution
1. **2025-11-20**: Initial NixOS system module design (deprecated)
   - See: `docs/redesigns/github-auth-redesign-2025-11-20.md` (removed)
   - Issue: Wrong scope (system vs user)

2. **2025-12-04**: GitLab CLI authentication fix
   - See: `docs/redesigns/gitlab-auth-fix-2025-12-04.md` (removed)
   - Moved to env var injection pattern

3. **2025-12-05**: Research on gh/glab credential helper integration
   - See: `docs/git-auth-integration-research-2025-12-05.md` (removed)
   - Discovered official credential helper commands

4. **2025-12-06**: Wrapper-based architecture implementation
   - See: `docs/auth-refactoring-session-2025-12-05.md` (removed)
   - Current design: Single wrapper for CLI + git operations

### Key Design Decisions

**Why Wrappers Instead of Custom Credential Helpers?**
- Eliminates duplication (Bitwarden config in one place)
- Leverages official `gh/glab auth git-credential` commands
- Simpler codebase (~150 lines removed)
- Single authentication flow for CLI and git

**Why Not Export GH_TOKEN as Session Variable?**
- Would be evaluated once at shell startup (stale tokens)
- Token in process environment for entire session (security concern)
- Doesn't help non-shell contexts (systemd, cron)

**Why Home-Manager Module vs NixOS Module?**
- Authentication is user-specific, not system-wide
- Works automatically on all hosts where user exists
- Proper separation of concerns

For the complete history of design iterations and architectural decisions, see the git commit history for `home/modules/github-auth.nix`.

## Next Steps

1. Follow the [Quick Start Guide](#quick-start-guide) to get started quickly
2. Review [Best Practices](#best-practices) for secure token management
3. Configure for your environment (Bitwarden or SOPS)
4. Test thoroughly with both CLI and git operations
5. Enjoy seamless GitHub/GitLab authentication across all machines!

## Security Notes

- Tokens are more convenient but less secure than SSH keys
- **Recommended**: Use both - SSH keys for git operations, tokens for GitHub CLI
- Consider using GitHub's new fine-grained personal access tokens
- Enable GitHub's security features: 2FA, signed commits, vigilant mode
- Regularly rotate tokens (set calendar reminder for expiration)