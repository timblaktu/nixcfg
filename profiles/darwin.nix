# Darwin-specific profile for home manager
{ config, lib, pkgs, ... }:

{
  # Darwin-specific packages
  home.packages = with pkgs; [
    # macOS specific utilities
    coreutils  # GNU coreutils
    findutils  # GNU find
    gnugrep    # GNU grep
    gnused     # GNU sed
    
    # Mac specific tools
    mas        # Mac App Store CLI
    m-cli      # macOS CLI
    
    # Additional utilities
    terminal-notifier
  ];
  
  # Mac-specific environment variables
  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_AUTO_UPDATE = "1";
  };
  
  # Darwin-specific shell configuration
  programs.bash.initExtra = ''
    # Add Homebrew paths
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  '';
  
  programs.zsh.initExtra = ''
    # Add Homebrew paths
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  '';
}
