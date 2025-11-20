# GitHub Authentication Configuration for thinky-nixos
# This module configures automatic GitHub authentication using Bitwarden
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/nixos/bitwarden-github-auth.nix
  ];

  # Enable Bitwarden-based GitHub authentication
  bitwardenGitHub = {
    enable = true;

    # Configure for user tim
    users = [ "tim" ];

    # Bitwarden configuration
    bitwarden = {
      tokenName = "github-token"; # Entry name in Bitwarden
      folder = "Infrastructure/Tokens"; # Folder in Bitwarden vault
      multiAccount = false; # Single GitHub account
    };

    # Authentication settings
    configureGit = true; # Setup git credentials
    configureGh = true; # Setup GitHub CLI
    gitProtocol = "https"; # Use HTTPS (not SSH)
    persistent = false; # Don't persist to disk (more secure)
  };

  # Ensure GitHub CLI is available
  environment.systemPackages = with pkgs; [
    gh # GitHub CLI tool
  ];
}
