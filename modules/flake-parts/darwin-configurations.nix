# modules/flake-parts/darwin-configurations.nix
# macOS system configurations using nix-darwin
#
# All Darwin hosts use the dendritic pattern:
# - Host modules are defined in modules/hosts/<name> [D]/
# - Modules define flake.modules.darwin.<name>
# - This file registers them as darwinConfigurations
{ inputs, self, withSystem, ... }:
let
  # Personal-Mac username for the PowerBook (gitignored local-username.nix;
  # "user" placeholder off-hardware). Mirrors the host module's own lookup so the
  # HM user attr and homeMinimal match system.primaryUser / systemDefault.userName.
  powerbookUsernameFile = "${self}/modules/hosts/powerbook [D]/local-username.nix";
  powerbookUsername =
    if builtins.pathExists powerbookUsernameFile
    then import powerbookUsernameFile
    else "user";
in
{
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

      # powerbook: Tim's personal Apple Silicon Mac (Plan 001 T5 skeleton).
      # System module in modules/hosts/powerbook [D]/. Personal HM is wired here
      # (integrated home-manager.darwinModules pattern, mirroring nixcfg-work's
      # corp-darwin-dev-team): the platform-neutral personal CLI tier (home-cli)
      # + nixcfg's thin macOS HM layer (home-darwin). NOT the corporate
      # corp-dev-team tier (that lives on the corp host in nixcfg-work).
      # Deploy with: darwin-rebuild switch --flake '.#powerbook'
      "powerbook" = withSystem "aarch64-darwin" ({ pkgs, ... }:
        inputs.darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            {
              nixpkgs.config.allowUnfree = true;
              # nixcfg's overlay provides custom packages the HM stack references
              # (e.g. home-default's basePackages -> markitdown). HM uses
              # useGlobalPkgs, so it inherits this system overlay. Mirrors the
              # corp-darwin-dev-team wiring in nixcfg-work.
              nixpkgs.overlays = [ self.overlays.default ];
            }
            self.modules.darwin.powerbook
            inputs.sops-nix.darwinModules.sops
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-bak";
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit (inputs) nixpkgs-stable;
              };
              home-manager.users.${powerbookUsername} = {
                imports = [
                  # Platform-neutral personal CLI tier (shell/git/tmux/neovim/
                  # yazi + CLI packages). T5: home-cli only; home-desktop / GUI
                  # tiers and personal apps are deferred to T5b.
                  self.modules.homeManager.home-cli
                  # Thin macOS HM layer (personal analogue of corp-wsl's home-wsl).
                  self.modules.homeManager.home-darwin
                ];
                homeMinimal.username = powerbookUsername;
                homeMinimal.homeDirectory = "/Users/${powerbookUsername}";
              };
            }
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
