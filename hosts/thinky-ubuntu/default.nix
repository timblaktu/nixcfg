# Ubuntu WSL configuration for Home Manager only
{ config, lib, pkgs, ... }:

{
  # This configuration is for standalone Home Manager on Ubuntu WSL

  # WSL-specific packages that might be needed - only add ones not in the wsl profile
  home.packages = with pkgs; [
    # wslu is already included in the WSL profile, so we don't need to add it here
  ];

  # System-wide aliases for WSL
  programs.bash.shellAliases = lib.mkForce {
    explorer = "explorer.exe .";
    code = "code.exe";
    code-insiders = "code-insiders.exe";
  };

  # Add the same to zsh if used
  programs.zsh.shellAliases = lib.mkForce {
    explorer = "explorer.exe .";
    code = "code.exe";
    code-insiders = "code-insiders.exe";
  };

  # WSL-specific environment variables
  home.sessionVariables = {
    WSL_DISTRO = lib.mkForce "Ubuntu";  # Use mkForce to override flake.nix setting
    HOSTNAME = "thinky-ubuntu"; # Set hostname as environment variable
  };
}
