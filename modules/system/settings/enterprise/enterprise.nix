# modules/system/settings/enterprise/enterprise.nix
# Platform-neutral enterprise Home Manager base
#
# Provides:
#   flake.modules.homeManager.home-enterprise - Company-wide, cross-platform HM
#     feature bundle (shell, git, tmux, neovim, terminal, shell-utils,
#     system-tools, yazi, files, git-auth-helpers).
#
# This is the COMMON enterprise HM tier. It deliberately contains NO
# WSL-specific modules -- those (wsl-home, onedrive, windows-terminal) live in
# flake.modules.homeManager.home-wsl (see wsl-enterprise.nix) and are imported
# only by WSL hosts. Darwin hosts compose this with home-darwin instead. This
# mirrors the NixOS side, where the platform-neutral dev-team tier is separate
# from the WSL-coupled wsl-enterprise tier.
#
# Layering / composition (mirrors the NixOS dev-team vs wsl-dev-team split):
#   home-enterprise (COMMON, here)
#     |- WSL host:    + home-wsl    (wsl-home + onedrive + windows-terminal)
#     \- Darwin host: + home-darwin (thin)
#   home-dev-team (COMMON, dev-team.nix) imports home-enterprise + dev tools.
#
# Layers are convenience bundles, not gatekeepers: any host can cherry-pick
# individual feature modules instead of using this bundle.
#
# Usage:
#   # In a host HM config (cross-platform base):
#   imports = [ inputs.self.modules.homeManager.home-enterprise ];
{ config, lib, inputs, ... }:
{
  flake.modules.homeManager.home-enterprise = { config, lib, pkgs, ... }: {
    imports = [
      # Base HM layer (includes home-minimal)
      inputs.self.modules.homeManager.home-default
      # Core CLI tools
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.tmux
      inputs.self.modules.homeManager.neovim
      # Terminal baseline (cross-platform)
      inputs.self.modules.homeManager.terminal
      inputs.self.modules.homeManager.shell-utils
      inputs.self.modules.homeManager.system-tools
      # Standard utilities
      inputs.self.modules.homeManager.yazi
      inputs.self.modules.homeManager.files
      inputs.self.modules.homeManager.git-auth-helpers
    ];

    # Enterprise defaults (overridable by team/host). homeFiles is provided by
    # the cross-platform `files` module. WSL-only defaults (oneDriveUtils,
    # wsl-home-settings) moved to home-wsl.
    homeFiles.enable = lib.mkDefault true;
  };
}
