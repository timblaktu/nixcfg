# modules/hosts/thinky-ubuntu [nd]/thinky-ubuntu.nix
# Dendritic host composition for thinky-ubuntu (vanilla WSL Ubuntu with Home Manager only)
#
# This module defines only the Home Manager configuration (no NixOS)
# following the dendritic pattern. Unlike NixOS-WSL hosts, this is
# for a vanilla Ubuntu WSL instance with just Nix/Home Manager installed.
#
# Deploy HM: home-manager switch --flake '.#tim@thinky-ubuntu'
{ config, lib, inputs, ... }:
let
  # Common user settings
  username = "tim";
  homeDirectory = "/home/${username}";
in
{
  # === Home Manager Module ===
  # Note: No NixOS module for this host - it's vanilla Ubuntu WSL
  flake.modules.homeManager."tim@thinky-ubuntu" = { config, lib, pkgs, ... }: {
    imports = [
      # Dendritic system type - provides home-default layer (includes home-minimal)
      inputs.self.modules.homeManager.home-default
      # Files module (scripts, utilities, completions)
      inputs.self.modules.homeManager.files
      # Dendritic feature modules
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.tmux
      inputs.self.modules.homeManager.neovim
      inputs.self.modules.homeManager.wsl-home
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.opencode
      inputs.self.modules.homeManager.secrets-management
      inputs.self.modules.homeManager.github-auth
      inputs.self.modules.homeManager.development-tools
      inputs.self.modules.homeManager.yazi
      inputs.self.modules.homeManager.shell-utils
      inputs.self.modules.homeManager.terminal
      inputs.self.modules.homeManager.system-tools
      inputs.self.modules.homeManager.esp-idf
      inputs.self.modules.homeManager.onedrive
      inputs.self.modules.homeManager.podman
      inputs.self.modules.homeManager.windows-terminal
      inputs.self.modules.homeManager.git-auth-helpers
    ];

    # Dendritic home-minimal options (required by system types)
    homeMinimal = {
      inherit username homeDirectory;
    };

    # WSL home settings (dendritic module)
    wsl-home-settings = {
      distroName = "ubuntu"; # vanilla Ubuntu, not NixOS
    };

    # ESP-IDF development environment (WSL host)
    espIdf.enable = true;

    # OneDrive utilities (WSL host)
    oneDriveUtils.enable = true;

    # Unified files module (scripts, utilities)
    homeFiles.enable = true;

    # Container tools (podman-tui, podman-compose)
    # Aliases default to docker→podman on Linux (platform-aware module)
    programs.podman-tools = {
      enable = true;
      enableCompose = true;
    };

    # Enable tmux auto-reload on home-manager generation change
    programs.tmux.autoReload.enable = true;

    # Secrets management (dendritic module)
    secretsManagement = {
      enable = true;
      rbw.email = "timblaktu@gmail.com";
    };

    # GitHub authentication (dendritic module)
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

    # HOST-SPECIFIC: Windows integration shell aliases
    # Vanilla Ubuntu WSL uses .exe suffixes for Windows binaries
    programs.bash.shellAliases = {
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };

    programs.zsh.shellAliases = {
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };

    # HOST-SPECIFIC: Environment variables
    home.sessionVariables = {
      WSL_DISTRO = lib.mkForce "Ubuntu";
      HOSTNAME = "thinky-ubuntu";
    };

    # Claude Code configuration (using lib presets)
    programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
      accounts = inputs.self.lib.claudeCode.personalAccounts;
      statusline = inputs.self.lib.claudeCode.defaultStatusline;
      mcpServers = inputs.self.lib.claudeCode.defaultMcpServers;
      subAgents.custom = inputs.self.lib.claudeCode.defaultSubAgents;
    };

    # OpenCode configuration (using lib presets)
    programs.opencode = inputs.self.lib.openCode.baseConfig // {
      accounts = inputs.self.lib.openCode.personalAccounts;
      mcpServers = inputs.self.lib.openCode.defaultMcpServers;
      commands = inputs.self.lib.openCode.defaultCommands;
    };
  };

  # === Configuration Registration ===
  # Note: Registration is done in flake-modules/home-configurations.nix
  # The host module only defines flake.modules.homeManager.* content.
  # This avoids circular dependencies that occur when trying to both define
  # and register configurations in the same module.
}
