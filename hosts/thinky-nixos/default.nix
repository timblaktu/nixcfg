# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

{
  wsl = {
    enable = true;
    defaultUser = "tim";
    # Enable integration with Windows paths
    interop.includePath = true;
    # Set a custom shell
    wslConf.automount.root = "/mnt";
    # Ensure Win32 yubikey support works
    wslConf.interop.appendWindowsPath = true;
  };

  # Hostname
  networking.hostName = "thinky-nixos";

  # User configuration
  users.users.tim = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = lib.mkForce pkgs.zsh;
    # No need for password in WSL
    hashedPassword = "";
  };

  # WSL-specific packages
  environment.systemPackages = with pkgs; [
    wslu # WSL utilities
  ];

  # System-wide aliases for WSL
  environment.shellAliases = {
    explorer = "explorer.exe .";
    code = "code.exe";
    code-insiders = "code-insiders.exe";
  };

  # Enable nix flakes
  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Disable some services that don't make sense in WSL
  services.xserver.enable = false;
  services.printing.enable = false;

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "24.11";
}
