# modules/hosts/nixos-dev-team-ec2 [N]/nixos-dev-team-ec2.nix
# Dendritic host composition for nixos-dev-team-ec2 (x86_64 EC2 instance)
#
# This is a DISTRIBUTION configuration for the dev team's EC2 AMI (x86_64).
# It composes the platform-agnostic dev-team module with EC2-specific runtime
# config (ENA drivers, SSM agent, serial console, GRUB, growPartition).
#
# Features (via dev-team module):
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Claude Code enterprise
# - Generic 'dev' user with SSH access
#
# EC2 runtime (via amazon-image.nix):
# - ENA network driver, NVMe timeout tuning
# - SSM agent for remote management
# - EC2 metadata service, cloud-init via user-data
# - Serial console on ttyS0
# - GRUB with UEFI boot
#
# Image outputs (via image.modules / system.build.images):
# - Amazon AMI: nix build '.#nixosConfigurations.nixos-dev-team-ec2.config.system.build.images.amazon'
#   Register: coldsnap upload result/*.img && aws ec2 register-image ...
#
# See also: nixos-dev-team-graviton (aarch64 variant)
{ config, lib, inputs, ... }:
{
  # === NixOS System Module ===
  flake.modules.nixos.nixos-dev-team-ec2 = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      # EC2 runtime config: ENA, SSM agent, serial console, GRUB, growPartition
      (modulesPath + "/virtualisation/amazon-image.nix")
      # System CLI layer (chains: system-minimal -> system-default -> system-cli)
      inputs.self.modules.nixos.system-cli
      # Shared dev team base (binfmt + Podman + Claude Code + usbutils + kmod)
      inputs.self.modules.nixos.dev-team
    ];

    config = {
      networking.hostName = "nixos-dev-team-ec2";

      # UEFI boot for modern EC2 instance types (Nitro-based)
      ec2.efi = true;

      # NOTE: nixpkgs.config.allowUnfree is set at the nixosConfiguration
      # registration level (nixos-configurations.nix), not here.

      # === Image Outputs ===
      # image.modules overlays produce format-specific images via
      # system.build.images without polluting this base config.

      # Amazon EC2 AMI (raw format for coldsnap upload)
      image.modules.amazon = {
        imports = [ inputs.self.modules.nixos.amazon-image-config ];
      };
    };
  };

  # === Configuration Registration ===
  # Registration is done in flake-parts/nixos-configurations.nix
  # using lib.nixosSystem with self.modules.nixos.nixos-dev-team-ec2
  #
  # Home Manager configuration is NOT bundled in this host module.
  # Users apply HM config independently using this flake's feature modules.
}
