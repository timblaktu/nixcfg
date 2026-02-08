# Environment configuration (consolidated approach)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homeBase;
in
{
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
      "$HOME/bin" # Our drop-in scripts
      "$HOME/.local/bin" # User local binaries
      "/usr/local/bin" # System local binaries
      "$HOME/go/bin" # Go binaries
      "/usr/local/go/bin" # System Go installation
      "$HOME/.cargo/bin" # Rust/Cargo binaries  
      "$HOME/.pyenv/bin" # Pyenv binaries
      "$HOME/android-sdk/cmdline-tools/latest/bin" # Android tools
      "$HOME/android-sdk/platform-tools" # Android platform tools
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

    # Create idempotent environment variable sourcing script
    home.file.".nix-idempotent-env" = {
      text = ''
        # Idempotent environment variable sourcing functions
        # This allows safe re-sourcing without variable pollution
        
        # Function to append to PATH only if not already present
        append_path_if_missing() {
          case ":$PATH:" in
            *":$1:"*) ;;  # already there, do nothing
            *) PATH="$1:$PATH";;  # not there, prepend it
          esac
        }
        
        # Function to append to any colon-separated environment variable
        append_env_if_missing() {
          local var_name="$1"
          local new_value="$2"
          local current_value
          eval "current_value=\$$var_name"
          
          case ":$current_value:" in
            *":$new_value:"*) ;;  # already there
            *) eval "$var_name=\"\$new_value:\$$var_name\"";;  # prepend
          esac
        }
        
        # Function to safely source Home Manager session variables with idempotent behavior
        source_hm_session_vars_idempotent() {
          local hm_vars_file="$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
          
          if [[ ! -f "$hm_vars_file" ]]; then
            return 0
          fi
          
          # Create a modified version that handles PATH and other append-style variables idempotently
          # We'll parse the original file and apply idempotent logic
          
          # First, handle all simple export statements (non-PATH variables)
          while IFS= read -r line; do
            if [[ "$line" =~ ^export\ ([^=]+)=\"(.*)\"$ ]]; then
              local var_name="''${BASH_REMATCH[1]}"
              local var_value="''${BASH_REMATCH[2]}"
              
              # Skip if variable name is empty or contains invalid characters
              if [[ -z "$var_name" || "$var_name" =~ [^a-zA-Z0-9_] ]]; then
                continue
              fi
              
              # Skip variables that need special handling
              case "$var_name" in
                PATH|XCURSOR_PATH|XDG_DATA_DIRS|GIO_EXTRA_MODULES)
                  continue
                  ;;
                *)
                  # Simple variable assignment
                  eval "export $var_name=\"$var_value\""
                  ;;
              esac
            fi
          done < "$hm_vars_file"
          
          # Handle PATH idempotently by parsing the generated PATH
          local hm_path_line=$(grep '^export PATH=' "$hm_vars_file" 2>/dev/null | head -1)
          if [[ -n "$hm_path_line" ]]; then
            # Extract the path components that Home Manager wants to add
            # This is a simplified approach - we'll add the known HM paths
            append_path_if_missing "$HOME/bin"
            append_path_if_missing "$HOME/.local/bin"
            append_path_if_missing "/usr/local/bin"
            append_path_if_missing "$HOME/go/bin"
            append_path_if_missing "/usr/local/go/bin"
            append_path_if_missing "$HOME/.cargo/bin"
            append_path_if_missing "$HOME/.pyenv/bin"
            append_path_if_missing "$HOME/android-sdk/cmdline-tools/latest/bin"
            append_path_if_missing "$HOME/android-sdk/platform-tools"
          fi
          
          # Handle other append-style environment variables
          local xcursor_line=$(grep '^export XCURSOR_PATH=' "$hm_vars_file" 2>/dev/null | head -1)
          if [[ -n "$xcursor_line" ]]; then
            append_env_if_missing "XCURSOR_PATH" "/home/tim/.nix-profile/share/icons"
            append_env_if_missing "XCURSOR_PATH" "/usr/share/icons"
            append_env_if_missing "XCURSOR_PATH" "/usr/share/pixmaps"
          fi
          
          local xdg_line=$(grep '^export XDG_DATA_DIRS=' "$hm_vars_file" 2>/dev/null | head -1)
          if [[ -n "$xdg_line" ]]; then
            append_env_if_missing "XDG_DATA_DIRS" "/home/tim/.nix-profile/share"
            append_env_if_missing "XDG_DATA_DIRS" "/usr/share/ubuntu"
            append_env_if_missing "XDG_DATA_DIRS" "/usr/local/share"
            append_env_if_missing "XDG_DATA_DIRS" "/usr/share"
            append_env_if_missing "XDG_DATA_DIRS" "/var/lib/snapd/desktop"
            # Add nix state dir
            if [[ -n "''${NIX_STATE_DIR:-}" ]]; then
              append_env_if_missing "XDG_DATA_DIRS" "''${NIX_STATE_DIR}/profiles/default/share"
            else
              append_env_if_missing "XDG_DATA_DIRS" "/nix/var/nix/profiles/default/share"
            fi
          fi
          
          # Source nix.sh if not already sourced (check for nix command)
          if ! command -v nix >/dev/null 2>&1; then
            local nix_sh_line=$(grep '^\. ".*nix.sh"' "$hm_vars_file" 2>/dev/null | head -1)
            if [[ -n "$nix_sh_line" ]]; then
              local nix_sh_path=$(echo "$nix_sh_line" | sed 's/^\. "\(.*\)"/\1/')
              if [[ -f "$nix_sh_path" ]]; then
                . "$nix_sh_path"
              fi
            fi
          fi
          
          # Handle TERM reset
          export TERM="$TERM"
          
          # Handle GIO_EXTRA_MODULES
          local gio_line=$(grep '^export GIO_EXTRA_MODULES=' "$hm_vars_file" 2>/dev/null | head -1)
          if [[ -n "$gio_line" ]]; then
            append_env_if_missing "GIO_EXTRA_MODULES" "/nix/store/r1gwh4giap2hpw92qxy60m93f05kr4dx-dconf-0.40.0-lib/lib/gio/modules"
          fi
        }
      '';
    };

    # For zsh users, use programs.zsh.envExtra instead of home.file.".zshenv"
    # to avoid conflicts with home-manager's built-in zshenv management.
    # envExtra is sourced in .zshenv which runs for ALL zsh instances (including non-interactive)
    programs.zsh.envExtra = mkIf config.programs.zsh.enable ''
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

    # Simplified bash configuration - now uses idempotent sourcing
    programs.bash.initExtra = lib.mkAfter ''
      # Source shared environment setup
      if [ -f "$HOME/.nix-shared-env" ]; then
        . "$HOME/.nix-shared-env"
      fi
      
      # Source idempotent environment functions
      if [ -f "$HOME/.nix-idempotent-env" ]; then
        . "$HOME/.nix-idempotent-env"
      fi
      
      # Use idempotent Home Manager session variable sourcing
      # This allows safe re-sourcing without variable pollution
      if declare -f source_hm_session_vars_idempotent >/dev/null 2>&1; then
        source_hm_session_vars_idempotent
      fi
      
      # Bash-specific pyenv initialization
      if [[ -d $PYENV_ROOT/bin ]] && command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init - bash)"
      fi
    '';

    # Simplified zsh configuration - now uses idempotent sourcing
    programs.zsh.initContent = lib.mkAfter ''
      # Source shared environment setup
      if [ -f "$HOME/.nix-shared-env" ]; then
        . "$HOME/.nix-shared-env"
      fi
      
      # Source idempotent environment functions
      if [ -f "$HOME/.nix-idempotent-env" ]; then
        . "$HOME/.nix-idempotent-env"
      fi
      
      # Use idempotent Home Manager session variable sourcing
      # This allows safe re-sourcing without variable pollution
      if declare -f source_hm_session_vars_idempotent >/dev/null 2>&1; then
        source_hm_session_vars_idempotent
      fi
      
      # Zsh-specific pyenv initialization
      if [[ -d $PYENV_ROOT/bin ]] && command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init - zsh)"
      fi
    '';
  };
}
