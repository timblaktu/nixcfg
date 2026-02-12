# modules/programs/shell/shell.nix
# Shell configuration for all platforms [NDnd]
#
# Provides:
#   flake.modules.homeManager.shell - ZSH configuration with vi-mode, completions, plugins
#   flake.modules.nixos.shell - System-level shell defaults (fish as default shell)
#   flake.modules.darwin.shell - Darwin shell defaults
#
# Features:
#   - Comprehensive ZSH configuration with vi-mode
#   - Shell scope indicators for nix-shell, venv, tmux context
#   - Smart PWD truncation for narrow terminals
#   - Extensive aliases (git, navigation, safety)
#   - zsh-autosuggestions and zsh-syntax-highlighting plugins
#   - VCS info in prompt
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.shell ];
{ config, lib, ... }:
let
  # Access flake-level meta options
  inherit (config.meta) username;
in
{
  flake.modules = {
    # === Home Manager Module ===
    # Primary shell configuration for user environment
    homeManager.shell = { config, pkgs, lib, ... }:
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
            # Home Manager (cross-platform)
            rebuild = "home-manager switch --flake ~/src/nixcfg#${username}@$(hostname)";
            rebuild-s = "NIXPKGS_ALLOW_UNFREE=1 home-manager switch --impure --flake ~/src/nixcfg#${username}@$(hostname)";
            h-m = "NIXPKGS_ALLOW_UNFREE=1 home-manager switch --impure --flake ~/src/nixcfg#${username}@$(hostname)";
            optimise = "nix-store --optimise";

            # Navigation
            ll = "ls -l";
            la = "ls -la";
            l = "ls -CF";
            ".." = "cd ..";
            "..." = "cd ../..";
            lh = "ls -lath | head";

            # Enhanced system info
            lsblk = "lsblk -po name,vendor,model,label,size,type,fstype,mountpoints";

            # Git
            g = "git";
            gs = "git status --short";
            ga = "git add";
            gau = "git add --update";
            gaa = "git add --all";
            gc = "git commit";
            gcu = "git commit --update --verbose";
            gca = "git commit --all --verbose";
            gci = "git commit --interactive --verbose";
            gp = "git push";
            gl = "git log";
            gd = "git diff";
            gdu = "git diff --no-pager";
            gitit = "git commit -av && git push";
            # Debug git with verbose tracing
            dgit = "GIT_TRACE=true GIT_CURL_VERBOSE=true GIT_SSH_COMMAND=\"ssh -vvv\" GIT_TRACE_PACK_ACCESS=true GIT_TRACE_PACKET=true GIT_TRACE_PACKFILE=true GIT_TRACE_PERFORMANCE=true GIT_TRACE_SETUP=true GIT_TRACE_SHALLOW=true git";

            # Convenience
            c = "clear";
            e = "$EDITOR";
            v = "nvim";
            vi = "nvim";
            vim = "nvim";

            # Process management
            psg = "ps aux | grep -i";

            # Network
            myip = "curl -s ifconfig.me";

            # System info
            df = "df -h";
            du = "du -h";
            free = "free -h";

            # Safety
            rm = "rm -i";
            cp = "cp -i";
            mv = "mv -i";

            # RBW (Rust Bitwarden) for secrets management
            rbwl = "rbw login";
            rbwu = "rbw unlock";
            rbws = "rbw sync";
            rbwg = "rbw get";
            rbwgn = "rbw get -f notes";
            rbwls = "rbw list";
            rbwlock = "rbw lock";
            rbwstop = "rbw stop-agent";

            # SOPS aliases for secrets management
            sopse = "sops";
            sopsd = "sops -d";

            # Python Poetry
            poetryshell = "eval $(poetry env activate)";
          } // lib.optionalAttrs (config.targets.wsl.enable or false) {
            # WSL-specific clipboard aliases
            clip = "clip.exe";
            paste = "powershell.exe Get-Clipboard";
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
            # dircolors is GNU coreutils (Linux only); macOS uses different approach
            if command -v dircolors &>/dev/null; then
              eval "$(dircolors -b)"
            fi
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
            if [[ -n "$WSL_DISTRO_NAME" ]]; then
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

            # Terminal and keyboard setup
            export GPG_TTY=$(tty)  # Bind gpg-agent to this TTY if gpg commands are used

            # Enable vi mode first
            bindkey -v

            # Load edit-command-line widget
            autoload -Uz edit-command-line
            zle -N edit-command-line

            # Bind Alt+e for edit-command-line in both insert and normal mode
            bindkey -M vicmd '\ee' edit-command-line  # Alt+e in normal mode
            bindkey -M viins '\ee' edit-command-line  # Alt+e in insert mode
            # Bind 'vv' in normal mode (common convention)
            bindkey -M vicmd 'vv' edit-command-line

            bindkey '^R' history-incremental-search-backward

            # Custom prompt with static SHLVL indicator
            PS1='%F{yellow}L$SHLVL%f %n@%m %F{red}%/%f$vcs_info_msg_0_ $ '

            # Nix development shell indicator function
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
            shell_scope_indicator() {
              local scope_parts=()
              local level_indicator=""

              # Shell level indicator (compact format)
              if [[ $SHLVL -gt 1 ]]; then
                level_indicator="L$SHLVL"
                scope_parts+=("%F{yellow}$level_indicator%f")
              fi

              # FHS Environment detection (buildFHSEnv environments)
              if [[ -n "$IN_NIX_SHELL" && "$IN_NIX_SHELL" == "impure" ]]; then
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

              # Tmux info
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
                # Fish-style abbreviation for narrow terminals
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

            # Source local config if it exists
            if [[ -f "$HOME/.zshrc.local" ]]; then
              source "$HOME/.zshrc.local"
            fi

            # Custom shell functions
            better_less() {
              # For viewing single files, pipe through cat first for better ANSI color rendering
              if [[ -f "$1" ]] && [[ $# -eq 1 ]]; then
                cat "$1" | less -r
              else
                command less "$@"
              fi
            }

            verbosecd() {
              cd "$1" && ls -lath | head
            }

            # SSH options for lenient connections (dev/testing environments)
            SSHOPTS_LENIENT=( -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )

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

            # Tmux auto-attach: automatically attach to existing session or create new one
            if [[ -x "$HOME/bin/tmux-auto-attach" ]]; then
              source "$HOME/bin/tmux-auto-attach"
            fi
          '';

          plugins = [
            {
              name = "zsh-autosuggestions";
              src = pkgs.fetchFromGitHub {
                owner = "zsh-users";
                repo = "zsh-autosuggestions";
                rev = "v0.7.0";
                sha256 = "sha256-KLUYpUu4DHRumQZ3w59m9aTW6TBKMCXl2UcKi4uMd7w=";
              };
            }
            {
              name = "zsh-syntax-highlighting";
              src = pkgs.fetchFromGitHub {
                owner = "zsh-users";
                repo = "zsh-syntax-highlighting";
                rev = "0.7.1";
                sha256 = "sha256-gOG0NLlaJfotJfs+SUhGgLTNOnGLjoqnUp54V9aFJg8=";
              };
            }
          ];
        };
      };

    # === NixOS Module ===
    # System-level shell configuration (sets default user shell)
    nixos.shell = { pkgs, ... }: {
      # Make zsh available system-wide
      programs.zsh.enable = true;

      # Set zsh as default shell for the primary user
      users.users.${username}.shell = pkgs.zsh;

      # NixOS-specific shell aliases
      environment.shellAliases = {
        update = "sudo nixos-rebuild switch";
        upgrade = "sudo nixos-rebuild switch --upgrade";
        ports = "sudo netstat -tulpn";
      };
    };

    # === Darwin Module ===
    # Darwin shell configuration
    darwin.shell = { pkgs, ... }: {
      # Make zsh available system-wide
      programs.zsh.enable = true;

      # Darwin handles user shells differently - typically set via System Preferences
      # or via `chsh`. We just ensure zsh is in allowed shells.
    };
  };
}
