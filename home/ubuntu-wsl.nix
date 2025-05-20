# Standalone home-manager configuration for thinky-ubuntu (non-NixOS system)
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Base WSL profile
    ./profiles/wsl.nix
  ];
  
  # Ubuntu-specific configurations
  home.packages = with pkgs; [
    # Tools to ensure NixOS packages integrate well with Ubuntu
    nix-index
    nix-prefetch-scripts
    
    # Add tools not provided by Ubuntu base system
    gnupg
  ];
  
  # Ubuntu environment-specific configurations
  home.sessionVariables = {
    # Ensure Nix binaries are in path on Ubuntu
    NIX_PATH = "$HOME/.nix-defexpr/channels:$NIX_PATH";
  };
  
  # Ubuntu-specific program configurations
  programs.bash.initExtra = ''
    # Source Nix environment if it exists
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  '';
  
  programs.zsh.initExtra = ''
    # Source Nix environment if it exists
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  '';
}
