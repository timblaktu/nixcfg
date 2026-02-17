# modules/flake-parts/darwin-configurations.nix
# macOS system configurations using nix-darwin
#
# All Darwin hosts use the dendritic pattern:
# - Host modules are defined in modules/hosts/<name> [D]/
# - Modules define flake.modules.darwin.<name>
# - This file registers them as darwinConfigurations
{ inputs, self, withSystem, ... }: {
  flake = {
    darwinConfigurations = {
      # macbook-air: Dendritic pattern - module defined in modules/hosts/macbook-air [D]/
      # Deploy with: darwin-rebuild switch --flake '.#macbook-air'
      "macbook-air" = withSystem "aarch64-darwin" ({ pkgs, ... }:
        inputs.darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.darwin.macbook-air
            inputs.sops-nix.darwinModules.sops
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );
    };
  };
}
