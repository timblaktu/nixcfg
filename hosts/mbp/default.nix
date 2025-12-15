# MacBook Pro specific configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Base module configuration
  base = {
    userName = "tim";
    sshPasswordAuth = lib.mkDefault true;
    requireWheelPassword = lib.mkDefault false;
    userGroups = lib.mkDefault [ "wheel" "networkmanager" "audio" "video" ];
    additionalPackages = lib.mkDefault (with pkgs; [
      kbd
      terminus_font
      powerline-fonts
    ]);
    consolePackages = lib.mkDefault (with pkgs; [
      kbd
      terminus_font
      powerline-fonts
    ]);
    additionalShellAliases = lib.mkDefault { };
  };

  # Hostname
  networking = {
    hostName = "mbp";
    useNetworkd = lib.mkDefault true;
    firewall.enable = lib.mkDefault false;
    wireless = {
      enable = lib.mkDefault true;
      networks = {
        "SUMMIT-VIS" = {
          psk = "summ1tv1s1t0r";
        };
        "zarf" = {
          psk = "c0rnp177a";
        };
      };
    };
  };

  systemd.network.enable = lib.mkDefault true;

  # Configure systemd-networkd to send hostname in DHCP requests
  systemd.network.networks."40-ethernet" = {
    matchConfig.Name = "enp0s10";
    networkConfig = {
      DHCP = "yes";
      IPv6PrivacyExtensions = "kernel";
    };
    dhcpV4Config = {
      SendHostname = true;
      Hostname = "mbp";
    };
  };

  # Console configuration
  console = {
    packages = [ pkgs.kbd pkgs.terminus_font pkgs.powerline-fonts ];
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
    isNormalUser = lib.mkDefault true;
    extraGroups = lib.mkDefault [ "wheel" "users" "audio" "video" ];
    packages = lib.mkDefault (with pkgs; [
      inputs.home-manager.packages.${pkgs.system}.default
    ]);
  };

  # Sudo without password for wheel group
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

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
    enable = lib.mkDefault true;
    ports = lib.mkDefault [ 22 ];
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkForce true; # mkForce is intentional here
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
  # Memory management optimizations
  boot.kernel.sysctl."vm.swappiness" = 10;
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  services.libinput.enable = true;

  # System state version
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
