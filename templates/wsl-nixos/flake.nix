{
  description = "WSL NixOS Configuration Template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import shared WSL modules from nixcfg
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { self, nixpkgs, nixos-wsl, nixcfg, ... }: {
    nixosConfigurations.my-wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nixcfg.nixosModules.wsl-base # Common WSL system configuration
        ./hardware-config.nix
        {
          # System configuration
          wslCommon = {
            hostname = "my-wsl";
            defaultUser = "myuser"; # Change this to your username
            sshPort = 2222;
            userGroups = [ "wheel" "dialout" ];
            authorizedKeys = [
              # Add your SSH public keys here
              # "ssh-ed25519 AAAA... user@host"
            ];
          };

          # Additional system packages
          environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            vim
            git
            wget
            curl
          ];

          system.stateVersion = "24.11";
        }
      ];
    };
  };
}
