{
  description = "WSL NixOS Configuration Template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import shared WSL modules from nixcfg
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { self, nixpkgs, nixos-wsl, sops-nix, nixcfg, ... }: {
    nixosConfigurations.my-wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit nixos-wsl sops-nix; inputs = { inherit nixos-wsl sops-nix; }; };
      modules = [
        nixcfg.nixosModules.wsl-base # Common WSL system configuration (dendritic)
        ./hardware-config.nix
        {
          # WSL settings (dendritic module options)
          wsl-settings = {
            hostname = "my-wsl";
            defaultUser = "myuser"; # Change this to your username
            sshPort = 2222;
            userGroups = [ "wheel" "dialout" ];
            sshAuthorizedKeys = [
              # Add your SSH public keys here
              # "ssh-ed25519 AAAA... user@host"
            ];
            # SOPS-nix secrets (optional, disable if not using)
            sops.enable = false;
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
