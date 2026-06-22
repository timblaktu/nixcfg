# modules/hosts/powerbook [D]/powerbook.nix
# Tim's personal nix-darwin configuration (Apple Silicon PowerBook)
#
# Plan 001 (Darwin support), T5 skeleton. Architecture: Model A - native
# nix-darwin workstation (docs/darwin in nixcfg-work). This is the PERSONAL
# counterpart to nixcfg-work's corporate corp-darwin-dev-team host: same proven
# Model A system structure, but personal (no corporate CA, no corporate Homebrew
# set, no corp HM baseline). Personal Homebrew casks / app lists / secrets are
# deliberately deferred to T5b - this skeleton is the minimal *evaluable* host.
#
# The Home Manager layer is wired in the flake-parts instantiation (see
# modules/flake-parts/darwin-configurations.nix), which adds
# home-manager.darwinModules.home-manager and sets
# home-manager.users.<username> = { imports = [ home-cli home-darwin ]; ... }.
# home-cli is the platform-neutral personal CLI tier (shell/git/tmux/neovim/yazi
# + CLI packages); home-darwin is nixcfg's thin macOS HM layer (the personal
# analogue of corp-wsl's home-wsl). The corporate corp-dev-team tier is NOT
# imported here - that belongs to the corp host in nixcfg-work.
#
# Deploy: darwin-rebuild switch --flake '.#powerbook'
{ ... }:
{
  flake.modules.darwin.powerbook = { lib, inputs, ... }:
    let
      # Personal-Mac username override (gitignored), mirroring corp-darwin's
      # local-username.nix mechanism. The real macOS account name is recorded in
      # this file; it is absent from the repo so the host evaluates with the
      # "user" placeholder off-hardware. Written from `whoami` on first run.
      localUsernameFile = "${inputs.self}/modules/hosts/powerbook [D]/local-username.nix";
      username =
        if builtins.pathExists localUsernameFile
        then import localUsernameFile
        else "user";
    in
    {
      imports = [
        # nixcfg's Darwin system-type stack. system-default chains
        # system-minimal: Nix settings + GC + binary caches, user creation +
        # trusted-users + base CLI packages, timezone, system.stateVersion.
        #
        # NB: stop at system-default (corp-darwin + macbook-air do the same).
        # nixcfg's darwin.system-cli is currently broken on darwin - it sets
        # `programs.git`, a home-manager/NixOS option that does not exist in
        # nix-darwin (eval: "The option `programs.git' does not exist"). CLI
        # niceties land via the home-cli HM layer anyway.
        inputs.self.modules.darwin.system-default
      ];

      # === User identity (single source: `username` above) ===
      systemDefault.userName = username;
      systemDefault.timeZone = lib.mkDefault "America/Los_Angeles";

      # The account nix-darwin applies user-scoped activation to (mandatory since
      # nix-darwin made primaryUser required for user-scoped options). mkDefault
      # so a local override can set the real account cleanly.
      system.primaryUser = lib.mkDefault username;

      # === macOS system defaults (UI/UX) - personal taste ===
      system.defaults = {
        dock = {
          autohide = true;
          mru-spaces = false;
          show-recents = false;
          tilesize = 48;
          orientation = "bottom";
        };
        finder = {
          AppleShowAllExtensions = true;
          ShowPathbar = true;
          ShowStatusBar = true;
          FXEnableExtensionChangeWarning = false;
          _FXShowPosixPathInTitle = true;
          FXPreferredViewStyle = "Nlsv"; # default to list view
        };
        trackpad = {
          Clicking = true; # tap to click
          TrackpadThreeFingerDrag = true;
        };
        NSGlobalDomain = {
          AppleShowAllExtensions = true;
          InitialKeyRepeat = 15; # fast key repeat
          KeyRepeat = 2;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticSpellingCorrectionEnabled = false;
        };
      };

      # === Touch ID for sudo ===
      # NB: the old `security.pam.enableSudoTouchIdAuth` is REMOVED in the pinned
      # nix-darwin; this is the current option (renamed for NixOS consistency).
      security.pam.services.sudo_local.touchIdAuth = true;

      # zsh is the default macOS shell.
      programs.zsh.enable = true;

      # Personal Homebrew casks / app lists, personal secrets, and any
      # customization beyond this evaluable baseline are deferred to T5b.
    };
}
