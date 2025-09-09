# macOS configuration for MacBook Air
{ config, pkgs, ... }: {
  # System settings
  system.stateVersion = 4;
  
  # Basic macOS configuration
  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };
  };
  
  # Environment setup
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
  ];
  
  # Enable sudo with Touch ID
  security.pam.enableSudoTouchId = true;
  
  # Homebrew integration
  homebrew = {
    enable = true;
    brews = [
      "mas"  # Mac App Store CLI
    ];
    casks = [
      "rectangle"  # Window management
      "raycast"    # Spotlight replacement
    ];
  };
  
  # Services
  services = {
    nix-daemon.enable = true;
  };
  
  # Users
  users.users.tim = {
    name = "tim";
    home = "/Users/tim";
  };
}
