# modules/flake-parts/modules.nix
# Enables the flake.modules.* namespace for dendritic pattern modules
#
# This provides:
# - flake.modules.nixos.<name> - NixOS system modules
# - flake.modules.darwin.<name> - nix-darwin modules
# - flake.modules.homeManager.<name> - Home Manager modules
#
# Feature modules define their configs here, then hosts compose them.
# Example:
#   flake.modules.nixos.shell = { pkgs, ... }: { programs.fish.enable = true; };
#   flake.modules.homeManager.shell = { ... }: { programs.starship.enable = true; };
#
# Hosts consume via:
#   imports = [ inputs.self.modules.nixos.shell ];
{ lib, config, ... }:
let
  # Module type that accepts any valid NixOS/Darwin/HM module
  # (function or attrset with imports/options/config)
  moduleType = lib.types.deferredModule;
in
{
  options.flake.modules = {
    nixos = lib.mkOption {
      type = lib.types.attrsOf moduleType;
      default = { };
      description = "NixOS system modules organized by feature";
    };

    darwin = lib.mkOption {
      type = lib.types.attrsOf moduleType;
      default = { };
      description = "nix-darwin modules organized by feature";
    };

    homeManager = lib.mkOption {
      type = lib.types.attrsOf moduleType;
      default = { };
      description = "Home Manager modules organized by feature";
    };
  };

  # flake-parts automatically exposes flake.modules at self.modules
  # So hosts can use: imports = [ inputs.self.modules.nixos.shell ];
}
