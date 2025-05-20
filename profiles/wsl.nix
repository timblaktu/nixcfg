# WSL-specific profile for home manager
{ config, lib, pkgs, ... }:

{
  # WSL-specific packages
  home.packages = with pkgs; [
    wslu
    
    # Additional tools useful in WSL
    dos2unix  # Provides dos2unix, unix2dos, mac2unix, and unix2mac commands
    usbutils
  ];
  
  # WSL-specific configuration
  home.sessionVariables = {
    WSL_INTEROP = lib.mkDefault "/run/WSL/";
    DISPLAY = lib.mkDefault ":0";
  };
  
  # Additional shell aliases for WSL
  programs.bash.shellAliases = lib.mkDefault {
    explorer = "explorer.exe .";
    code = "code.exe";
  };
  
  programs.zsh.shellAliases = lib.mkDefault {
    explorer = "explorer.exe .";
    code = "code.exe";
  };
}
