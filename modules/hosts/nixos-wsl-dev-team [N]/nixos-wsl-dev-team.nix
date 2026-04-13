# modules/hosts/nixos-wsl-dev-team [N]/nixos-wsl-dev-team.nix
# Dendritic host composition for nixos-wsl-dev-team (WSL distribution image)
#
# This is a DISTRIBUTION configuration for the dev team's WSL tarball.
# It is a thin composition layer -- all real config lives in wsl-dev-team module.
#
# Features (via wsl-dev-team -> wsl-enterprise):
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - WSL integration (wsl.conf, users, SSH)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Claude Code enterprise managed settings
# - Generic 'dev' user with setup-username bootstrap script
#
# Build tarball: nix build '.#nixosConfigurations.nixos-wsl-dev-team.config.system.build.tarballBuilder'
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#nixos-wsl-dev-team'
{ config, lib, inputs, ... }:
{
  # === NixOS System Module ===
  # No Home Manager module -- the .wsl tarball is system-only.
  # Users apply HM config after importing the image by using this flake's
  # home-dev-team module in their own home-manager configuration.
  flake.modules.nixos.nixos-wsl-dev-team = { config, lib, pkgs, ... }: {
    imports = [
      # Hardware configuration (WSL2-specific)
      ./_hardware-config.nix
      # Dev team layer (chains: wsl-enterprise -> system-cli + wsl)
      inputs.self.modules.nixos.wsl-dev-team
    ];

    # Host-specific overrides (minimal -- layer modules do the work)
    # None needed for distribution image.
  };

  # === Configuration Registration ===
  # Registration is done in flake-parts/nixos-configurations.nix
  # using lib.nixosSystem with self.modules.nixos.nixos-wsl-dev-team
  #
  # This host has NO Home Manager configuration -- it's designed as a
  # distribution image. Users add HM config after installing the tarball.
}
