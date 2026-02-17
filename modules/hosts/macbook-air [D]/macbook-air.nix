# modules/hosts/macbook-air [D]/macbook-air.nix
# Dendritic host composition for macbook-air (Apple Silicon Mac running nix-darwin)
#
# This module defines both Darwin system and Home Manager configurations
# following the dendritic pattern. This is an Apple Silicon MacBook Air
# used as a portable development machine.
#
# Deploy Darwin: darwin-rebuild switch --flake '.#macbook-air'
# Deploy HM:     home-manager switch --flake '.#tim@macbook-air'
{ config, lib, inputs, ... }:
let
  # Common user settings
  username = "tim";
  homeDirectory = "/Users/${username}";
in
{
  # === Darwin System Module ===
  flake.modules.darwin.macbook-air = { config, lib, pkgs, ... }: {
    imports = [
      # Dendritic system type - provides system-default layer (includes minimal)
      inputs.self.modules.darwin.system-default
    ];

    # Allow unfree packages
    nixpkgs.config.allowUnfree = lib.mkDefault true;

    # System default layer configuration (required by system types)
    systemDefault = {
      userName = username;
      timeZone = "America/Los_Angeles";
    };

    # macOS system defaults for UI and UX preferences
    system.defaults = {
      dock = {
        autohide = true;
        mru-spaces = false;
        show-recents = false;
        tilesize = 48;
      };
      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        FXEnableExtensionChangeWarning = false;
        _FXShowPosixPathInTitle = true;
      };
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };
    };

    # Enable sudo with Touch ID
    security.pam.enableSudoTouchIdAuth = true;

    # Homebrew integration for GUI apps not in nixpkgs
    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "zap";
      };
      brews = [
        "mas" # Mac App Store CLI
      ];
      casks = [
        "rectangle" # Window management
        "raycast" # Spotlight replacement
        "iterm2" # Terminal emulator
        "visual-studio-code" # Editor
      ];
    };

    # Services
    services.nix-daemon.enable = true;

    # Enable zsh (default shell on macOS)
    programs.zsh.enable = true;

    # System state version for nix-darwin
    system.stateVersion = 4;

    # User environment managed by standalone Home Manager
    # Deploy with: home-manager switch --flake '.#tim@macbook-air'
  };

  # === Home Manager Module ===
  flake.modules.homeManager."tim@macbook-air" = { config, lib, pkgs, ... }: {
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
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.opencode
      inputs.self.modules.homeManager.secrets-management
      inputs.self.modules.homeManager.github-auth
      inputs.self.modules.homeManager.yazi
      inputs.self.modules.homeManager.shell-utils
      inputs.self.modules.homeManager.terminal
      inputs.self.modules.homeManager.system-tools
      inputs.self.modules.homeManager.podman
      inputs.self.modules.homeManager.git-auth-helpers
      # Note: No wsl-home, esp-idf, onedrive, or windows-terminal - this is macOS, not WSL
    ];

    # Dendritic home-minimal options (required by system types)
    homeMinimal = {
      inherit username homeDirectory;
    };

    # Unified files module (scripts, utilities)
    homeFiles.enable = true;

    # Additional environment variables (home-default option)
    homeDefault.environmentVariables = {
      EDITOR = "nvim";
    };

    # Enable tmux auto-reload on home-manager generation change
    programs.tmux.autoReload.enable = true;

    # Container tools (podman-tui, podman-compose)
    programs.podman-tools = {
      enable = true;
      enableCompose = true;
      aliases = {
        docker = "podman";
        d = "podman";
        dc = "podman-compose";
      };
    };

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
  # Note: Registration is done in flake-modules/ files.
  # The host module only defines flake.modules.{darwin,homeManager}.* content.
  # This avoids circular dependencies that occur when trying to both define
  # and register configurations in the same module.
  #
  # Registration happens in:
  # - flake-modules/darwin-configurations.nix
  # - flake-modules/home-configurations.nix
}
