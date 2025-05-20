# WSL profile
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ../common/shell.nix
    ../common/git.nix
    ../common/neovim.nix
    ../common/tmux.nix
    ./development.nix
  ];
  
  # WSL-specific home manager configurations
  home.packages = with pkgs; [
    # Windows interop tools
    wsl-open # Open files in Windows applications from WSL
    
    # Extra tools useful in WSL environment
    fuse # For mounting remote filesystems
    
    # Development tools that work well in WSL
    vscode-fhs # For VS Code Remote
  ];
  
  # WSL-specific environment variables
  home.sessionVariables = {
    # Use Windows browser for opening URLs
    BROWSER = "wslview";
    # Improve WSL/Windows interoperability
    WSLENV = "BROWSER:WSL_INTEROP:WSL_DISTRO_NAME:PATH/up";
  };
  
  # WSL-specific shell aliases
  programs.bash.shellAliases = {
    # Windows command equivalents
    notepad = "notepad.exe";
    cmd = "cmd.exe /c";
    pwsh = "powershell.exe";
    # Navigate to Windows home directory
    winhome = "cd /mnt/c/Users/$(wslvar USERNAME)";
  };
  
  programs.zsh.shellAliases = {
    # Windows command equivalents
    notepad = "notepad.exe";
    cmd = "cmd.exe /c";
    pwsh = "powershell.exe";
    # Navigate to Windows home directory
    winhome = "cd /mnt/c/Users/$(wslvar USERNAME)";
  };
}
