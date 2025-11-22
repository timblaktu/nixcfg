# WSL CUDA support module
# Enables GPU passthrough for CUDA workloads in WSL2 NixOS
#
# This module does NOT install NVIDIA drivers - WSL2 provides driver stubs
# at /usr/lib/wsl/lib/ from the Windows host driver.
#
# Usage: Add to your host configuration and enable:
#   imports = [ ../../modules/nixos/wsl-cuda.nix ];
#   wslCuda.enable = true;
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.wslCuda;
  wslLibPath = "/usr/lib/wsl/lib";
in
{
  options.wslCuda = {
    enable = mkEnableOption "WSL CUDA support for GPU passthrough";

    enableNixLd = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable nix-ld to run dynamically linked binaries like nvidia-smi
        from the WSL driver stubs.
      '';
    };

    cudaLibraryPath = mkOption {
      type = types.str;
      default = wslLibPath;
      description = "Path to WSL CUDA driver stubs";
    };

    extraLibraryPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional library paths to include in LD_LIBRARY_PATH";
    };

    setSystemEnv = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set LD_LIBRARY_PATH system-wide. If false, you'll need to set it
        manually or in your shell configuration.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.wsl.enable or false;
        message = "wslCuda requires WSL to be enabled (wsl.enable = true)";
      }
    ];

    # Enable nix-ld to run non-NixOS dynamically linked binaries
    # This is required for nvidia-smi and other WSL driver binaries
    programs.nix-ld = mkIf cfg.enableNixLd {
      enable = true;
      # Libraries that nix-ld will make available to dynamically linked programs
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        # Add common libraries needed by CUDA applications
      ];
    };

    # Set LD_LIBRARY_PATH to include WSL CUDA stubs
    # This allows PyTorch and other CUDA libraries to find libcuda.so
    environment.variables = mkIf cfg.setSystemEnv {
      LD_LIBRARY_PATH = mkDefault (
        concatStringsSep ":" ([ cfg.cudaLibraryPath ] ++ cfg.extraLibraryPaths)
      );
    };

    # Also set in session variables for shells
    environment.sessionVariables = mkIf cfg.setSystemEnv {
      LD_LIBRARY_PATH = mkDefault (
        concatStringsSep ":" ([ cfg.cudaLibraryPath ] ++ cfg.extraLibraryPaths)
      );
    };

    # Informational message
    warnings = [
      ''
        WSL CUDA support enabled. The NVIDIA driver is provided by Windows.
        - Run 'nvidia-smi' to verify GPU access
        - Ensure Windows has NVIDIA driver version 525.60+ for CUDA 12 support
        - WSL CUDA stubs are at: ${cfg.cudaLibraryPath}
      ''
    ];
  };
}
