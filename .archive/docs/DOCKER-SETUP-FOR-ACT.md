# Docker Setup for Act Integration

## Option A: Enable Docker in NixOS (Recommended)

Add to your `hosts/thinky-nixos/default.nix`:

```nix
{
  # Docker configuration for act support
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };
  
  # Add user to docker group
  base = {
    userName = "tim";
    userGroups = [ "wheel" "dialout" "docker" ];  # Add docker group
    # ... rest of existing config
  };
}
```

Then rebuild and reboot:
```bash
sudo nixos-rebuild switch --flake '.#thinky-nixos'
sudo reboot
```

## Option B: Docker Desktop WSL Integration

If you prefer Docker Desktop on Windows:

1. Install Docker Desktop on Windows host
2. Enable WSL2 integration in Docker Desktop settings
3. Select the "NixOS" distribution for integration
4. Docker socket will be available at standard location

## Testing After Docker Setup

Once Docker is running, test act functionality:

```bash
# Verify Docker is working
docker run hello-world

# Test act with fast jobs
act -j verify-sops
act -j audit-permissions

# Test comprehensive jobs  
act -j gitleaks
act -j trufflehog

# Test git hooks
git add -A
git commit -m "test commit"  # Should run pre-commit hook
```

## Expected Performance (from ACT.md analysis)

- **verify-sops**: ~5 seconds
- **audit-permissions**: ~3 seconds  
- **gitleaks**: ~30 seconds first run, ~10 seconds cached
- **trufflehog**: ~45 seconds first run, ~15 seconds cached

## Troubleshooting

If Docker setup fails:
- Check WSL2 is enabled: `wsl --version`
- Verify user in docker group: `groups $USER`
- Check Docker daemon: `systemctl status docker`
- Test Docker socket: `ls -la /var/run/docker.sock`