# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  imports = [
    ./hardware-config.nix
    # Dendritic system type - provides system-cli layer (includes default and minimal)
    inputs.self.modules.nixos.system-cli
    # Dendritic WSL configuration
    inputs.self.modules.nixos.wsl
  ];

  # System default layer configuration (required by system types)
  systemDefault.userName = "tim";

  # WSL settings (dendritic module)
  # GPU: NVIDIA RTX 2000 Ada (8GB VRAM) via WSL2 passthrough
  wsl-settings = {
    hostname = "pa161878-nixos";
    defaultUser = "tim";
    sshPort = 2223;
    userGroups = [ "wheel" "dialout" ];
    sshAuthorizedKeys = [ sshKeys.timblaktu ];
    # Enable CUDA support for GPU passthrough
    cuda.enable = true;
  };

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@pa161878-nixos'
}
