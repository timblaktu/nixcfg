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
            
            # Home-manager module
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.tim = { 
                imports = [
                  ../home/modules/base.nix
                  ../home/modules/mcp-servers.nix
                ];
                # Pass configuration to homeBase
                homeBase = { };
              };
              home-manager.extraSpecialArgs = { 
                inherit inputs;
                inherit (inputs) nixpkgs-stable;
              };
            }
            
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
