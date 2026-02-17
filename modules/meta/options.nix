# modules/meta/options.nix
# Read-only flake-level options for the dendritic pattern
#
# These options provide shared constants that are accessible across all
# flake-parts modules via the top-level `config` attribute.
#
# Usage in other flake-parts modules:
#   { config, ... }:
#   {
#     # Access via config
#     flake.modules.homeManager.shell = {
#       home.username = config.meta.username;
#     };
#   }
#
# Note: These are flake-level options, not NixOS/HM module options.
# They are evaluated once at flake build time, making them suitable
# for constants like the primary username.
{ lib, ... }:
{
  options.meta = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "tim";
      readOnly = true;
      description = ''
        Primary username for all configurations in this flake.

        This is the default user account created on NixOS/Darwin systems
        and the user for standalone Home Manager configurations.

        Read-only: This value is set at flake definition time and cannot
        be overridden by individual configurations.
      '';
    };

    homeDirectory = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      default = system:
        if lib.hasInfix "darwin" system
        then "/Users/tim"
        else "/home/tim";
      readOnly = true;
      description = ''
        Function to get home directory path based on system architecture.

        Usage: config.meta.homeDirectory "x86_64-linux" -> "/home/tim"
               config.meta.homeDirectory "aarch64-darwin" -> "/Users/tim"

        Read-only: Derived from username and follows platform conventions.
      '';
    };

    gitEmail = lib.mkOption {
      type = lib.types.str;
      default = "tim@timblaktu.com";
      readOnly = true;
      description = ''
        Primary git email for commits.
        Read-only: This should be consistent across all configurations.
      '';
    };

    gitName = lib.mkOption {
      type = lib.types.str;
      default = "Tim Black";
      readOnly = true;
      description = ''
        Primary git name for commits.
        Read-only: This should be consistent across all configurations.
      '';
    };
  };
}
