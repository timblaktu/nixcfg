# nixvim-anywhere package definition
{ lib
, stdenv
, writeShellScript
, writeText
, bash
, curl
, git
, coreutils
, findutils
, gawk
, gnugrep
, gnused
, gnutar
, gzip
, nixvim-config ? null
, homeManagerConfiguration ? null
, configName ? "tim@tblack-t14-nixos"
}:

let
  # Create the main nixvim-anywhere script with dependencies
  nixvimAnywhereScript = writeShellScript "nixvim-anywhere" ''
    #!${bash}/bin/bash
    # nixvim-anywhere: Convert any system to use nixvim via home-manager
    
    set -euo pipefail
    
    # Ensure required tools are in PATH
    export PATH="${lib.makeBinPath [
      bash curl git coreutils findutils gawk gnugrep gnused gnutar gzip
    ]}:$PATH"
    
    SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_NAME="$(basename "''${BASH_SOURCE[0]}")"
    VERSION="1.0.0"
    
    # Configuration
    BACKUP_BASE_DIR="$HOME/.nixvim-anywhere-backups"
    CONFIG_TARGET="''${CONFIG_TARGET:-${configName}}"
    DRY_RUN="''${DRY_RUN:-false}"
    
    ${builtins.readFile ./nixvim-anywhere}
  '';

  # Template home-manager configuration that imports actual nixvim config
  homeManagerTemplate = writeText "home-manager-template.nix" ''
    { config, pkgs, ... }:
    {
      # Basic home-manager configuration
      home.username = builtins.getEnv "USER";
      home.homeDirectory = builtins.getEnv "HOME";
      home.stateVersion = "24.05";
      
      # Let home-manager manage itself
      programs.home-manager.enable = true;
      
      # Import the same nixvim configuration used on Type 1/2 systems
      # This ensures perfect parity across all platform types
      ${if nixvim-config != null then ''
        programs.nixvim = (import ${nixvim-config}).programs.nixvim;
      '' else if homeManagerConfiguration != null then ''
        programs.nixvim = ${homeManagerConfiguration}.config.programs.nixvim;
      '' else ''
        # Fallback nixvim configuration
        programs.nixvim = {
          enable = true;
          
          globals.mapleader = " ";
          globals.maplocalleader = " ";
          
          opts = {
            number = true;
            relativenumber = true;
            expandtab = true;
            shiftwidth = 2;
            tabstop = 2;
          };
          
          plugins = {
            lualine.enable = true;
            nvim-tree.enable = true;
            telescope.enable = true;
            treesitter.enable = true;
            lsp = {
              enable = true;
              servers = {
                nil_ls.enable = true;
                pyright.enable = true;
                ts_ls.enable = true;
                gopls.enable = true;
                rust_analyzer = {
                  enable = true;
                  installRustc = true;
                  installCargo = true;
                };
              };
            };
            cmp = {
              enable = true;
              autoEnableSources = true;
            };
          };
          
          keymaps = [
            {
              action = "<cmd>NvimTreeToggle<CR>";
              key = "<leader>e";
              mode = "n";
            }
            {
              action = "<cmd>Telescope find_files<CR>";
              key = "<leader>ff";
              mode = "n";
            }
            {
              action = "<cmd>Telescope live_grep<CR>";
              key = "<leader>fg";
              mode = "n";
            }
          ];
        };
      ''}
      
      # Explicitly avoid managing other programs to prevent conflicts
      programs.bash.enable = false;
      programs.zsh.enable = false;  
      
      # install additional packages here
      home.packages = with pkgs; [ git ];
      
      # Ensure Nix-managed neovim takes precedence
      home.sessionPath = [ "$HOME/.nix-profile/bin" ];
    }
  '';

  # Installation script for web deployment
  webInstaller = writeShellScript "install-nixvim-anywhere.sh" ''
    #!/bin/bash
    # Web installer for nixvim-anywhere
    # Usage: curl -L <url> | bash
    
    set -euo pipefail
    
    REPO_URL="https://github.com/tim/nixcfg"
    TEMP_DIR="/tmp/nixvim-anywhere-$(date +%s)"
    
    echo "=== nixvim-anywhere Web Installer ==="
    echo "Downloading nixvim-anywhere from $REPO_URL"
    echo
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository
    if command -v git >/dev/null 2>&1; then
        git clone "$REPO_URL" .
    else
        echo "Error: git is required for installation"
        echo "Please install git and try again"
        exit 1
    fi
    
    # Run installation
    if [[ -f "pkgs/nixvim-anywhere/nixvim-anywhere" ]]; then
        chmod +x pkgs/nixvim-anywhere/nixvim-anywhere
        ./pkgs/nixvim-anywhere/nixvim-anywhere install --backup --detect-conflicts
    else
        echo "Error: nixvim-anywhere script not found in repository"
        exit 1
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    echo
    echo "Installation complete! You can now use 'nvim' to start your nixvim configuration."
  '';

  # Documentation files
  quickStartGuide = writeText "QUICKSTART.md" ''
    # nixvim-anywhere Quick Start
    
    ## One-Command Installation
    
    Convert your current system to use nixvim via Nix + home-manager:
    
    ```bash
    curl -L https://github.com/tim/nixcfg/raw/main/install-nixvim-anywhere.sh | bash
    ```
    
    ## Manual Installation
    
    1. **Clone repository**:
       ```bash
       git clone https://github.com/tim/nixcfg.git
       cd nixcfg/pkgs/nixvim-anywhere
       ```
    
    2. **Run installation with backup**:
       ```bash
       ./nixvim-anywhere install --backup --detect-conflicts
       ```
    
    3. **Validate installation**:
       ```bash
       ./nixvim-anywhere validate
       ```
    
    4. **Start using nixvim**:
       ```bash
       nvim
       ```
    
    ## What This Does
    
    - ✅ **Installs Nix** in single-user mode (safe, no daemon)
    - ✅ **Sets up home-manager** for user-space package management
    - ✅ **Deploys nixvim** with all dependencies (LSP servers, tools)
    - ✅ **Creates backups** of existing configurations
    - ✅ **Validates installation** to ensure everything works
    
    ## Benefits
    
    - **Complete dependency management**: All LSP servers installed automatically
    - **No conflicts**: home-manager isolates from system packages
    - **Easy updates**: `home-manager switch` updates everything
    - **Reproducible**: Identical environment on every system
    - **Safe rollback**: Can restore pre-Nix state if needed
    
    ## Common Commands
    
    ```bash
    # Update nixvim configuration
    home-manager switch
    
    # Check installation status
    ./nixvim-anywhere status
    
    # Validate everything is working
    ./nixvim-anywhere validate
    
    # Rollback to pre-Nix state
    ./nixvim-anywhere rollback
    ```
    
    ## Troubleshooting
    
    ### Installation Issues
    - **Permission denied**: Don't use sudo, Nix installs in user space
    - **Conflicts detected**: Use `--force` flag or resolve conflicts first
    - **Git not found**: Install git with your system package manager
    
    ### Runtime Issues
    - **Wrong neovim version**: Check PATH with `which nvim`
    - **Config not loading**: Verify with `./nixvim-anywhere validate`
    - **LSP not working**: Dependencies installed automatically, check `:LspInfo`
    
    ### Recovery
    - **Rollback installation**: `./nixvim-anywhere rollback`
    - **Complete removal**: Remove ~/.nix-* and /nix directories
    - **Restore backup**: Backups stored in ~/.nixvim-anywhere-backups/
  '';

