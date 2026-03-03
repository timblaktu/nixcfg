# modules/programs/pulumi/pulumi.nix
# Pulumi Infrastructure-as-Code CLI tooling
#
# Provides:
#   flake.modules.homeManager.pulumi - Pulumi CLI with optional ESC and plugins
#
# Features:
#   - Pulumi CLI installation
#   - Optional Pulumi ESC (Environments, Secrets, Configuration)
#   - User-specified provider/language plugins from nixpkgs
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.pulumi ];
#   pulumi.enable = true;
{ config, lib, inputs, ... }:
{
  flake.modules = {
    homeManager.pulumi = { config, lib, pkgs, ... }:
      let
        cfg = config.pulumi;
      in
      {
        options.pulumi = {
          enable = lib.mkEnableOption "Pulumi Infrastructure-as-Code CLI";

          enableEsc = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install pulumi-esc (Environments, Secrets, Configuration)";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = ''
              Additional Pulumi provider or language packages from nixpkgs.
              Example: [ pkgs.pulumi-language-python pkgs.pulumiPackages.pulumi-aws-native ]
            '';
          };
        };

        config = lib.mkIf cfg.enable {
          home.packages =
            [ pkgs.pulumi ]
            ++ lib.optional cfg.enableEsc pkgs.pulumi-esc
            ++ cfg.plugins;
        };
      };
  };
}
