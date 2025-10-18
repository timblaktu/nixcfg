# ZSH and shell configuration (merged from shell.nix)
{ config, pkgs, lib, ... }:
let 
  inherit (lib) mkIf optionalString;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    
    history = {
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      extended = true;
      share = true;
    };
    
    shellAliases = {
      # System maintenance
      update = "sudo nixos-rebuild switch";
      upgrade = "sudo nixos-rebuild switch --upgrade";
      rebuild = "home-manager switch --flake ~/src/nixcfg#tim@tblack-t14-nixos";
      rebuild-s = "NIXPKGS_ALLOW_UNFREE=1 home-manager switch --impure --flake ~/src/nixcfg#tim@tblack-t14-nixos";
      h-m = "NIXPKGS_ALLOW_UNFREE=1 home-manager switch --impure --flake ~/src/nixcfg#tim@tblack-t14-nixos";
      gc = "sudo nix-collect-garbage -d";
      optimise = "sudo nix-store --optimise";
      
      # Navigation
      ll = "ls -l";
      la = "ls -la";  
      l = "ls -CF";
      ".." = "cd ..";
      "..." = "cd ../..";
      
      # Git
      g = "git";
      gs = "git status";
      ga = "git add";
      gco = "git commit";
      gp = "git push";
      gl = "git log";
      gd = "git diff";
      
      # Convenience
      c = "clear";
      e = "$EDITOR";
      v = "nvim";
      vi = "nvim";
      vim = "nvim";
      
      # Process management
      psg = "ps aux | grep -i";
      
      # Container tools (provided by podman-tools module when containerSupport enabled)
      
      # Network
      ports = "sudo netstat -tulpn";
      myip = "curl ifconfig.me";
      
      # System info
      df = "df -h";
      du = "du -h";
      free = "free -h";
      
      # Safety  
      rm = "rm -i";
      cp = "cp -i";
      mv = "mv -i";
      
      # Clipboard (WSL)
      clip = mkIf (config.targets.wsl.enable or false) "clip.exe";
      paste = mkIf (config.targets.wsl.enable or false) "powershell.exe Get-Clipboard";
    };
    
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      PAGER = "less";
      LESS = "-R";
      TERM = "xterm-256color";
    };
    
    completionInit = ''
      autoload -U compinit && compinit
      zstyle ':completion:*' auto-description 'specify: %d'
      zstyle ':completion:*' completer _expand _complete _correct _approximate
      zstyle ':completion:*' format 'Completing %d'
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*' menu select=2
      eval "$(dircolors -b)"
      zstyle ':completion:*:default' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' list-colors "" 
      zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
      zstyle ':completion:*' matcher-list "" 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
      zstyle ':completion:*' menu select=long
      zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
      zstyle ':completion:*' use-compctl false
      zstyle ':completion:*' verbose true
      zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
      zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
      # Option B: Show just the description with a colon
      #zstyle ':completion:*:descriptions' format '%d:'
      # Option C: Show description in bold without "Completing"
      zstyle ':completion:*:descriptions' format '%B%d:%b'
    '';
    
    initContent = ''
      # Source NixOS system environment first
      if [[ -r "/etc/set-environment" ]]; then
        source /etc/set-environment
      fi
      
      # Source home-manager session variables
      # Handle both standalone home-manager and NixOS-integrated home-manager
      if [[ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]]; then
        # Standalone home-manager path
        source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      elif [[ -f "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]]; then
        # NixOS-integrated home-manager path
        source "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      fi
      
      # Ensure WSL utilities and Windows paths are available in WSL
      if [[ -n "$WSL_DISTRO" ]]; then
        # Add /bin for WSL utilities like wslpath, but avoid duplicates
        case ":$PATH:" in
          *:/bin:*) ;;  # /bin already in PATH
          *) export PATH="/bin:$PATH" ;;
        esac
        # Add Windows paths if not already present
        case ":$PATH:" in
          *:/mnt/c/Windows/System32:*) ;;  # Windows paths already in PATH
          *) export PATH="$PATH:/mnt/c/Windows/System32:/mnt/c/Windows:/mnt/c/Windows/System32/WindowsPowerShell/v1.0" ;;
        esac
      fi
      
      # Terminal and keyboard setup (from existing ~/.zshrc)
      export GPG_TTY=$(tty)  # Bind gpg-agent to this TTY if gpg commands are used
      
      # Enable vi mode first
      bindkey -v
      
      # Load edit-command-line widget
      autoload -Uz edit-command-line
      zle -N edit-command-line
      
      # Bind Alt+e for edit-command-line in both insert and normal mode (doesn't conflict with vim/nvim)
      bindkey -M vicmd '\ee' edit-command-line  # Alt+e in normal mode
      bindkey -M viins '\ee' edit-command-line  # Alt+e in insert mode
      # Bind 'vv' in normal mode (common convention, doesn't conflict)
      bindkey -M vicmd 'vv' edit-command-line
      
      bindkey '^R' history-incremental-search-backward  # Custom keybinding
      
      # VCS info setup moved to end to prevent override
      
      # Custom prompt that matches existing style (with static SHLVL indicator)
      PS1='%F{yellow}L$SHLVL%f %n@%m %F{red}%/%f$vcs_info_msg_0_ $ '
      
      # Nix development shell indicator function (enhanced)
      function nix_shell_indicator() {
        if [ -v IN_NIX_SHELL ] && [ -n "$IN_NIX_SHELL" ]; then
          if [[ -n "$name" ]]; then
            echo "%F{cyan}[nix:$name]%f "
          else
            echo "%F{cyan}[nix-shell]%f "
          fi
        fi
      }
      
      # Enhanced shell scope detection functions
      # These functions provide comprehensive information about the current shell context
      
      # Main function to generate shell scope indicator
      shell_scope_indicator() {
        local scope_parts=()
        local level_indicator=""
        
        # Shell level indicator (compact format)
        if [[ $SHLVL -gt 1 ]]; then
          level_indicator="L$SHLVL"
          scope_parts+=("%F{yellow}$level_indicator%f")
        fi
        
        # Skip tmux indicator - visible in status bar
        # Focus on shell nesting hierarchy within tmux
        
        # FHS Environment detection (buildFHSEnv environments)
        if [[ -n "$IN_NIX_SHELL" && "$IN_NIX_SHELL" == "impure" ]]; then
          # Check if we're in an FHS environment by looking for FHS indicators
          if [[ -n "$FHS_NAME" || "$0" == *"fhs"* || -n "$ESP_IDF_FHS_ENV" || "$PWD" == */fhs-* ]]; then
            local fhs_name="$FHS_NAME"
            [[ -z "$fhs_name" && -n "$name" ]] && fhs_name="$name"
            [[ -z "$fhs_name" ]] && fhs_name="fhs"
            scope_parts+=("%F{magenta}[$fhs_name-fhs]%f")
          else
            # Regular nix-shell
            local shell_name="$name"
            [[ -z "$shell_name" ]] && shell_name="nix-shell"
            scope_parts+=("%F{cyan}[$shell_name]%f")
          fi
        elif [[ -n "$IN_NIX_SHELL" ]]; then
          # Pure nix-shell
          local shell_name="$name"
          [[ -z "$shell_name" ]] && shell_name="pure"
          scope_parts+=("%F{cyan}[$shell_name-pure]%f")
        fi
        
        # Python virtual environment
        if [[ -n "$VIRTUAL_ENV" ]]; then
          local venv_name="$(basename "$VIRTUAL_ENV")"
          scope_parts+=("%F{blue}(py:$venv_name)%f")
        fi
        
        # Conda environment
        if [[ -n "$CONDA_DEFAULT_ENV" && "$CONDA_DEFAULT_ENV" != "base" ]]; then
          scope_parts+=("%F{blue}(conda:$CONDA_DEFAULT_ENV)%f")
        fi
        
        # Direnv active
        if [[ -n "$DIRENV_DIR" ]]; then
          scope_parts+=("%F{yellow}(direnv)%f")
        fi
        
        # ESP-IDF environment specific detection
        if [[ -n "$IDF_PATH" && -n "$ESP_IDF_FHS_ENV" ]]; then
          scope_parts+=("%F{red}[esp-idf]%f")
        fi
        
        # Join all parts with spaces and add trailing space if not empty  
        if [[ ''${#scope_parts[0]} -gt 0 ]]; then
          local IFS=' '
          printf "%s " ''${scope_parts[*]}
        fi
      }
      
      # Comprehensive shell scope information (for debugging/inspection)
      shell_scope_info() {
        echo "=== Shell Scope Information ==="
        echo "Shell Level: $SHLVL"
        echo "Current Shell: $0 (PID: $$, PPID: $PPID)"
        
        # Tmux info (basic - details visible in status bar)
        if [[ -n "$TMUX" ]]; then
          echo "Tmux: Active (see status bar for details)"
        else
          echo "Tmux: Not active"
        fi
        
        # Nix environment info
        if [[ -n "$IN_NIX_SHELL" ]]; then
          echo "Nix Shell: $IN_NIX_SHELL"
          [[ -n "$name" ]] && echo "Nix Shell Name: $name"
          [[ -n "$NIX_SHELL_PACKAGES" ]] && echo "Packages: $NIX_SHELL_PACKAGES"
          
          # FHS detection
          if [[ "$IN_NIX_SHELL" == "impure" ]]; then
            if [[ -n "$FHS_NAME" || "$0" == *"fhs"* || -n "$ESP_IDF_FHS_ENV" ]]; then
              echo "FHS Environment: Detected (likely buildFHSEnv)"
              [[ -n "$FHS_NAME" ]] && echo "FHS Name: $FHS_NAME"
            fi
          fi
        else
          echo "Nix Shell: Not active"
        fi
        
        # Other environments
        [[ -n "$VIRTUAL_ENV" ]] && echo "Python venv: $(basename "$VIRTUAL_ENV")"
        [[ -n "$CONDA_DEFAULT_ENV" ]] && echo "Conda env: $CONDA_DEFAULT_ENV"
        [[ -n "$DIRENV_DIR" ]] && echo "Direnv active in: $DIRENV_DIR"
        [[ -n "$IDF_PATH" ]] && echo "ESP-IDF Path: $IDF_PATH"
        
        # Process tree (if available)
        if command -v pstree >/dev/null 2>&1; then
          echo -e "\nProcess Tree:"
          pstree -p $$ 2>/dev/null
        fi
      }
      
      braille_symbols=( ⡀ ⡄ ⡆ ⡇ ⡏ ⡟ ⡿ ⣿ )
      smart_pwd() {
        local pwd_str="''${PWD/#$HOME/~}"
        if [[ $COLUMNS -ge 120 ]]; then
          # Truncate components longer than 8 chars to first 4 + ...
          echo "$pwd_str" | sed 's|/\([^/]{12}\)[^/]*|/\1...|g'
        else
          # Fish-style abbreviation for narrow terminals (truncate to 1 char except for last)
          echo "$pwd_str" | sed 's|\([^/]\)[^/]*/|\1/|g'
        fi
      }
      PROMPT="%F{yellow}\''${braille_symbols[SHLVL]:-⣿+}%f\$(shell_scope_indicator)%F{red}\$(smart_pwd)%f\$vcs_info_msg_0_ $ "

      # VCS info setup - placed at end to prevent override by plugins
      autoload -Uz vcs_info
      precmd_vcs_info() { vcs_info }
      precmd_functions+=( precmd_vcs_info )
      zstyle ':vcs_info:*' formats " %B%F{magenta}%b%f"
      
      # History settings
      setopt BANG_HIST              # Treat the '!' character specially during expansion.
      setopt EXTENDED_HISTORY       # Write the history file in the ":start:elapsed;command" format.
      setopt INC_APPEND_HISTORY     # Write to the history file immediately, not when the shell exits.
      setopt SHARE_HISTORY          # Share history between all sessions.
      setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming history.
      setopt HIST_IGNORE_DUPS       # Don't record an entry that was just recorded again.
      setopt HIST_IGNORE_ALL_DUPS   # Delete old recorded entry if new entry is a duplicate.
      setopt HIST_FIND_NO_DUPS      # Do not display a line previously found.
      setopt HIST_IGNORE_SPACE      # Don't record an entry starting with a space.
      setopt HIST_SAVE_NO_DUPS      # Don't write duplicate entries in the history file.
      setopt HIST_REDUCE_BLANKS     # Remove superfluous blanks before recording entry.
      setopt HIST_VERIFY            # Don't execute immediately upon history expansion.
      
      # Other useful options
      setopt AUTO_CD              # If command is a directory path, cd to it
      setopt MULTIOS              # Perform implicit tees or cats when multiple redirections are attempted
      setopt PROMPT_SUBST         # Enable parameter expansion, command substitution, etc. in prompts
      setopt INTERACTIVE_COMMENTS # Allow comments in interactive shell
      setopt NO_BEEP              # Don't beep on errors
      setopt EXTENDED_GLOB        # Use extended globbing
      
      # Load custom functions
      if [[ -d "$HOME/.config/zsh/functions" ]]; then
        fpath=("$HOME/.config/zsh/functions" $fpath)
        autoload -Uz $HOME/.config/zsh/functions/*(:t)
      fi
      
      # Override validated-scripts version with static script
      # Using function to take precedence over PATH commands
      check-terminal-setup() {
        /home/tim/bin/check-terminal-setup "$@"
      }
      
      # Also override setup-terminal-fonts to use dynamic detection
      setup-terminal-fonts() {
        /home/tim/bin/setup-terminal-fonts "$@"
      }
      
      # Source local config if it exists
      if [[ -f "$HOME/.zshrc.local" ]]; then
        source "$HOME/.zshrc.local"
      fi
      
      # Enable powerful pattern matching
      setopt EXTENDED_GLOB
      
      # Make less more friendly for non-text input files
      export LESSOPEN="| /usr/bin/env highlight -O ansi %s 2>/dev/null"
      
      # Directory stack options
      setopt AUTO_PUSHD
      setopt PUSHD_IGNORE_DUPS
      setopt PUSHD_MINUS
      
      DIRSTACKSIZE=20
      
      # Aliases for directory stack  
      alias dirs='dirs -v'
      for i in {1..19}; do
        alias "$i"="cd -$i"
      done
    '';
    
    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users/zsh-autosuggestions";
          repo = "zsh-autosuggestions"; 
          rev = "v0.7.0";
          sha256 = "sha256-KLUYpUu4DHRumQZ3w59m9aTW6TBKMCXl2UcKi4uMd7w=";
        };
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users/zsh-syntax-highlighting";
          repo = "zsh-syntax-highlighting";
          rev = "0.7.1";
          sha256 = "sha256-gOG0NLlaJfotJfs+SUhGgLTNOnGLjoqnUp54V9aFJg8=";
        };
      }
    ];
  };
}
