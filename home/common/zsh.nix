# ZSH configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in {
  config = {
    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      
      initExtraBeforeCompInit = ''
        # Nix development shell indicator function
        function nix_shell_indicator() {
          if [[ -n "$IN_NIX_SHELL" ]]; then
            if [[ -n "$name" ]]; then
              echo "%F{cyan}[nix:$name]%f "
            else
              echo "%F{cyan}[nix-shell]%f "
            fi
          fi
        }
      '';
      
      initExtra = ''
        # Set the prompt with Nix shell indicator
        PROMPT='$(nix_shell_indicator)%F{green}%n@%m%f:%F{blue}%~%f$ '
        
        # Additional ZSH configuration
        setopt AUTO_CD              # Auto change to a dir without typing cd
        setopt AUTO_PUSHD           # Push the old directory onto the stack on cd
        setopt PUSHD_IGNORE_DUPS    # Do not store duplicates in the stack
        setopt PUSHD_SILENT         # Do not print the directory stack after pushd or popd
        setopt PUSHD_TO_HOME        # Push to home directory when no argument is given
        setopt CDABLE_VARS          # Change directory to a path stored in a variable
        setopt MULTIOS              # Write to multiple descriptors
        setopt EXTENDED_GLOB        # Use extended globbing syntax
        setopt INTERACTIVE_COMMENTS # Allow comments in interactive shells
        
        # History settings
        setopt EXTENDED_HISTORY     # Write the history file in the ':start:elapsed;command' format
        setopt SHARE_HISTORY        # Share history between all sessions
        setopt HIST_EXPIRE_DUPS_FIRST  # Expire a duplicate event first when trimming history
        setopt HIST_IGNORE_DUPS     # Do not record an event that was just recorded again
        setopt HIST_IGNORE_ALL_DUPS # Delete an old recorded event if a new event is a duplicate
        setopt HIST_FIND_NO_DUPS    # Do not display a previously found event
        setopt HIST_IGNORE_SPACE    # Do not record an event starting with a space
        setopt HIST_SAVE_NO_DUPS    # Do not write a duplicate event to the history file
        setopt HIST_VERIFY          # Do not execute immediately upon history expansion
        setopt HIST_BEEP            # Beep when accessing non-existent history
      '';
      
      shellAliases = {
        # Standard aliases
        ls = "ls --color=auto";
        ll = "ls -la";
        la = "ls -a";
        
        # Git shortcuts
        gs = "git status";
        gc = "git commit";
        gp = "git push";
        
        # Nix shortcuts
        nd = "nix develop";
        nb = "nix build";
        nr = "nix run";
        ns = "nix-shell";
        
        # Add ESP32-C5 specific aliases
        esp32c5 = "nix develop .#esp32c5";
      } // cfg.shellAliases; # Merge with user-defined aliases
      
      # Useful oh-my-zsh plugins
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "sudo"
          "docker"
          "command-not-found"
          "colored-man-pages"
        ];
      };
    };
  };
}
