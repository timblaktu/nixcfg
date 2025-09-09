# Environment configuration (consolidated approach)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in {
  config = {
    # Consolidated session variables (replaces most shell initExtra content)
    home.sessionVariables = {
      # Go configuration
      GOPATH = "$HOME/go";
      
      # Android SDK configuration  
      ANDROID_SDK_ROOT = "$HOME/android-sdk";
      ADB_PORT = "5037";
       
      # Pyenv setup
      PYENV_ROOT = "$HOME/.pyenv";
      
      # Neovim runtime
      VIMRUNTIME = "/usr/share/nvim/runtime";
      
      # Yocto build configuration
      BUILD_DIR = "/mnt/internal-4tb-nvme/build";
      TRIP = "10.0.1.19";
      
      # Dynamic variables that need shell execution
      # These will be set in a sourced script
    } // cfg.environmentVariables;
    
    # Consolidated session path (replaces sessionPath additions in initExtra)
    home.sessionPath = [
      "$HOME/bin"                    # Our drop-in scripts
      "$HOME/.local/bin"             # User local binaries
      "/usr/local/bin"               # System local binaries
      "$HOME/go/bin"                 # Go binaries
      "/usr/local/go/bin"            # System Go installation
      "$HOME/.cargo/bin"             # Rust/Cargo binaries  
      "$HOME/.pyenv/bin"             # Pyenv binaries
      "$HOME/android-sdk/cmdline-tools/latest/bin"  # Android tools
      "$HOME/android-sdk/platform-tools"            # Android platform tools
    ];
    
    # Create a shared environment setup script that both shells can source
    home.file.".nix-shared-env" = mkIf config.programs.bash.enable {
      text = ''
        # Shared environment setup for both bash and zsh
        # This handles dynamic variables and complex setup
        
        # Dynamic environment variables that need shell execution
        export GPG_TTY=$(tty)
        export HOST_IP=$(ip route show | grep -i default | awk '{ print $3}')
        export ADB_SERVER_SOCKET="tcp:$HOST_IP:$ADB_PORT"
        
        # Create Go directories if they don't exist
        mkdir -p $GOPATH/{src,pkg,bin} 2>/dev/null || true
        
        # Source Nix environment if it exists
        if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
          . "$HOME/.nix-profile/etc/profile.d/nix.sh"
        fi
        
        # Source color functions if available
        if [ -f "$HOME/bin/colorfuncs.sh" ]; then
          . "$HOME/bin/colorfuncs.sh"
        fi
        
        # TMUX hostname abbreviation
        if [ -n "$TMUX" ]; then
          export TMUX_HOSTNAME_ABBREV=$(
            python -c 'import re, socket; h=socket.gethostname(); tokens=re.split(r"([^a-zA-Z0-9]+)", h); print("".join(t[:4] if t.isalnum() else t for t in tokens)[:15])' 2>/dev/null || echo "$HOSTNAME"
          )
        fi
        
        # Cargo environment
        if [ -f "$HOME/.cargo/env" ]; then
          . "$HOME/.cargo/env"
        fi
      '';
    };
    
    # For zsh users, create .zshenv which is always sourced (even for non-interactive shells)
    # This ensures tmux sessions have proper environment
    home.file.".zshenv" = mkIf config.programs.zsh.enable {
      text = ''
        # ZSH environment setup - sourced for ALL zsh instances
        # This ensures consistent environment in tmux sessions
        
        # Source static Nix environment first
        [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]] && source "$HOME/.nix-profile/etc/profile.d/nix.sh"
        
        # Dynamic environment variables that need shell execution
        export GPG_TTY=$(tty)
        export HOST_IP=$(ip route show | grep -i default | awk '{ print $3}')
        export ADB_SERVER_SOCKET="tcp:$HOST_IP:$ADB_PORT"
        
        # Create Go directories if they don't exist
        mkdir -p $GOPATH/{src,pkg,bin} 2>/dev/null || true
        
        # Source color functions if available
        if [ -f "$HOME/bin/colorfuncs.sh" ]; then
          . "$HOME/bin/colorfuncs.sh"
        fi
        
        # TMUX hostname abbreviation
        if [ -n "$TMUX" ]; then
          export TMUX_HOSTNAME_ABBREV=$(
            python -c 'import re, socket; h=socket.gethostname(); tokens=re.split(r"([^a-zA-Z0-9]+)", h); print("".join(t[:4] if t.isalnum() else t for t in tokens)[:15])' 2>/dev/null || echo "$HOSTNAME"
          )
        fi
        
        # Cargo environment
        if [ -f "$HOME/.cargo/env" ]; then
          . "$HOME/.cargo/env"
        fi
      '';
    };
    
    # Simplified bash configuration - now just sources shared env and handles shell-specific items
    programs.bash.initExtra = lib.mkAfter ''
      # Source shared environment setup
      if [ -f "$HOME/.nix-shared-env" ]; then
        . "$HOME/.nix-shared-env"
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
      
      # Bash-specific pyenv initialization
      if [[ -d $PYENV_ROOT/bin ]]; then
        eval "$(pyenv init - bash)"
      fi
    '';
    
    # Simplified zsh configuration - now just sources shared env and handles shell-specific items
    programs.zsh.initContent = lib.mkAfter ''
      # Source shared environment setup
      if [ -f "$HOME/.nix-shared-env" ]; then
        . "$HOME/.nix-shared-env"
      fi
      
      # Zsh-specific pyenv initialization
      if [[ -d $PYENV_ROOT/bin ]]; then
        eval "$(pyenv init - zsh)"
      fi
    '';
  };
}
