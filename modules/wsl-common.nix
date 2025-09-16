# Common WSL configuration module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wslCommon;
in
{
  options.wslCommon = {
    enable = mkEnableOption "WSL common configuration";

    hostname = mkOption {
      type = types.str;
      description = "System hostname";
      example = "thinky-nixos";
    };

    defaultUser = mkOption {
      type = types.str;
      default = "tim";
      description = "Default WSL user";
    };

    interopRegister = mkOption {
      type = types.bool;
      default = true;
      description = "Enable WSL interop registration";
    };

    interopIncludePath = mkOption {
      type = types.bool;
      default = true;
      description = "Enable integration with Windows paths";
    };

    appendWindowsPath = mkOption {
      type = types.bool;
      default = true;
      description = "Ensure Win32 support works by appending Windows PATH";
    };

    automountRoot = mkOption {
      type = types.str;
      default = "/mnt";
      description = "WSL automount root directory";
    };

    enableWindowsTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Windows tool aliases (explorer, code, etc.)";
    };

    sshPort = mkOption {
      type = types.int;
      default = 22;
      description = "SSH port for this WSL instance";
    };

    userGroups = mkOption {
      type = types.listOf types.str;
      default = [ "wheel" ];
      description = "Additional user groups";
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "SSH authorized keys for the default user";
    };
  };

  config = mkIf cfg.enable {
    # Runtime assertions for WSL configuration validation
    assertions = [
      {
        assertion = cfg.hostname != "";
        message = "wslCommon.hostname must not be empty";
      }
      {
        assertion = cfg.defaultUser != "";
        message = "wslCommon.defaultUser must not be empty";
      }
      {
        assertion = cfg.sshPort > 0 && cfg.sshPort < 65536;
        message = "wslCommon.sshPort must be a valid port number (1-65535)";
      }
      {
        assertion = cfg.automountRoot != "";
        message = "wslCommon.automountRoot must not be empty";
      }
      {
        assertion = builtins.elem "wheel" cfg.userGroups;
        message = "wslCommon.userGroups should include 'wheel' for sudo access";
      }
    ];
    # WSL configuration
    wsl = {
      enable = true;
      defaultUser = cfg.defaultUser;
      interop.includePath = cfg.interopIncludePath;
      interop.register = cfg.interopRegister;
      wslConf.automount.root = cfg.automountRoot;
      wslConf.interop.appendWindowsPath = cfg.appendWindowsPath;
    };

    # Set hostname
    networking.hostName = cfg.hostname;

    # Configure the default user
    users.users.${cfg.defaultUser} = {
      isNormalUser = lib.mkDefault true;
      extraGroups = lib.mkDefault cfg.userGroups;
      # Shell is set by base.nix userShell option
      hashedPassword = lib.mkDefault ""; # No password needed in WSL
      openssh.authorizedKeys.keys = lib.mkDefault cfg.authorizedKeys;
    };

    # SSH configuration
    services.openssh = {
      enable = lib.mkDefault true;
      ports = [ cfg.sshPort ];
    };

    # WSL-specific packages
    environment.systemPackages = with pkgs; [
      wslu # WSL utilities
    ];

    # Windows tool aliases (conditional)
    environment.shellAliases = mkIf cfg.enableWindowsTools {
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };

    # Disable services that don't make sense in WSL
    services.xserver.enable = false;
    services.printing.enable = false;
  };
}