# modules/flake-parts/nixos-configurations.nix
# Simplified NixOS system configurations - all config in hosts/*/default.nix
{ inputs, self, withSystem, ... }: {
  flake = {
    nixosConfigurations = {
      # mbp: Dendritic pattern - module defined in modules/hosts/mbp [N]/
      mbp = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.mbp
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );

      # potato: Dendritic pattern - module defined in modules/hosts/potato [N]/
      potato = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.potato
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );

      # pa161878-nixos: Dendritic pattern - module defined in modules/hosts/pa161878-nixos/
      pa161878-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.pa161878-nixos
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "pa161878-nixos";
          };
        }
      );

      # thinky-nixos: Dendritic pattern - module defined in modules/hosts/thinky-nixos/
      thinky-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.thinky-nixos
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "thinky-nixos";
          };
        }
      );

      # nixos-wsl-minimal: Dendritic pattern - module defined in modules/hosts/nixos-wsl-minimal [N]/
      nixos-wsl-minimal = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Keep allowUnfree = false for distribution
            self.modules.nixos.nixos-wsl-minimal
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nixos-wsl-tiger-team: Tiger team distribution image
      # module defined in modules/hosts/nixos-wsl-tiger-team [N]/
      nixos-wsl-tiger-team = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # allowUnfree set by wsl-tiger-team module (true)
            self.modules.nixos.nixos-wsl-tiger-team
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );
    };
  };
}
