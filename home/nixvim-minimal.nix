# Minimal nixvim-only home-manager module
# This provides minimal overrides for the dendritic neovim module
#
# NOTE: This is a standalone module imported by tim@nixvim-minimal config
# in home-configurations.nix. It imports the dendritic neovim module and
# applies minimal preference overrides.
{ config, lib, pkgs, inputs, ... }:

{
  imports = [ inputs.self.modules.homeManager.neovim ];

  # Override some settings for minimal preferences
  programs.nixvim.opts = {
    # Prefer 4-space tabs in minimal config
    shiftwidth = lib.mkForce 4;
    tabstop = lib.mkForce 4;
    softtabstop = lib.mkForce 4;

    # Disable backups in minimal config
    backup = lib.mkForce false;
    writebackup = lib.mkForce false;
    backupdir = lib.mkForce null;
    backupcopy = lib.mkForce null;

    # Use XDG state directory for undo
    undodir = lib.mkForce "${config.xdg.stateHome}/nvim/undo";
  };
}
