# modules/hosts/nixos-dev-team [N]/nixos-dev-team.nix
# Dendritic host composition for nixos-dev-team (pure NixOS, no WSL)
#
# This is a DISTRIBUTION configuration for the dev team's generic NixOS image.
# It is a thin composition layer -- all real config lives in system-cli and
# individual feature modules.
#
# Features:
# - Full CLI dev stack (system-cli -> system-default -> system-minimal)
# - binfmt cross-compilation (aarch64)
# - Podman containers
# - Generic 'dev' user with SSH access
# - No WSL, no CrowdStrike, no Windows Terminal
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
    ];

    config = lib.mkMerge [
      # === Core Configuration ===
      {
        networking.hostName = "nixos-dev-team";

        # Generic username for distribution (not personal)
        systemDefault.userName = lib.mkDefault "dev";

        # Passwordless sudo for wheel group (standard for dev images)
        security.sudo.wheelNeedsPassword = lib.mkDefault false;

        # NOTE: nixpkgs.config.allowUnfree is set at the nixosConfiguration
        # registration level (nixos-configurations.nix), not here. Setting it
        # in the module causes assertion failures in VM tests where the test
        # framework provides an externally-created pkgs instance.

        # State version
        system.stateVersion = lib.mkDefault "24.11";
      }

      # === Dev Team Feature Flags ===
      {
        # Enable QEMU user-mode emulation for cross-arch builds (aarch64)
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
        boot.binfmt.preferStaticEmulators = true;
        boot.binfmt.registrations.aarch64-linux.matchCredentials = true;
        nix.settings.extra-platforms = [ "aarch64-linux" ];

        # Enable Podman container runtime
        systemCli.enablePodman = lib.mkDefault true;

        # Development utilities
        environment.systemPackages = with pkgs; [
          usbutils # lsusb
          kmod # lsmod, modprobe
        ];
      }
    ];
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
