# modules/hosts/nixos-dev-team [N]/nixos-dev-team.nix
# Dendritic host composition for nixos-dev-team (pure NixOS, no WSL)
#
# This is a DISTRIBUTION configuration for the dev team's generic NixOS image.
# It is a thin composition layer -- all real config lives in the shared
# dev-team module (binfmt, Podman, Claude Code, usbutils, kmod).
#
# Features (via dev-team module):
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Claude Code enterprise
# - Generic 'dev' user with SSH access
# - No WSL, no CrowdStrike, no Windows Terminal
#
# Image outputs (via image.modules / system.build.images):
# - Proxmox VMA: nix build '.#nixosConfigurations.nixos-dev-team.config.system.build.images.proxmox'
#   Import: qmrestore vzdump-qemu-*.vma.zst VMID --storage POOL
#
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#nixos-dev-team'
# VM test: nix build '.#checks.x86_64-linux.vm-dev-team-stack'
{ config, lib, inputs, ... }:
{
  # === NixOS System Module ===
  flake.modules.nixos.nixos-dev-team = { config, lib, pkgs, ... }: {
    imports = [
      # Hardware configuration (generic VM)
      ./_hardware-config.nix
      # System CLI layer (chains: system-minimal -> system-default -> system-cli)
      inputs.self.modules.nixos.system-cli
      # Shared dev team base (binfmt + Podman + Claude Code + usbutils + kmod)
      inputs.self.modules.nixos.dev-team
    ];

    config = {
      networking.hostName = "nixos-dev-team";

      # NOTE: nixpkgs.config.allowUnfree is set at the nixosConfiguration
      # registration level (nixos-configurations.nix), not here. Setting it
      # in the module causes assertion failures in VM tests where the test
      # framework provides an externally-created pkgs instance.

      # === Image Outputs ===
      # image.modules overlays produce format-specific images via
      # system.build.images without polluting this base config.
      # The builder modules (proxmox-image.nix, etc.) are registered
      # automatically by nixpkgs' images.nix framework.

      # Proxmox VE (VMA) image
      image.modules.proxmox = {
        imports = [ inputs.self.modules.nixos.proxmox-image-config ];
        proxmox.qemuConf.cores = 4;
        proxmox.qemuConf.memory = 4096;
        proxmox.qemuConf.name = "nixos-dev-team";
      };
    };
  };

  # === Configuration Registration ===
  # Registration is done in flake-parts/nixos-configurations.nix
  # using lib.nixosSystem with self.modules.nixos.nixos-dev-team
  #
  # Home Manager configuration is NOT bundled in this host module.
  # Users apply HM config independently using this flake's feature modules
  # (shell, git, tmux, neovim, development-tools, etc.).
  # The VM test (vm-dev-team-stack) demonstrates the full HM integration.
}
