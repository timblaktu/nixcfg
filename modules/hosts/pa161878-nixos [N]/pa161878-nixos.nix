# modules/hosts/pa161878-nixos [N]/pa161878-nixos.nix
# Dendritic host composition for pa161878-nixos (WSL work environment)
#
# This module defines both NixOS system and Home Manager configurations
# following the dendritic pattern. Uses the tiger-team layer modules as
# base, adding only personal-specific configuration.
#
# Layer chain:
#   NixOS:  wsl-tiger-team -> wsl-enterprise -> system-cli + wsl
#   HM:     home-tiger-team -> home-enterprise -> home-default + all tools
#
# Deploy NixOS: sudo nixos-rebuild switch --flake '.#pa161878-nixos'
# Deploy HM:    home-manager switch --flake '.#tim@pa161878-nixos'
{ config, lib, inputs, ... }:
let
  # SSH public keys (shared across configurations)
  sshKeys = {
    timblaktu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkVsx3oZrqwkfU6FmhqNEeAGN8dj6lPxNcEwVCmJcQh timblaktu@gmail.com";
  };

  # Common user settings
  username = "tim";
  homeDirectory = "/home/${username}";
in
{
  # === NixOS System Module ===
  flake.modules.nixos.pa161878-nixos = { config, lib, pkgs, ... }: {
    imports = [
      ./_hardware-config.nix
      # Tiger-team layer (chains: wsl-enterprise -> system-cli + wsl)
      inputs.self.modules.nixos.wsl-tiger-team
    ];

    # Personal overrides (bare values override enterprise mkDefault;
    # mkForce where tiger-team sets bare values)
    systemDefault.userName = username;

    wsl-settings = {
      # mkForce: tiger-team sets "nixos-wsl-tiger" as bare value (priority 100)
      hostname = lib.mkForce "pa161878-nixos";
      defaultUser = username;
      sshPort = 2223;
      userGroups = [ "wheel" "dialout" ];
      sshAuthorizedKeys = [ sshKeys.timblaktu ];
      # binfmt.enable: inherited from tiger-team (true)
      # cuda.enable: inherited from enterprise (false)
    };
  };

  # === Home Manager Module ===
  flake.modules.homeManager."tim@pa161878-nixos" = { config, lib, pkgs, ... }: {
    imports = [
      # Tiger-team bundle (enterprise + team tools: claude-code, opencode,
      # gitlab-auth, podman, development-tools, windows-terminal, and all
      # enterprise modules: shell, git, tmux, neovim, wsl-home, etc.)
      inputs.self.modules.homeManager.home-tiger-team
      # Personal-only modules (not shared with team)
      inputs.self.modules.homeManager.secrets-management
      inputs.self.modules.homeManager.github-auth
      inputs.self.modules.homeManager.esp-idf
    ];

    # Required by system types
    homeMinimal = {
      inherit username homeDirectory;
    };

    # Host-specific overrides
    homeDefault.enableLocalAI = false;
    espIdf.enable = true;

    # Secrets management (personal bitwarden)
    secretsManagement = {
      enable = true;
      rbw.email = "timblaktu@gmail.com";
    };

    # GitHub authentication (personal PATs)
    gitAuth.github = {
      enable = true;
      mode = "bitwarden";
      bitwarden = {
        item = "github.com";
        field = "PAT-timtam2026";
      };
      cli.tokenOverrides.pr = {
        item = "github.com";
        field = "PAT-pubclassic";
      };
    };

    # GitLab authentication (personal credentials -- host/cli/userName from tiger-team)
    gitAuth.gitlab = {
      mode = "bitwarden";
      bitwarden = {
        item = "GitLab git.panasonic.aero";
        field = "lord (access token)";
      };
      cli.apiUser = "blackt1";
    };

    # Claude Code: add personal accounts (tiger-team provides work + base config;
    # accounts is attrsOf submodule, so these merge with tiger-team's work account)
    programs.claude-code.accounts = inputs.self.lib.claudeCode.personalAccounts;

    # OpenCode: add personal accounts (same merging pattern)
    programs.opencode.accounts = inputs.self.lib.openCode.personalAccounts;
  };

  # === Configuration Registration ===
  # Note: Registration is done in flake-modules/ files using lib helpers.
  # The host module only defines flake.modules.{nixos,homeManager}.* content.
  # This avoids circular dependencies that occur when trying to both define
  # and register configurations in the same module.
  #
  # Registration happens in:
  # - flake-modules/nixos-configurations.nix (uses lib.mkNixos)
  # - flake-modules/home-configurations.nix (uses lib.mkHomeManager)
}
