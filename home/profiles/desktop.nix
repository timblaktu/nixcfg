# Desktop profile with GUI applications
{ config, lib, pkgs, ... }:

{
  imports = [
    ../common/shell.nix
    ../common/git.nix
    ../common/neovim.nix
    ../common/tmux.nix
  ];
  
  # GUI applications
  home.packages = with pkgs; [
    # Web browsers
    firefox
    chromium
    
    # Communication
    slack
    discord
    element-desktop
    
    # Media
    vlc
    mpv
    gimp
    inkscape
    
    # PDF viewers and document tools
    libreoffice
    evince
    okular
    
    # Development tools
    vscode
    jetbrains.idea-community
    insomnia # API client
    
    # System tools
    alacritty
    kitty
    rofi
    
    # File managers
    pcmanfm
    ranger
    
    # Utility
    pavucontrol
    flameshot # Screenshots
    
    # Fonts
    (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" "Hack" ]; })
  ];
  
  # Terminal emulators
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal.family = "JetBrainsMono Nerd Font";
        size = 11;
      };
      window = {
        padding = {
          x = 10;
          y = 10;
        };
      };
    };
  };
  
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    settings = {
      scrollback_lines = 10000;
      enable_audio_bell = false;
      window_padding_width = 10;
    };
  };
  
  # Firefox
  programs.firefox = {
    enable = true;
    profiles.default = {
      settings = {
        "browser.uidensity" = 0;
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "distribution.searchplugins.defaultLocale" = "en-US";
        "general.useragent.locale" = "en-US";
        "browser.bookmarks.showMobileBookmarks" = true;
      };
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        privacy-badger
        bitwarden
        darkreader
      ];
    };
  };
  
  # VSCode
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      vscodevim.vim
      jnoortheen.nix-ide
      ms-python.python
      rust-lang.rust-analyzer
      matklad.rust-analyzer
      golang.go
      esbenp.prettier-vscode
      dbaeumer.vscode-eslint
      ms-azuretools.vscode-docker
      github.copilot
    ];
    userSettings = {
      "editor.fontFamily" = "'JetBrainsMono Nerd Font', 'Droid Sans Mono', 'monospace'";
      "editor.fontSize" = 14;
      "editor.lineHeight" = 24;
      "editor.tabSize" = 2;
      "editor.formatOnSave" = true;
      "files.autoSave" = "afterDelay";
      "workbench.colorTheme" = "Dracula";
      "vim.useSystemClipboard" = true;
      "vim.enableNeovim" = true;
      "terminal.integrated.shell.linux" = "${pkgs.zsh}/bin/zsh";
    };
  };
  
  # Configure fonts
  fonts.fontconfig.enable = true;
  
  # Desktop notifications
  services.dunst = {
    enable = true;
    settings = {
      global = {
        font = "JetBrainsMono Nerd Font 10";
        markup = "full";
        format = "<b>%s</b>\\n%b";
        sort = true;
        indicate_hidden = true;
        alignment = "left";
        show_age_threshold = 60;
        word_wrap = true;
        ignore_newline = false;
        width = 300;
        height = 300;
        offset = "10x30";
        transparency = 0;
        idle_threshold = 120;
        monitor = 0;
        follow = "mouse";
        sticky_history = true;
        history_length = 20;
        show_indicators = true;
        line_height = 0;
        separator_height = 2;
        padding = 8;
        horizontal_padding = 8;
        separator_color = "frame";
        startup_notification = false;
        frame_width = 2;
      };
    };
  };
  
  # Enable screen locking
  services.screen-locker = {
    enable = true;
    lockCmd = "${pkgs.i3lock}/bin/i3lock -n -c 000000";
    inactiveInterval = 10;
  };
  
  # Automatic screen brightness adjustment
  services.redshift = {
    enable = true;
    latitude = "37.7749";  # San Francisco (example)
    longitude = "-122.4194";
    temperature = {
      day = 6500;
      night = 3000;
    };
  };
}
