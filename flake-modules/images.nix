# flake-modules/images.nix
# Image building configurations for deployment and distribution
# - WSL tarballs: Built using NixOS-WSL's tarballBuilder
# - VM images: Built using nixos-generators
{ inputs, self, withSystem, ... }: {
  flake = {
    # Image outputs for distribution
    images = {
      # WSL tarball for Windows colleague onboarding (CRITICAL)
      # Uses NixOS-WSL's tarballBuilder to create a .tar.gz for WSL import
      wsl-minimal = self.nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder or
        (throw "nixos-wsl-minimal configuration doesn't have tarballBuilder - ensure nixos-wsl module is imported");

      # qcow2 VM image for testing (High priority)
      vm-minimal = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          format = "qcow";

          # Create a minimal NixOS configuration suitable for VM testing
          modules = [
            ({ config, lib, pkgs, ... }: {
              # Basic system configuration
              boot.loader.grub.enable = true;
              boot.loader.grub.device = "/dev/vda";

              # Minimal networking
              networking.hostName = "nixos-vm";
              networking.useDHCP = false;
              networking.interfaces.eth0.useDHCP = true;

              # Enable SSH for remote access
              services.openssh.enable = true;
              services.openssh.settings.PermitRootLogin = "yes";

              # Default user
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                initialPassword = "nixos";
              };

              # Essential packages
              environment.systemPackages = with pkgs; [
                vim
                git
                htop
              ];

              # Enable sudo without password for wheel
              security.sudo.wheelNeedsPassword = false;

              # Nix settings
              nix.settings.experimental-features = [ "nix-command" "flakes" ];

              system.stateVersion = "24.11";
            })
          ];
        }
      );
    };

    # Also expose as packages for easier building
    packages.x86_64-linux = {
      wsl-image = self.images.wsl-minimal;
      vm-image = self.images.vm-minimal;
    };
  };
}
