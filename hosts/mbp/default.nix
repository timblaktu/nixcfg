# MacBook Pro specific configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking = {
    hostName = "mbp";
    useNetworkd = true;
    firewall.enable = false;
    wireless = {
      enable = true;
      networks = {
        # Add your wireless networks here
        # "NetworkName" = {
        #   psk = "password";
        # };
      };
    };
  };

  systemd.network.enable = true;

  # Console configuration
  console = {
    packages = [pkgs.kbd pkgs.terminus_font pkgs.powerline-fonts];
    font = "${pkgs.powerline-fonts}/share/consolefonts/ter-powerline-v20b.psf.gz";
    keyMap = "us";
    colors = [
      "002b36" # base03, background
      "dc322f" # red
      "859900" # green
      "b58900" # yellow
      "268bd2" # blue
      "d33682" # magenta
      "2aa198" # cyan
      "eee8d5" # base2, foreground
      "073642" # base02, bright background
      "cb4b16" # bright red
      "586e75" # base01, bright green
      "657b83" # base00, bright yellow
      "839496" # base0, bright blue
      "6c71c4" # violet, bright magenta
      "93a1a1" # base1, bright cyan
      "fdf6e3" # base3, bright foreground
    ];
  };

  # User configuration (overrides common)
  users.users.tim = {
    isNormalUser = true;
    shell = lib.mkForce pkgs.zsh;
    extraGroups = ["wheel" "networkmanager" "audio" "video"];
    packages = with pkgs; [
      inputs.home-manager.packages.${pkgs.system}.default
    ];
  };

  # Sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Enable GnuPG agent
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Zsh configuration
  programs.zsh = {
    enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
    enableGlobalCompInit = true;
    enableLsColors = true;
    setOptions = [
      "EXTENDED_HISTORY"
      "HIST_IGNORE_DUPS"
      "SHARE_HISTORY"
      "HIST_FCNTL_LOCK"
    ];
    interactiveShellInit = ''
      bindkey -v
      bindkey '^R' history-incremental-search-backward
    '';
    promptInit = ''
      autoload -U promptinit
      promptinit
      prompt suse
      setopt prompt_sp
      setopt prompt_subst
      autoload -Uz vcs_info
      precmd () { vcs_info }
      zstyle ':vcs_info:*' formats ' %s(%F{red}%b%f)'
      PS1='%n@%m %F{red}%/%f$vcs_info_msg_0_ $ '
    '';
    histSize = 10000;
  };

  # Additional system packages
  environment = {
    systemPackages = with pkgs; [
      kbd
      terminus_font
      powerline-fonts
    ];
    variables = {
      EDITOR = "nvim";
    };
  };

  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = lib.mkForce true;
    };
  };

  # Disable X server and related services for this config
  services.xserver.enable = false;
  services.printing.enable = false;
  services.pipewire = {
    enable = false;
    pulse.enable = false;
  };

  # Enable touchpad support
  services.libinput.enable = true;
}
