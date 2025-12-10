# 🚀 Quick GitHub Authentication Setup

Set up GitHub authentication in 5 minutes! This guide gets you authenticated to GitHub immediately.

## Prerequisites

- [ ] NixOS system with this nixcfg flake
- [ ] Bitwarden account (free tier works)
- [ ] `rbw` configured (already set up in nixcfg)

## Step 1: Create GitHub Token (2 minutes)

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

## Step 2: Store Token in Bitwarden (1 minute)

```bash
# Make sure Bitwarden is unlocked
rbw unlock

# Store your GitHub token
rbw add github-token --folder "Infrastructure/Tokens"
# When prompted, paste your token from Step 1

# Verify it's stored
rbw get github-token  # Should show your token
```

## Step 3: Enable in Your Host Config (1 minute)

Edit your host configuration:

```bash
# Edit your host configuration
nvim hosts/thinky-nixos/default.nix
```

Add this import to the imports list:
```nix
imports = [
  # ... existing imports ...
  ./github-auth.nix  # Add this line
];
```

The `github-auth.nix` file is already created with sensible defaults.

## Step 4: Apply and Test (1 minute)

```bash
# Apply the configuration
sudo nixos-rebuild switch --flake '.#thinky-nixos'

# Initialize GitHub authentication
github-auth-init

# You should see:
# 🔐 Bootstrapping GitHub authentication for tim...
# ✅ GitHub token retrieved from Bitwarden
# ✅ Git configured for GitHub authentication
# ✅ GitHub CLI authenticated successfully

# Test it works
gh auth status
# Should show: ✓ Logged in to github.com as YOUR-USERNAME
```

## 🎉 You're Done!

You can now:
```bash
# Clone private repos
git clone https://github.com/timblaktu/private-repo

# Use GitHub CLI
gh repo list                    # List your repos
gh pr create                     # Create pull request
gh issue create                  # Create issue
gh repo clone owner/repo         # Clone any repo

# Push to repos (no password needed!)
git push
```

## After Each Reboot

Since we're using the secure non-persistent mode:
```bash
# Unlock Bitwarden if needed
rbw unlock

# Re-initialize GitHub auth (takes 2 seconds)
github-auth-init
```

## Optional: Make It Persistent

If you want authentication to survive reboots (less secure):

Edit `hosts/thinky-nixos/github-auth.nix`:
```nix
bitwardenGitHub = {
  # ... other settings ...
  persistent = true;  # Change from false to true
};
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake '.#thinky-nixos'
```

## Troubleshooting

### "rbw is locked"
```bash
rbw unlock  # Enter your Bitwarden master password
```

### "Token not found in Bitwarden"
```bash
rbw list | grep github  # Check if token exists
rbw add github-token --folder "Infrastructure/Tokens"  # Re-add if needed
```

### "Permission denied when pushing"
- Check your token has `repo` scope
- Ensure you own the repository
- Run `github-auth-init` to refresh authentication

## Multiple GitHub Accounts?

1. Store multiple tokens:
```bash
rbw add github-token-personal --folder "Infrastructure/Tokens"
rbw add github-token-work --folder "Infrastructure/Tokens"
```

2. Update `github-auth.nix`:
```nix
bitwarden = {
  multiAccount = true;  # Enable multi-account support
};
```

## Next Steps

- Set a calendar reminder to rotate your token in 90 days
- Consider setting up commit signing (see SECRETS-MANAGEMENT.md)
- Explore `gh` CLI aliases: `gh alias list`

---

**Time to complete: ~5 minutes** ⏱️

**Security level: High** 🔒 (tokens never stored in plaintext)

**Convenience level: Maximum** 🚀 (works immediately on git push)