# modules/system/settings/dev-team/dev-team.nix
# Platform-agnostic dev team NixOS module [NDnd]
#
# Provides:
#   flake.modules.nixos.dev-team - Shared dev team system config
#
# This is the platform-agnostic base for dev team configurations.
# It imports system-cli and adds binfmt cross-compilation, Podman,
# Claude Code enterprise, and standard dev utilities.
#
# Platform-specific layers import this module and add their own config:
#   - wsl-dev-team: adds WSL enterprise base, USBIP, terminal profile
#   - nixos-dev-team: adds VM hardware config
#   - nixos-proxmox-dev-team: adds Proxmox image output
#
# Does NOT set nixpkgs.config.allowUnfree (must stay at registration
# level for VM test compatibility).
#
# Does NOT import system-cli -- consumers must co-import a system type.
# NixOS deferred modules (flake-parts pattern) are not deduplicated by
# reference identity, so importing system-cli here AND in wsl-enterprise
# causes "option already declared" errors. Instead:
#   - nixos-dev-team imports system-cli + dev-team
#   - wsl-dev-team imports wsl-enterprise (has system-cli) + dev-team
#
# Priority layering:
#   dev-team uses mkDefault (1000) for all values -- platform layers
#   and hosts can override with bare values (100) or mkForce (50).
#
# Usage:
#   # In a host module (must co-import a system type):
#   imports = [
#     inputs.self.modules.nixos.system-cli  # or wsl-enterprise, etc.
#     inputs.self.modules.nixos.dev-team
#   ];
{ ... }:
{
  flake.modules.nixos.dev-team = { config, lib, pkgs, inputs, ... }: {

    config = {
      # === User & System Defaults ===
      # Generic username for distribution (not personal)
      systemDefault.userName = lib.mkDefault "dev";

      # Passwordless sudo for wheel group (standard for dev images)
      security.sudo.wheelNeedsPassword = lib.mkDefault false;

      # State version
      system.stateVersion = lib.mkDefault "24.11";

      # === Cross-Architecture Build Support (binfmt + QEMU) ===
      boot.binfmt.emulatedSystems = lib.mkDefault [ "aarch64-linux" ];
      boot.binfmt.preferStaticEmulators = lib.mkDefault true;
      boot.binfmt.registrations.aarch64-linux.matchCredentials = lib.mkDefault true;
      nix.settings.extra-platforms = lib.mkDefault [ "aarch64-linux" ];

      # === Feature Flags ===
      # Enable Podman container runtime
      systemCli.enablePodman = lib.mkDefault true;

      # Enable Claude Code enterprise managed settings at /etc/claude-code/
      systemCli.enableClaudeCodeEnterprise = lib.mkDefault true;

      # === Development Utilities ===
      environment.systemPackages = with pkgs; [
        usbutils # lsusb -- USB device enumeration (Jetson flashing, usbipd workflows)
        kmod # lsmod, modprobe, modinfo -- kernel module management
      ];
    };
  };
}
