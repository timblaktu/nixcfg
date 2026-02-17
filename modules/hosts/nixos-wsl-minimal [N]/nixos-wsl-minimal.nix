# modules/hosts/nixos-wsl-minimal [N]/nixos-wsl-minimal.nix
# Dendritic host composition for nixos-wsl-minimal (WSL distribution template)
#
# This is a TEMPLATE configuration designed for distribution as a WSL tarball.
# It uses generic settings suitable for new users:
# - Generic "nixos" user (not a personal username)
# - No Home Manager integration (users can add their own)
# - allowUnfree = false for distribution compliance
# - First-login welcome message
#
# This host has NO Home Manager configuration - it's purely system-level.
#
# Build tarball: nix build '.#nixosConfigurations.nixos-wsl-minimal.config.system.build.tarballBuilder'
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#nixos-wsl-minimal'
{ config, lib, inputs, ... }:
let
  # Generic user for distribution (NOT a personal username)
  defaultUser = "nixos";
in
{
  # === NixOS System Module ===
  # Note: No Home Manager module - this is a minimal distribution template
  flake.modules.nixos.nixos-wsl-minimal = { config, lib, pkgs, ... }:
    let
      # Security check script for tarball builds
      tarballSecurityCheck = pkgs.writers.writeBashBin "wsl-tarball-security-check" ''
        echo "WSL Tarball Security Check"
        echo "=========================="
        echo ""
        echo "Checking for personal information..."

        # Check for common personal identifiers
        for id in tim tblack timblack; do
          if [[ "${defaultUser}" =~ $id ]]; then
            echo "⚠ WARNING: Username contains personal identifier: $id"
          fi
        done

        # Check for sensitive env vars
        for pattern in TOKEN API_KEY SECRET PASSWORD PRIVATE_KEY; do
          if env | grep -q "^$pattern"; then
            echo "✗ ERROR: Sensitive env var detected: $pattern*"
          fi
        done

        echo ""
        echo "Check complete."
      '';
    in
    {
      imports = [
        # Hardware configuration (WSL2-specific)
        ./_hardware-config.nix
        # Dendritic system type - minimal layer (no user creation - we handle it)
        inputs.self.modules.nixos.system-minimal
        # NixOS-WSL module
        inputs.nixos-wsl.nixosModules.default
      ];

      # Tarball security check available as: $out/bin/wsl-tarball-security-check
      system.build.tarballSecurityCheck = tarballSecurityCheck;

      # Keep it free for distribution
      nixpkgs.config.allowUnfree = false;

      # WSL configuration
      wsl = {
        enable = true;
        inherit defaultUser;

        # Enable basic Windows integration
        interop = {
          register = true;
          includePath = true;
        };

        # Standard WSL mount configuration
        wslConf = {
          automount.root = "/mnt";
          interop.appendWindowsPath = true;
        };

        # Disable advanced features by default (users can enable if needed)
        usbip.enable = false;
      };

      # Hostname - generic name for distribution
      networking = {
        hostName = "nixos-wsl";
        # Networking handled by WSL
        networkmanager.enable = false;
        firewall.enable = false;
      };

      # User configuration - minimal setup with generic user
      users.users.${defaultUser} = {
        isNormalUser = true;
        description = "NixOS User";
        extraGroups = [ "wheel" ];
        shell = pkgs.bash; # Use bash by default for compatibility

        # Set a default password that users should change
        # Password is "nixos" - users should change this immediately
        initialPassword = "nixos";
      };

      # Enable sudo without password for wheel group initially
      # Users should configure this according to their security needs
      security.sudo.wheelNeedsPassword = false;

      # Essential system packages only (minimal for distribution)
      environment.systemPackages = with pkgs; [
        # Core utilities
        wget
        curl
        htop
        tree

        # WSL utilities
        wslu

        # Nix tools
        nixpkgs-fmt
        nil # Nix language server
      ];

      # Basic shell aliases for Windows integration
      environment.shellAliases = {
        # Windows interop shortcuts
        explorer = "explorer.exe";
        notepad = "notepad.exe";

        # Nix shortcuts
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl-minimal";
        update = "nix flake update /etc/nixos";
      };

      # Locale settings
      i18n.defaultLocale = "en_US.UTF-8";
      time.timeZone = "America/New_York"; # Users should adjust

      # Console configuration
      console = {
        font = "Lat2-Terminus16";
        keyMap = "us";
      };

      # Documentation
      documentation = {
        enable = true;
        man.enable = true;
        info.enable = true;
        doc.enable = true;
      };

      # OpenSSH for remote access (disabled by default)
      services.openssh = {
        enable = false; # Users can enable if needed
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "no";
        };
      };

      # System state version
      system.stateVersion = "24.11";

      # Add helpful message on first login
      programs.bash.interactiveShellInit = ''
        if [ -f ~/.first-login ]; then
          echo "======================================"
          echo "Welcome to NixOS-WSL!"
          echo ""
          echo "Quick start:"
          echo "1. Change your password: passwd"
          echo "2. Edit configuration: sudo vim /etc/nixos/configuration.nix"
          echo "3. Rebuild system: sudo nixos-rebuild switch --flake /etc/nixos#nixos-wsl-minimal"
          echo ""
          echo "For more information:"
          echo "- NixOS Manual: https://nixos.org/manual/nixos/stable/"
          echo "- NixOS-WSL Docs: https://nix-community.github.io/NixOS-WSL/"
          echo "======================================"
          rm ~/.first-login
        fi
      '';

      # Create first-login flag for new users
      system.activationScripts.firstLogin = ''
        if [ ! -f /home/${defaultUser}/.first-login ]; then
          touch /home/${defaultUser}/.first-login
          chown ${defaultUser}:users /home/${defaultUser}/.first-login
        fi
      '';
    };

  # === Configuration Registration ===
  # Note: Registration is done in flake-modules/nixos-configurations.nix
  # using lib.nixosSystem with self.modules.nixos.nixos-wsl-minimal
  #
  # This host has NO Home Manager configuration - it's designed as a
  # minimal distribution template. Users can add their own HM config after
  # installing the tarball.
}
