# Server profile for home manager
{ config, lib, pkgs, ... }:

{
  # Server-specific packages
  home.packages = with pkgs; [
    # Monitoring tools
    htop
    bottom
    iftop
    iotop
    lsof
    
    # Network tools
    nmap
    tcpdump
    mtr
    
    # System tools
    lshw
    pciutils
    usbutils
    
    # Useful utilities
    tmux
    screen
    rsync
  ];
  
  # Server-specific tmux configuration
  programs.tmux = {
    enable = true;
    shortcut = "a";
    terminal = "screen-256color";
    historyLimit = 10000;
    escapeTime = 0;
    keyMode = "vi";
    extraConfig = ''
      # Additional server-specific tmux config
      set -g status-bg black
      set -g status-fg yellow
      
      # Monitor activity
      setw -g monitor-activity on
      set -g visual-activity on
      
      # Auto-rename windows based on current process
      setw -g automatic-rename on
    '';
  };
}
