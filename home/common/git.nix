# Git configuration
{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Tim Black";
    userEmail = "tim@timblack.net";
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      color.ui = true;
      merge = {
        conflictstyle = "diff3";
        tool = "vimdiff";
      };
      diff = {
        colorMoved = "default";
        tool = "vimdiff";
      };
    };
    
    aliases = {
      st = "status";
      ci = "commit";
      co = "checkout";
      br = "branch";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
    };
    
    ignores = [
      ".DS_Store"
      "*.swp"
      "*~"
      ".direnv/"
      "result"
      "result-*"
    ];
    
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
      };
    };
  };
  
  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
      prompt = "enabled";
    };
  };
  
  # Install additional Git-related tools
  home.packages = with pkgs; [
    git-crypt  # For encrypting sensitive files in git repos
    gitui      # Terminal UI for git
    lazygit    # Another terminal UI for git
  ];
}
