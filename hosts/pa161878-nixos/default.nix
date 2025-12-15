# WSL NixOS configuration
{ config, lib, pkgs, inputs, ... }:

let
  sshKeys = import ../common/ssh-keys.nix;
in
{
  imports = [
    ./hardware-config.nix
    ../common/wsl-base.nix # Common WSL base configuration
    ../../modules/nixos/wsl-cuda.nix # HOST-SPECIFIC: CUDA support
  ];

  # Host-specific WSL common configuration
  wslCommon = {
    hostname = "pa161878-nixos";
    defaultUser = "tim";
    sshPort = 2223;
    userGroups = [ "wheel" "dialout" ];
    authorizedKeys = [ sshKeys.timblaktu ];
  };

  # SSH service configuration
  services.openssh.ports = [ 2223 ];

  # WSL CUDA support - enables GPU passthrough for ML workloads
  # GPU: NVIDIA RTX 2000 Ada (8GB VRAM) via WSL2 passthrough
  wslCuda.enable = true;

  # User environment managed by standalone Home Manager
  # Deploy with: home-manager switch --flake '.#tim@pa161878-nixos'
}
