# GitHub Authentication with Bitwarden and SOPS-NiX

## Overview

This guide explains how to set up automatic GitHub authentication on NixOS machines using either:
1. **Bitwarden** (recommended) - Dynamic token retrieval, more secure
2. **SOPS-NiX** (Secrets OPerationS for Nix) - Static encrypted tokens, simpler but less flexible

Both methods ensure you can immediately authenticate to the [GitHub CLI](https://cli.github.com/) (`gh`) and push/pull from private repos on newly provisioned machines. Token access goes through Bitwarden via [`rbw`](https://github.com/doy/rbw), an unofficial command-line Bitwarden client. The module lives at [`modules/programs/github-auth/github-auth.nix`](../modules/programs/github-auth/github-auth.nix) and a matching GitLab variant at [`modules/programs/gitlab-auth/gitlab-auth.nix`](../modules/programs/gitlab-auth/gitlab-auth.nix). See [Comparison: Bitwarden vs SOPS-NiX](#comparison-bitwarden-vs-sops-nix) for the full trade-off.

> **Quick Start**: If you want to get up and running in 5 minutes, jump to the [Quick Start Guide](#quick-start-guide) section below.

> **Current module interface**: The authoritative configuration lives under the home-manager option `gitAuth.github`, defined in [`modules/programs/github-auth/github-auth.nix`](../modules/programs/github-auth/github-auth.nix). Some step-by-step examples further down predate this module and reference an older NixOS-level `bitwardenGitHub` option; treat `gitAuth.github` as the source of truth. A minimal Bitwarden setup is:
>
> ```nix
> imports = [ inputs.self.modules.homeManager.github-auth ];
> gitAuth.github = {
>   enable = true;
>   bitwarden = {
>     item = "github.com";
>     field = "PAT-mytoken";
>   };
> };
> ```

The key options on `gitAuth.github`:

| Option | Purpose | Default |
|---|---|---|
| `enable` | Turn the module on | `false` |
| `mode` | Secret backend (`bitwarden` or `sops`) | - |
| `protocol` | Git remote protocol (`https` or `ssh`) | - |
| `bitwarden.item` / `bitwarden.field` | Bitwarden entry and field holding the token | `github-token` item |
| `sops.secretName` / `sops.secretsFile` | SOPS secret name and encrypted file | `github_token`, `secrets/common/github.yaml` |
| `git.enableCredentialHelper` | Wire up the git credential helper | - |
| `cli.enable` / `cli.enableAliases` | Install and alias the `gh` CLI | `true` / `true` |
| `cli.tokenOverrides.<subcommand>` | Use a different token for a specific `gh` subcommand (for example, a classic PAT for cross-fork `pr`) | `{}` |
| `nix.enableAccessToken` | Configure a nix access-token for rate-limit-free GitHub fetches | `true` |
| `orgs.<name>` | Per-organization token source | `{}` |

## Table of Contents
- [Quick Start Guide](#quick-start-guide)
- [Method 1: Bitwarden Integration](#method-1-bitwarden-integration-recommended)
- [Method 2: SOPS-NiX](#method-2-sops-nix-alternative)
- [Comparison: Bitwarden vs SOPS-NiX](#comparison-bitwarden-vs-sops-nix)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Integration with Existing Modules](#integration-with-existing-modules)
- [Migration from Manual Setup](#migration-from-manual-setup)
- [History & References](#history--references)
- [Next Steps](#next-steps)
- [Security Notes](#security-notes)

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

Enable the module through the `gitAuth.github` option shown in the [Current module interface](#overview) callout above. Import `inputs.self.modules.homeManager.github-auth` in your home-manager configuration and set `gitAuth.github.enable = true` with the Bitwarden item and field for your token.

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

#### 2. Enable in Your Home-Manager Configuration

The module is a home-manager module, imported via `inputs.self.modules.homeManager.github-auth`, and all configuration lives under the `gitAuth.github` option. It is per-user, not system-wide, so you enable it in your home-manager configuration rather than in a NixOS system module.

```nix
# In your home-manager configuration
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    # ... other imports
    inputs.self.modules.homeManager.github-auth
  ];

  # Enable Bitwarden-backed GitHub authentication
  gitAuth.github = {
    enable = true;
    mode = "bitwarden";   # secret backend: "bitwarden" (default) or "sops"
    protocol = "https";   # git remote protocol: "https" (default) or "ssh"

    # Which Bitwarden item and field hold the token.
    # Leave `field` unset to read the item's password field.
    bitwarden = {
      item = "github.com";
      field = "PAT-mytoken";
    };

    git.enableCredentialHelper = true; # wire up the git credential helper (default true)
    cli.enable = true;                 # install and wrap the gh CLI (default true)
    nix.enableAccessToken = true;      # token file for rate-limit-free nix GitHub fetches (default true)
  };
}
```

Bitwarden mode asserts `secretsManagement.enable = true`, so make sure `rbw` is configured for your user (see the existing `secretsManagement` configuration in this repo).

#### 3. Apply Configuration

```bash
# Apply your home-manager configuration (use your own host, e.g. tim@thinky-nixos)
home-manager switch --flake '.#<your-user>@<your-host>'

# Test authentication (gh is wrapped to inject the token from Bitwarden)
gh auth status

# Verify a git operation over HTTPS fetches credentials automatically
git clone https://github.com/<your-user>/private-repo
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

SOPS support is built into the same module: set `gitAuth.github.mode = "sops"` and the wrapper reads the token from a SOPS-decrypted file instead of Bitwarden. You do not write a separate module or activation script.

### Setup Steps

#### 1. Create GitHub Secrets File

```bash
# Create the encrypted secrets file (SOPS encrypts on save)
cd secrets/common
sops github.yaml

# Add your GitHub token under the secret name the module expects by default:
github_token: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### 2. Enable SOPS Mode in Your Home-Manager Configuration

```nix
# In your home-manager configuration
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    # ... other imports
    inputs.self.modules.homeManager.github-auth
  ];

  gitAuth.github = {
    enable = true;
    mode = "sops";

    # SOPS secret name and encrypted file (these are the module defaults;
    # override only if your secret lives elsewhere).
    sops = {
      secretName = "github_token";
      secretsFile = ../../../secrets/common/github.yaml;
    };

    git.enableCredentialHelper = true;
    cli.enable = true;
  };
}
```

The module expects the SOPS secret at `config.sops.secrets."<secretName>".path`, so ensure your SOPS integration (the `sops-nix` home-manager module) is configured and decrypting `secretsFile` with your host/user key.

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

4. **Multiple tokens for different contexts**: The current module does not have a single `multiAccount` toggle. Instead it routes to different Bitwarden credentials by context, which is more precise. Use `orgs.<name>` to select a token for repositories under a given GitHub organization (matched by the remote URL), and `cli.tokenOverrides.<subcommand>` to use a different token for a specific `gh` subcommand (for example, a classic PAT for cross-fork `pr` creation).
   ```nix
   gitAuth.github = {
     enable = true;
     bitwarden = { item = "github.com"; field = "PAT-mytoken"; };

     # Per-organization token: repos under github.com/my-org/ use this token.
     orgs.my-org.bitwarden = { item = "github.com"; field = "PAT-my-org"; };

     # Per-subcommand override: `gh pr ...` uses a classic PAT.
     cli.tokenOverrides.pr = { item = "github.com"; field = "PAT-classic"; };
   };
   ```

## Troubleshooting

### Token Not Working
```bash
# Check token validity (gh is wrapped to inject the Bitwarden token)
gh auth status

# Confirm the token itself is readable from Bitwarden (adjust item/field to yours)
rbw get github.com --field PAT-mytoken

# Test with curl
curl -H "Authorization: token $(rbw get github.com --field PAT-mytoken)" https://api.github.com/user
```

### Bitwarden Locked
```bash
# Unlock Bitwarden - the wrapper fetches the token fresh on the next gh/git call,
# so there is no separate init step to re-run.
rbw unlock
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

1. **Wrapper Scripts**: The module installs a wrapped `gh` (and the GitLab module a wrapped `glab`) in place of the upstream binary, built with `writeShellScriptBin "gh"`. The wrapper reads the token from Bitwarden via `rbw`, exports it as `GH_TOKEN` (`GITLAB_TOKEN` for `glab`), and then execs the real `gh`.

2. **Two paths to a token**: CLI calls and git operations are served differently. The CLI path injects `GH_TOKEN` into the wrapped `gh`. The git path is driven by the git credential helper that `gitAuth.github.git.enableCredentialHelper` configures (it is on by default). The helper does NOT uniformly read Bitwarden directly: for the default `github.com` token it delegates to `gh auth git-credential get` (which returns the token `gh auth login` stored), and only for a repository that matches a configured `orgs.<name>` entry does it read that org's token directly from `rbw` and emit `username=x-access-token` with `password=<token>`. This split exists because `gh auth git-credential` ignores `GH_TOKEN` and always returns the `gh auth login` token, so a per-org token has to be emitted by hand.

3. **Credential helper scope**: The helper is scoped per host, not per org. `enableCredentialHelper` writes a single `credential."https://github.com"` helper (plus a `credential."https://gist.github.com"` entry that delegates to `gh auth git-credential`). Git ignores the URL path when matching credential contexts, so a separate per-org `credential."https://github.com/<org>"` section would be shadowed by the generic one. Instead the single `https://github.com` helper is given `useHttpPath = true`, reads the repository path from the git credential protocol on stdin, and dispatches to the matching org token internally by that path.

4. **Single Configuration Point**: The Bitwarden item/field (and any per-org or per-subcommand overrides) are declared once on `gitAuth.github`, and both the CLI wrapper and the git credential helper read from that one declaration.

#### How It Works

The wrapper and the credential helper both run a throttled `rbw sync` first (controlled by `rbwSyncInterval`, default 300 seconds): they re-sync the local Bitwarden cache only if the last sync was longer ago than that, then read the token from the local `rbw` store on each call. A rotated token therefore takes effect on the next call once the cache has re-synced, without any separate init step.

```mermaid
sequenceDiagram
    participant U as You
    participant GH as "gh (wrapper)"
    participant Git as git
    participant H as "credential helper (https://github.com)"
    participant RBW as rbw / Bitwarden
    participant GHauth as "gh auth git-credential"
    Note over U,RBW: CLI path (for example, gh repo list)
    U->>GH: gh repo list
    GH->>RBW: rbw sync if stale, then rbw get (item/field)
    RBW-->>GH: token
    GH->>GH: export GH_TOKEN, exec real gh
    Note over U,GHauth: Git path, default token (no org match)
    U->>Git: git clone https://github.com/user/repo
    Git->>H: credential request (with path, via useHttpPath)
    H->>GHauth: delegate "gh auth git-credential get"
    GHauth-->>H: "username / password"
    H-->>Git: "username / password"
    Note over U,RBW: Git path, configured org match
    U->>Git: git clone https://github.com/my-org/repo
    Git->>H: credential request (path=my-org/repo)
    H->>RBW: rbw get (org item/field)
    RBW-->>H: token
    H-->>Git: "username=x-access-token / password=token"
```

#### Benefits

- ✅ **Single Source of Truth**: Token location defined once per service
- ✅ **No Duplication**: One declaration feeds both the CLI wrapper and the git credential helper
- ✅ **Fresh on use**: The token is read from the local rbw store on each call, with the Bitwarden server sync throttled by `rbwSyncInterval` (default 300 seconds)
- ✅ **Minimal disk footprint**: The CLI and git paths keep the token in memory; the only on-disk copy is the optional `~/.config/nix/github-token` file (mode 600) written when `nix.enableAccessToken` is set, so nix can fetch from GitHub without rate limits
- ✅ **Leverages Official Integration**: The default `github.com` token path delegates to the built-in `gh auth git-credential`

#### Previous Architectures

**Version 1 (Removed)**: NixOS system modules with activation scripts - wrong scope, over-engineered
**Version 2 (Removed)**: Custom credential helpers with shell aliases - redundant configuration
**Version 3 (Current)**: Wrapper-based unified approach - optimal design

For historical context, see the [History & References](#history--references) section below.

## Integration with Existing Modules

This authentication system integrates with:
- [`modules/programs/github-auth/github-auth.nix`](../modules/programs/github-auth/github-auth.nix) - Main authentication module with wrapper and credential-helper generation
- [`modules/programs/gitlab-auth/gitlab-auth.nix`](../modules/programs/gitlab-auth/gitlab-auth.nix) - GitLab equivalent (`glab` wrapper, `GITLAB_TOKEN` injection)

## Migration from Manual Setup

If you currently:
- **Store tokens in `.env` files**: Move to Bitwarden/SOPS
- **Use SSH keys only**: Add HTTPS token auth for better CLI integration
- **Have tokens in shell config**: Remove and use this module
- **Use old NixOS system modules**: Switch to home-manager module (see git history)

## History & References

This authentication system evolved through several design iterations, from an initial NixOS system module (wrong scope: system rather than user), through a GitLab CLI fix that moved to environment-variable token injection, to the current wrapper-based architecture that unifies CLI and git credential flows. The full iteration history lives in the git commit log for [`modules/programs/github-auth/github-auth.nix`](../modules/programs/github-auth/github-auth.nix).

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

For the complete history of design iterations and architectural decisions, see the git commit history for [`modules/programs/github-auth/github-auth.nix`](../modules/programs/github-auth/github-auth.nix).

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