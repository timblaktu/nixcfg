# Shell configuration
{ config, lib, pkgs, ... }:

{
  # ZSH configuration
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      share = true;
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "history"
        "npm"
        "python"
        "rust"
      ];
      theme = "robbyrussell";
    };
    
    shellAliases = {
      ll = "ls -la";
      la = "ls -a";
      home-switch = "home-manager switch";
      hm = "home-manager";
      nixr = "sudo nixos-rebuild";
      nixs = "sudo nixos-rebuild switch";
      nixb = "sudo nixos-rebuild boot";
      nixc = "cd ~/.config/nixpkgs";
    };
    
    initExtra = ''
      # Additional shell initialization
      bindkey -v  # Vi mode
      bindkey '^R' history-incremental-search-backward
      
      # Custom functions
      function mkcd() {
        mkdir -p "$1" && cd "$1"
      }
    '';
  };
  
  # Bash configuration (as fallback)
  programs.bash = {
    enable = true;
    historySize = 10000;
    historyFileSize = 100000;
    historyControl = ["ignoredups" "ignorespace"];
    shellAliases = config.programs.zsh.shellAliases;
  };
  
  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      directory = {
        truncation_length = 5;
        truncate_to_repo = true;
      };
      nix_shell = {
        symbol = "❄️ ";
        format = "via [$symbol$state]($style) ";
      };
    };
  };
  
  # Direnv for per-directory environment variables
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
