# flake-modules/nixos-configurations.nix
# Simplified NixOS system configurations - all config in hosts/*/default.nix
{ inputs, self, withSystem, ... }: {
  flake = {
    nixosConfigurations = {
      mbp = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ../hosts/mbp ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      potato = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [ ../hosts/potato ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
          };
        }
      );
      
      thinky-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ../hosts/thinky-nixos ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable mcp-servers-nix;
            wslHostname = "tblack-t14-nixos";
          };
        }
      );
      
      nixos-wsl-minimal = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ../hosts/nixos-wsl-minimal ];
          specialArgs = {
            inherit inputs;
          };
        }
      );
    };
  };
}