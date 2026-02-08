# hosts/mbp/default.nix
# DEPRECATED: Configuration has been migrated to dendritic pattern
#
# The actual NixOS and Home Manager configurations are now in:
#   modules/hosts/mbp [N]/mbp.nix
#
# This file is kept for hardware-config.nix reference only.
# The hardware-config.nix in this directory is imported by the dendritic module.
#
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#mbp'
# Deploy HM:    home-manager switch --flake '.#tim@mbp'
{ ... }: {
  # This stub exists only to preserve the hosts/mbp/ directory structure
  # for hardware-config.nix. All actual configuration is in the dendritic module.
  imports = [ ];
}