in
stdenv.mkDerivation {
  pname = "nixvim-anywhere";
  version = "1.0.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    
    # Create output structure
    mkdir -p $out/bin
    mkdir -p $out/share/nixvim-anywhere
    mkdir -p $out/share/doc/nixvim-anywhere
    
    # Install main script
    cp ${nixvimAnywhereScript} $out/bin/nixvim-anywhere
    chmod +x $out/bin/nixvim-anywhere
    
    # Install templates and configuration files
    cp ${homeManagerTemplate} $out/share/nixvim-anywhere/home-manager-template.nix
    cp ${webInstaller} $out/share/nixvim-anywhere/install-nixvim-anywhere.sh
    chmod +x $out/share/nixvim-anywhere/install-nixvim-anywhere.sh
    
    # Install documentation
    cp ${./README.md} $out/share/doc/nixvim-anywhere/README.md
    cp ${quickStartGuide} $out/share/doc/nixvim-anywhere/QUICKSTART.md
    
    # Create version info
    cat > $out/share/nixvim-anywhere/version.txt << EOF
    nixvim-anywhere version 1.0.0
    Configuration target: ${configName}
    Build time: $(date -u)
    EOF
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Convert any system to use nixvim via Nix + home-manager";
    longDescription = ''
      nixvim-anywhere safely converts traditional Linux/macOS systems to use 
      nixvim by installing Nix and home-manager in user space. This approach
      provides complete dependency management, conflict avoidance, and easy
      rollback while maintaining the same nixvim configuration across all
      platform types.
      
      Key features:
      - Safe single-user Nix installation
      - Automated home-manager setup
      - Comprehensive backup and rollback
      - Conflict detection and resolution
      - Perfect nixvim configuration parity
    '';
    homepage = "https://github.com/tim/nixcfg";
    license = licenses.mit;
    maintainers = [ "tim" ];
    platforms = platforms.unix;
    mainProgram = "nixvim-anywhere";
  };
}
