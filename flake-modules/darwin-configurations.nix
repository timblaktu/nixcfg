# flake-modules/darwin-configurations.nix
# macOS system configurations using nix-darwin
{ inputs, self, withSystem, ... }: {
  flake = {
    darwinConfigurations = {
      # Example macOS configuration
      macbook-air = withSystem "aarch64-darwin" ({ pkgs, ... }:
        inputs.darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            # Global config for nixpkgs
            { nixpkgs.config.allowUnfree = true; }

            # Base configuration
            ../hosts/macbook-air

            # User environment managed by standalone Home Manager
            # Deploy with: home-manager switch --flake '.#tim@macbook-air'

            # Secrets management
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
