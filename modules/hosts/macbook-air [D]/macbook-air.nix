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
      # Dendritic system type - provides home-minimal layer (required first)
      inputs.self.modules.homeManager.home-minimal
      # Legacy base module (will be removed in Phase 6)
      # Provides: disabledModules, detailed program configs (no longer provides username/homeDirectory)
      ../../../home/modules/base.nix
      # Dendritic feature modules
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.tmux
      inputs.self.modules.homeManager.neovim
      inputs.self.modules.homeManager.claude-code
      # opencode: imported via base.nix (home/modules/opencode.nix) - not dendritic yet
      inputs.self.modules.homeManager.secrets-management
      inputs.self.modules.homeManager.github-auth
      # Note: No wsl-home module - this is macOS, not WSL
    ];

    # Dendritic home-minimal options (required by system types)
    homeMinimal = {
      inherit username homeDirectory;
    };

    # Legacy homeBase options for additional features
    homeBase.environmentVariables = {
      EDITOR = "nvim";
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

    # Claude Code configuration (using lib presets)
    programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
      accounts = inputs.self.lib.claudeCode.personalAccounts;
      statusline = inputs.self.lib.claudeCode.defaultStatusline;
      mcpServers = inputs.self.lib.claudeCode.defaultMcpServers;
      subAgents.custom = inputs.self.lib.claudeCode.defaultSubAgents;
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
