# Git configuration
{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Tim Black";
    userEmail = "timblaktu@gmail.com";
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      color.ui = true;
      merge = {
        conflictstyle = "diff3";
        renameLimit = 999999;
        tool = "smart-nvimdiff";
      };
      # # Add mergetool configuration with cmd workaround for 4-way layout
      # mergetool = {
      #   nvimdiff = {
      #     # Using cmd instead of layout parameter due to Git 2.49.0 bug
      #     cmd = ''nvim -d "$LOCAL" "$BASE" "$REMOTE" "$MERGED" -c "wincmd J"'';
      #   };
      mergetool = {
        prompt = false;
        keepBackup = false;
        "smart-nvimdiff" = {
          cmd = ''smart-nvimdiff "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'';
          trustExitCode = true;
        };
        # Cannot get this to show 4-way layout
        #vimdiff = {
        #  layout = "LOCAL,BASE,REMOTE / MERGED";
        #  # layout = "LOCAL,BASE,REMOTE / MERGED + BASE,LOCAL + BASE,REMOTE + (LOCAL/BASE/REMOTE),MERGED";
        #};
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
        mnemonicPrefix = true;
        renames = true;
        renameLimit = 999999;
        tool = "nvimdiff";
        submodule = "log";
      };
      difftool = {
        prompt = false;
        trustExitCode = true;
        nvimdiff = {
          cmd = ''nvim -d "$LOCAL" "$REMOTE"'';
          layout = "LOCAL,REMOTE";
        };
      };
      credential = {
        helper = "cache --timeout=3600";  # Cache credentials for 1 hour to avoid frequent prompts
        "https://glab.espressif.cn/customer/esp-idf-for-summit" = {
          helper = "store";
        };
      };
      safe = {
        directory = [

        ];
      };
      status = {
        submodulesummary = 1;
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
  
  # GitHub CLI (settings from existing ~/.config/gh/config.yml)
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";  # From existing config (not ssh)
      editor = "";  # Blank in existing config - will refer to environment
      prompt = "enabled";
      prefer_editor_prompt = "disabled";  # From existing config
      pager = "";  # Blank - will refer to environment
      # Custom aliases from existing config
      aliases = {
        co = "pr checkout";
      };
    };
  };
  
  # Install additional Git-related tools
  home.packages = with pkgs; [
    # smart-nvimdiff is now provided by validated-scripts module
    pre-commit # framework for local static analysis before git commit
    gitleaks   # scan working tree for accidental secret/PII leaks
    git-crypt  # For encrypting sensitive files in git repos
    # gitui      # Terminal UI for git - temporarily disabled due to build failure
    lazygit    # Another terminal UI for git
  ];
}
