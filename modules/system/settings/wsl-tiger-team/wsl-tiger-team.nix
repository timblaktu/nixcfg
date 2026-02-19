# modules/system/settings/wsl-tiger-team/wsl-tiger-team.nix
# Tiger team WSL configuration layer [NDnd]
#
# Provides:
#   flake.modules.nixos.wsl-tiger-team - Team-specific NixOS-WSL system config
#   flake.modules.homeManager.home-tiger-team - Team-specific HM feature bundle
#
# This is a team-specific layer that imports the enterprise base and adds
# development tooling for the tiger team's workflow: binfmt cross-compilation,
# Podman containers, Claude Code enterprise, and unfree packages.
#
# NixOS side: Imports wsl-enterprise, overrides for dev workflow.
# HM side: Imports home-enterprise + AI dev tools, GitLab, Podman, etc.
#
# Priority layering:
#   Enterprise (mkDefault/1000) < Tiger-team (bare/100) < Host (mkForce/50)
#   Tiger-team uses mkDefault for NEW options not set by enterprise.
#
# Usage:
#   # In a host module:
#   imports = [ inputs.self.modules.nixos.wsl-tiger-team ];
#
#   # In a host HM config:
#   imports = [ inputs.self.modules.homeManager.home-tiger-team ];
{ config, lib, inputs, ... }:
{
  flake.modules = {

    # =========================================================================
    # NixOS Module: wsl-tiger-team
    # =========================================================================
    # Team-specific WSL system config layered on enterprise base.
    # Enables binfmt (cross-arch builds), Podman, Claude Code enterprise,
    # and unfree packages. Adds setup-username bootstrap script.
    nixos.wsl-tiger-team = { config, lib, pkgs, ... }: {
      imports = [
        # Enterprise base (chains: system-cli -> system-default -> system-minimal + wsl)
        inputs.self.modules.nixos.wsl-enterprise
      ];

      config = lib.mkMerge [
        # === Team Overrides on Enterprise Defaults ===
        # Bare values (priority 100) override enterprise mkDefault (1000).
        # Hosts use mkForce to override these if needed.
        {
          # Team hostname (enterprise default: "nixos-wsl")
          wsl-settings.hostname = "nixos-wsl-tiger";

          # Enable QEMU user-mode emulation for cross-arch builds (aarch64)
          wsl-settings.binfmt.enable = true;

          # Team needs unfree packages (enterprise default: false)
          nixpkgs.config.allowUnfree = true;

          # Windows Terminal profile: team-branded name and font
          enterprise.terminal.profileName = "NixOS Tiger Team";
          enterprise.terminal.font = {
            face = "CaskaydiaMono Nerd Font";
            size = 11;
          };
        }

        # === Team-specific Options ===
        # mkDefault (1000) for options enterprise doesn't set -- overridable by host.
        {
          # Enable Podman container runtime
          systemCli.enablePodman = lib.mkDefault true;

          # Enable Claude Code enterprise managed settings at /etc/claude-code/
          systemCli.enableClaudeCodeEnterprise = lib.mkDefault true;

          # setup-username: Bootstrap script for distributed images.
          # Performs imperative user rename from default 'dev' to chosen username.
          # This is a one-time bootstrap operation -- NixOS declarative user config
          # takes over after the user clones the flake and rebuilds.
          environment.systemPackages = [
            (pkgs.writeShellScriptBin "setup-username" ''
              set -euo pipefail

              if [ $# -ne 1 ]; then
                echo "Usage: setup-username <new-username>"
                echo ""
                echo "Renames the default 'dev' user to your preferred username."
                echo "This is a one-time bootstrap for distributed WSL images."
                echo ""
                echo "After renaming, restart WSL:"
                echo "  wsl --shutdown"
                echo "  wsl -d <distro-name>"
                exit 1
              fi

              NEW_USER="$1"
              CURRENT_USER=$(whoami)

              if [ "$CURRENT_USER" != "dev" ]; then
                echo "Error: This script can only be run by the 'dev' user."
                echo "Current user: $CURRENT_USER"
                echo "(Username already changed from default.)"
                exit 1
              fi

              # Validate username
              if ! echo "$NEW_USER" | ${pkgs.gnugrep}/bin/grep -qE '^[a-z_][a-z0-9_-]*$'; then
                echo "Error: Invalid username."
                echo "Use lowercase letters, numbers, hyphens, underscores."
                echo "Must start with a letter or underscore."
                exit 1
              fi

              echo "This will rename user 'dev' to '$NEW_USER'."
              echo "You will be logged out. Restart WSL to continue."
              echo ""
              read -rp "Proceed? (y/N) " CONFIRM

              if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
                echo "Cancelled."
                exit 0
              fi

              # Rename user, move home directory, rename primary group
              sudo ${pkgs.shadow}/bin/usermod -l "$NEW_USER" dev
              sudo ${pkgs.shadow}/bin/usermod -d "/home/$NEW_USER" -m "$NEW_USER"
              sudo ${pkgs.shadow}/bin/groupmod -n "$NEW_USER" dev 2>/dev/null || true

              # Update WSL default user in wsl.conf
              sudo ${pkgs.gnused}/bin/sed -i "s/^default=dev$/default=$NEW_USER/" /etc/wsl.conf

              echo ""
              echo "User renamed: dev -> $NEW_USER"
              echo ""
              echo "Next steps:"
              echo "  1. Close this terminal"
              echo "  2. In PowerShell: wsl --shutdown"
              echo "  3. Reopen your WSL distro"
              echo ""
              echo "To make the change permanent (survives nixos-rebuild):"
              echo "  Edit your NixOS flake config to set:"
              echo "    systemDefault.userName = \"$NEW_USER\";"
              echo "    wsl-settings.defaultUser = \"$NEW_USER\";"
            '')
          ];

          # NOTE: GitLab system-level git credential config is NOT set here.
          # The HM gitlab-auth module handles credential setup comprehensively
          # (glab auth, credential helpers, CLI wrappers). System-level config
          # would duplicate and potentially conflict with HM-managed settings.
          # Team members using HM get GitLab auth from home-tiger-team bundle.
        }
      ];
    };

    # =========================================================================
    # Home Manager Module: home-tiger-team
    # =========================================================================
    # Convenience bundle of HM feature modules for the tiger team's dev workflow.
    # Imports the enterprise bundle and adds AI dev tools, GitLab auth, Podman,
    # and standard team settings.
    #
    # Layers are convenience bundles, not gatekeepers:
    # - Another team can independently import claude-code, opencode, etc.
    # - Any host can cherry-pick individual modules instead of using this bundle.
    homeManager.home-tiger-team = { config, lib, pkgs, ... }: {
      imports = [
        # Enterprise HM bundle (home-default, shell, git, tmux, neovim, wsl-home,
        # terminal, shell-utils, system-tools, yazi, files, git-auth-helpers, onedrive)
        inputs.self.modules.homeManager.home-enterprise
        # AI development tools
        inputs.self.modules.homeManager.claude-code
        inputs.self.modules.homeManager.opencode
        # Authentication
        inputs.self.modules.homeManager.gitlab-auth
        # Containers
        inputs.self.modules.homeManager.podman
        # Development toolchain
        inputs.self.modules.homeManager.development-tools
        # Terminal appearance
        inputs.self.modules.homeManager.windows-terminal
      ];

      # === Claude Code Configuration ===
      # Team-shared config: work account (Code Companion proxy) + enterprise defaults.
      # Hosts ADD personal accounts (max, pro) via module system merging --
      # accounts is attrsOf submodule, so tiger-team's work + host's max/pro coexist.
      programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
        accounts = inputs.self.lib.claudeCode.workAccount;
        statusline = inputs.self.lib.claudeCode.defaultStatusline;
        mcpServers = inputs.self.lib.claudeCode.defaultMcpServers;
        subAgents.custom = inputs.self.lib.claudeCode.defaultSubAgents;
      };

      # === OpenCode Configuration ===
      # Team-shared config: work account (Code Companion proxy) + base settings.
      # Same merging pattern as claude-code for host personal accounts.
      programs.opencode = inputs.self.lib.openCode.baseConfig // {
        accounts = inputs.self.lib.openCode.workAccount;
        provider = inputs.self.lib.openCode.baseConfig.provider
          // inputs.self.lib.openCode.workProvider;
        mcpServers = inputs.self.lib.openCode.defaultMcpServers;
        commands = inputs.self.lib.openCode.defaultCommands;
      };

      # === GitLab Authentication ===
      # Team-standard GitLab instance config. Personal credential details
      # (bitwarden item/field, mode, apiUser) are left to hosts.
      gitAuth.gitlab = {
        enable = lib.mkDefault true;
        host = lib.mkDefault "git.panasonic.aero";
        cli.enable = lib.mkDefault true;
        # Don't pre-fill username in git credential config.
        # glab auth git-credential rejects username mismatches (compares against
        # glab's internal user from whoami). Without pre-filled username, glab
        # provides credentials directly. See CLAUDE.md glab credential helper fix.
        git.userName = lib.mkDefault null;
      };

      # === Podman Tools ===
      # Aliases default to docker→podman on Linux (platform-aware module).
      programs.podman-tools = {
        enable = lib.mkDefault true;
        enableCompose = lib.mkDefault true;
      };

      # === Tmux ===
      # Auto-reload tmux config when home-manager generation changes.
      programs.tmux.autoReload.enable = lib.mkDefault true;

      # === Windows Terminal ===
      # Team-standard font, size, and keybindings for consistent appearance.
      windowsTerminal = {
        enable = lib.mkDefault true;
        font = {
          face = lib.mkDefault "CaskaydiaMono NFM, Noto Color Emoji";
          size = lib.mkDefault 12;
        };
        keybindings = lib.mkDefault [
          { id = "Terminal.CopyToClipboard"; keys = "ctrl+shift+c"; }
          { id = "Terminal.PasteFromClipboard"; keys = "ctrl+shift+v"; }
          { id = "Terminal.DuplicatePaneAuto"; keys = "alt+shift+d"; }
          { id = "Terminal.NextTab"; keys = "alt+ctrl+l"; }
          { id = "Terminal.PrevTab"; keys = "alt+ctrl+h"; }
        ];
      };

      # Does NOT configure (left to host):
      # - homeMinimal.username / homeMinimal.homeDirectory
      # - secretsManagement.* (personal bitwarden email)
      # - gitAuth.github.* (personal GitHub PATs)
      # - gitAuth.gitlab.bitwarden.* (personal credential details)
      # - gitAuth.gitlab.mode (bitwarden vs token -- personal choice)
      # - gitAuth.gitlab.cli.apiUser (personal GitLab username)
    };

  };
}
