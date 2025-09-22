# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-config.nix
    ../../modules/base.nix
    ../../modules/wsl-common.nix
    ../../modules/wsl-tarball-checks.nix
    ../../modules/nixos/sops-nix.nix
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    inputs.nixos-wsl.nixosModules.default
  ];
  
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Base module configuration
  base = {
    userName = "tim";
    userGroups = [ "wheel" "dialout" ];
    enableClaudeCodeEnterprise = true;
    nixMaxJobs = 8;
    nixCores = 0;
    enableBinaryCache = true;
    cacheTimeout = 10;
    sshPasswordAuth = true;
    requireWheelPassword = false;
    additionalShellAliases = {
      esp32c5 = "esp-idf-shell";
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };
  };

  # WSL common configuration
  wslCommon = {
    enable = true;
    hostname = "thinky-nixos";
    defaultUser = "tim";
    sshPort = 2223;  # Must bind to unique port since sharing winHost with another WSL guest
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com"
    ];
    enableWindowsTools = true;
  };

  # WSL-specific configuration
  wsl.enable = true;
  wsl.defaultUser = "tim";
  wsl.crossInstanceMount.enable = true;
  wsl.interop.register = true;
  wsl.usbip.enable = true;
  wsl.usbip.autoAttach = [ "3-1" "3-2" ];  # .. the last on new sabrent hub is 8-4
  wsl.usbip.snippetIpAddress = "localhost";  # Fix for auto-attach

  # For disk id and UUIDs, use: `lsblk -o NAME,SIZE,TYPE,FSTYPE,RO,MOUNTPOINTS,UUID`
  wsl.bareMounts = {
    enable = true;
    mounts = [
      {
        diskUuid = "e030a5d0-fd70-4823-8f51-e6ea8c145fe6";
        mountPoint = "/mnt/wsl/internal-4tb-nvme";
        fsType = "ext4";
        options = [ "defaults" "noatime" ];
      }
      # {
      #   diskUuid = "ANOTHER-UUID-HERE";
      #   mountPoint = "/mnt/wsl/ext-tb4-4tb-nvme-1";
      #   fsType = "ext4";
      #   options = [ "defaults" "noatime" ];
      # }
    ];
  };
  
  # Bind mount the Nix store from the bare-mounted disk
  # NOTE: Before enabling this, copy existing store with:
  # sudo rsync -avHAX /nix/ /mnt/wsl/internal-4tb-nvme/nix-thinky-nixos/
  # fileSystems."/nix" = {
  #   device = "/mnt/wsl/internal-4tb-nvme/nix-thinky-nixos";
  #   fsType = "none";
  #   options = [
  #     "bind"
  #     "x-systemd.automount"           # Mount on first access
  #     "x-systemd.idle-timeout=60"     # Unmount after idle
  #     "x-systemd.requires=mnt-wsl-internal\\x2d4tb\\x2dnvme.mount"
  #     "x-systemd.after=mnt-wsl-internal\\x2d4tb\\x2dnvme.mount"
  #     "_netdev"                        # Network device (for ordering)
  #     "nofail"                         # Don't fail boot if unavailable
  #   ];
  # };
  
  # SSH service configuration
  services.openssh = {
    enable = true;
    ports = [ 2223 ];  # Must bind to unique port since sharing winHost with another WSL guest
  };

  # USB device management for ESP32 development
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "10-esp32-usb";
      destination = "/etc/udev/rules.d/10-esp32-usb.rules";
      text = ''
        # CP2102N USB to UART Bridge Controller - Device 1
        # Serial: a84d26d0ef5fef1186befc45d9b539e6
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="a84d26d0ef5fef1186befc45d9b539e6", SYMLINK+="ttyESP0", MODE="0666", GROUP="dialout"
        
        # CP2102N USB to UART Bridge Controller - Device 2  
        # Serial: 4095a7a28d1af0119da88250ac170b28
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="4095a7a28d1af0119da88250ac170b28", SYMLINK+="ttyESP1", MODE="0666", GROUP="dialout"
        
        # Generic rule for all CP2102N devices (fallback)
        # This ensures any CP2102N device gets proper permissions even if not explicitly listed
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
        
        # Also handle the usb-serial subsystem
        SUBSYSTEM=="usb-serial", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="dialout"
      '';
    })
  ];

  # Home Manager configuration for user tim
  home-manager.users.tim = {
    imports = [ ../../home/modules/base.nix ];
    homeBase = {
      username = "tim";
      homeDirectory = "/home/tim";
      enableDevelopment = true;
      enableEspIdf = true;
      environmentVariables = {
        WSL_DISTRO = "nixos";
        EDITOR = "nvim";
      };
      shellAliases = {
        explorer = "explorer.exe .";
        code = "code.exe";
        code-insiders = "code-insiders.exe";
        esp32c5 = "esp-idf-shell";
      };
    };
    
    # Configure Bitwarden rbw CLI for secrets management
    secretsManagement = {
      enable = true;
      rbw = {
        email = "timblaktu@gmail.com";
        # Explicitly set Bitwarden cloud service URLs (these are the defaults)
        baseUrl = "https://vault.bitwarden.com";
        identityUrl = "https://identity.bitwarden.com";
        uiUrl = "https://vault.bitwarden.com";
        notificationsUrl = "https://notifications.bitwarden.com";
      };
    };
    terminalVerification.terminalFont = "JetBrainsMono Nerd Font";
    targets.wsl = {
      enable = true;
      windowsUsername = "tblack";
      windowsTools = {
        enablePowerShell = true;
        enableCmd = false;
        enableWslPath = true;
        wslPathPath = "/bin/wslpath";
      };
      bindMountRoot.enable = false;
    };
  };
  home-manager.extraSpecialArgs = {
    inherit inputs;
    inherit (inputs) nixpkgs-stable;
    wslHostname = "tblack-t14-nixos";
  };
  home-manager.backupFileExtension = "backup";

  # SOPS-NiX configuration for secrets management
  sopsNix = {
    enable = true;
    hostKeyPath = "/etc/sops/age.key";
    # defaultSopsFile will be set when we have production secrets
  };
  
  # Production secrets will be defined here as needed
  # Example:
  # sops.secrets = {
  #   "github_token" = {
  #     owner = "tim";
  #     group = "users";
  #     mode = "0400";
  #     sopsFile = ../../secrets/common/services.yaml;
  #   };
  # };

  # System state version
  system.stateVersion = "24.11";
}
