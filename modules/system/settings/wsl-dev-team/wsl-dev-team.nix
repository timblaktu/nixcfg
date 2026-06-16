# modules/system/settings/wsl-dev-team/wsl-dev-team.nix
# Dev team WSL configuration layer
#
# Provides:
#   flake.modules.nixos.wsl-dev-team - Team-specific NixOS-WSL system config
#   flake.modules.homeManager.home-dev-team - Team-specific HM feature bundle
#
# This is a WSL-specific layer that composes wsl-enterprise + dev-team and
# adds WSL-specific overrides (USBIP, terminal profile, setup-username).
#
# Platform-agnostic dev tooling (binfmt, Podman, Claude Code enterprise,
# usbutils, kmod) lives in the shared dev-team module.
#
# NixOS side: Imports wsl-enterprise + dev-team, adds WSL overrides.
# HM side: Imports home-enterprise + AI dev tools, GitLab, Podman, etc.
#
# Priority layering:
#   Enterprise (mkDefault/1000) < Dev-team (mkDefault/1000) < WSL-dev-team (bare/100) < Host (mkForce/50)
#   WSL-dev-team uses bare values to override enterprise/dev-team mkDefaults.
#
# Usage:
#   # In a host module:
#   imports = [ inputs.self.modules.nixos.wsl-dev-team ];
#
#   # In a host HM config:
#   imports = [ inputs.self.modules.homeManager.home-dev-team ];
{ config, lib, inputs, ... }:
{
  flake.modules = {

    # =========================================================================
    # NixOS Module: wsl-dev-team
    # =========================================================================
    # WSL-specific dev team config composing wsl-enterprise + shared dev-team.
    # Platform-agnostic dev tooling (binfmt, Podman, Claude Code enterprise,
    # usbutils, kmod) comes from dev-team. This module adds WSL overrides.
    #
    # The double-import of system-cli (via dev-team AND wsl-enterprise) is
    # safe -- NixOS deduplicates modules by reference identity.
    nixos.wsl-dev-team = { config, lib, pkgs, ... }: {
      imports = [
        # Enterprise base (chains: system-cli -> system-default -> system-minimal + wsl)
        inputs.self.modules.nixos.wsl-enterprise
        # Platform-agnostic dev team base (binfmt, Podman, Claude Code, usbutils, kmod)
        inputs.self.modules.nixos.dev-team
      ];

      # =======================================================================
      # Options: declarative setup-username self-rebuild for distributed images
      # =======================================================================
      # On NixOS-WSL user identity is declarative: /etc/passwd and /etc/wsl.conf
      # are regenerated from the config on every boot. An imperative `usermod -l`
      # rename therefore cannot persist (it is reverted on the next restart) and
      # also fails outright while the target user has a live login shell. When
      # selfRebuild is enabled, setup-username instead writes the chosen name into
      # a seeded copy of the flake and runs nixos-rebuild, so the rename becomes
      # declarative state that survives restarts.
      options.wsl-settings.selfRebuild = {
        enable = lib.mkEnableOption "declarative setup-username self-rebuild for distributed WSL images";

        flakeSource = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Store path of the flake source seeded into the image and rebuilt
            from. Required when enable is true. Referencing it pulls the flake
            source into the system closure so the on-image rebuild can evaluate
            without re-fetching the source's origin.
          '';
        };

        flakeAttr = lib.mkOption {
          type = lib.types.str;
          default = config.wsl-settings.hostname;
          defaultText = lib.literalExpression "config.wsl-settings.hostname";
          description = "nixosConfiguration attribute to rebuild (e.g. corp-wsl-dev-team).";
        };

        workDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/wsl-self-rebuild";
          description = "Writable directory the flake source is seeded into (via systemd-tmpfiles) for the rebuild.";
        };

        extraRebuildArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = lib.literalExpression ''[ "--override-input" "vtecli" "/nix/store/...-source" ]'';
          description = ''
            Extra arguments passed to nixos-rebuild, e.g. to override a private
            flake input to a baked store path so the rebuild needs no corporate
            network/SSH access. Other inputs are fetched from their (public)
            origins during the rebuild.
          '';
        };
      };

      config = lib.mkMerge [
        # === Team Overrides on Enterprise Defaults ===
        # Bare values (priority 100) override enterprise mkDefault (1000).
        # Hosts use mkForce to override these if needed.
        {
          # Team hostname (enterprise default: "nixos-wsl")
          wsl-settings.hostname = "nixos-wsl-dev-team";

          # Add plugdev for hardware programmer access (Dediprog udev rule)
          wsl-settings.userGroups = [ "wheel" "plugdev" ];

          # USB devices to auto-attach by hardware ID (VID:PID) via usbipd-win v5.x
          wsl-settings.usbip.autoAttachByHardwareId = [
            { hardwareId = "0403:6001"; description = "FTDI USB-UART adapter"; }
            { hardwareId = "0483:374b"; description = "ST-LINK/V2-1 (STM32 Nucleo/Discovery)"; }
            { hardwareId = "0483:dada"; description = "Dediprog SPI flash programmer (SF100/SF600/SF700)"; }
            { hardwareId = "0955:7523"; description = "NVIDIA Jetson Recovery Mode (APX)"; }
            { hardwareId = "1d6b:0104"; description = "Linux USB Mass Storage Gadget (Jetson initrd-flash)"; }
          ];

          # Team needs unfree packages (enterprise default: false)
          nixpkgs.config.allowUnfree = true;

          # Windows Terminal profile: team-branded name and font
          enterprise.terminal.profileName = "NixOS Dev Team";
          enterprise.terminal.font = {
            face = "CaskaydiaMono Nerd Font";
            size = 11;
          };
        }

        # === WSL-specific Options ===
        # mkDefault (1000) for WSL-only options -- overridable by host.
        {
          # setup-username: Bootstrap script for distributed WSL images.
          # Performs imperative user rename from the shipped default user to the
          # chosen username. This is a one-time bootstrap operation -- NixOS
          # declarative user config takes over after the user clones the flake
          # and rebuilds.
          #
          # The "from" user is derived at build time from wsl-settings.defaultUser
          # (the option that actually sets wsl.defaultUser and creates the user),
          # so the script always targets the user the image really ships -- whether
          # that is "user", "dev", or anything else. Hardcoding "dev" here made the
          # script abort on every shipped image (which defaults to "user").
          environment.systemPackages = [
            (pkgs.writeShellScriptBin "setup-username" (
              let sr = config.wsl-settings.selfRebuild; in
              # --- Shared usage + validation ---
              ''
                set -euo pipefail

                # Injected at build time from the system's configured default user.
                BOOTSTRAP_USER="${config.wsl-settings.defaultUser}"

                if [ $# -ne 1 ]; then
                  echo "Usage: setup-username <new-username>"
                  echo ""
                  echo "Sets your preferred username on this distributed WSL image."
                  echo "The default user is '$BOOTSTRAP_USER'; this is a one-time bootstrap."
                  exit 1
                fi

                NEW_USER="$1"
                CURRENT_USER=$(whoami)

                if [ "$CURRENT_USER" != "$BOOTSTRAP_USER" ]; then
                  echo "Error: This script can only be run by the default '$BOOTSTRAP_USER' user."
                  echo "Current user: $CURRENT_USER"
                  echo "(Username already changed from the default.)"
                  exit 1
                fi

                if [ "$NEW_USER" = "$BOOTSTRAP_USER" ]; then
                  echo "Error: New username matches the current default ('$BOOTSTRAP_USER')."
                  echo "Nothing to do -- choose a different username."
                  exit 1
                fi

                # Validate username
                if ! echo "$NEW_USER" | ${pkgs.gnugrep}/bin/grep -qE '^[a-z_][a-z0-9_-]*$'; then
                  echo "Error: Invalid username."
                  echo "Use lowercase letters, numbers, hyphens, underscores."
                  echo "Must start with a letter or underscore."
                  exit 1
                fi
              ''
              + (if sr.enable then
              # --- Declarative path: write override + rebuild (persists) ---
                ''

                  # NixOS-WSL regenerates /etc/passwd and /etc/wsl.conf from the
                  # declarative config on every boot, so an imperative `usermod -l`
                  # rename cannot persist. Instead, drop a username override into a
                  # seeded copy of the flake and rebuild: the rename then becomes
                  # declarative state that survives every restart.
                  WORKDIR="${sr.workDir}"

                  if [ ! -e "$WORKDIR/flake.nix" ]; then
                    echo "Error: self-rebuild flake source not found at $WORKDIR/flake.nix" >&2
                    echo "It is seeded by systemd-tmpfiles on first boot. On a fresh" >&2
                    echo "image, restart WSL once (wsl --shutdown) and try again." >&2
                    exit 1
                  fi

                  echo "This sets your username to '$NEW_USER' and rebuilds the system so the"
                  echo "change is permanent (survives restarts). It may take a few minutes and"
                  echo "needs internet access to github.com."
                  echo ""
                  read -rp "Proceed? (y/N) " CONFIRM
                  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
                    echo "Cancelled."
                    exit 0
                  fi

                  # The flake imports this file when present (see the corp
                  # nixos-configurations wiring), setting both wsl-settings.defaultUser
                  # and systemDefault.userName so login user, /etc/passwd and the home
                  # directory all re-point to the new name.
                  printf '%s\n' \
                    '{ lib, ... }:' \
                    '{' \
                    "  wsl-settings.defaultUser = lib.mkForce \"$NEW_USER\";" \
                    "  systemDefault.userName = lib.mkForce \"$NEW_USER\";" \
                    '}' | sudo ${pkgs.coreutils}/bin/tee "$WORKDIR/local-username.nix" >/dev/null

                  echo "Rebuilding (nixos-rebuild switch)..."
                  sudo nixos-rebuild switch --flake "$WORKDIR#${sr.flakeAttr}"${lib.optionalString (sr.extraRebuildArgs != [ ]) " ${lib.escapeShellArgs sr.extraRebuildArgs}"}

                  echo ""
                  echo "Done: '$BOOTSTRAP_USER' -> '$NEW_USER' (declarative; persists across restarts)."
                  echo ""
                  echo "Restart WSL to log in as '$NEW_USER':"
                  echo "  In PowerShell:  wsl --shutdown"
                  echo "  Reopen your WSL distro"
                ''
              else
              # --- Imperative fallback (non-distributed / legacy images) ---
                ''

                  # NOTE: On NixOS-WSL this rename does NOT persist across a restart
                  # (user identity is declarative). Prefer wsl-settings.selfRebuild for
                  # distributed images. Retained for non-WSL or non-distributed use.
                  echo "This will rename user '$BOOTSTRAP_USER' to '$NEW_USER'."
                  echo "You will be logged out. Restart WSL to continue."
                  echo ""
                  read -rp "Proceed? (y/N) " CONFIRM

                  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
                    echo "Cancelled."
                    exit 0
                  fi

                  # Rename user, move home directory, rename primary group
                  sudo ${pkgs.shadow}/bin/usermod -l "$NEW_USER" "$BOOTSTRAP_USER"
                  sudo ${pkgs.shadow}/bin/usermod -d "/home/$NEW_USER" -m "$NEW_USER"
                  sudo ${pkgs.shadow}/bin/groupmod -n "$NEW_USER" "$BOOTSTRAP_USER" 2>/dev/null || true

                  # Update WSL default user in wsl.conf
                  sudo ${pkgs.gnused}/bin/sed -i "s/^default=$BOOTSTRAP_USER$/default=$NEW_USER/" /etc/wsl.conf

                  echo ""
                  echo "User renamed: $BOOTSTRAP_USER -> $NEW_USER"
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
            )
            )
          ];

          # NOTE: GitLab system-level git credential config is NOT set here.
          # The HM gitlab-auth module handles credential setup comprehensively
          # (glab auth, credential helpers, CLI wrappers). System-level config
          # would duplicate and potentially conflict with HM-managed settings.
          # Team members using HM get GitLab auth from home-dev-team bundle.
        }

        # === Declarative self-rebuild seeding (distributed images) ===
        # Seed a writable copy of the flake source so setup-username can drop a
        # username override and run nixos-rebuild against it. The tmpfiles `C`
        # rule copies only when the target is absent/empty, so the override file
        # survives later boots (and the seed is not re-copied over it).
        (lib.mkIf config.wsl-settings.selfRebuild.enable {
          assertions = [
            {
              assertion = config.wsl-settings.selfRebuild.flakeSource != null;
              message = "wsl-settings.selfRebuild.enable requires wsl-settings.selfRebuild.flakeSource to be set.";
            }
          ];
          systemd.tmpfiles.rules = [
            "C ${config.wsl-settings.selfRebuild.workDir} 0755 root root - ${config.wsl-settings.selfRebuild.flakeSource}"
          ];
        })
      ];
    };

    # =========================================================================
    # Home Manager Module: home-dev-team
    # =========================================================================
    # Convenience bundle of HM feature modules for the dev team's workflow.
    # Imports the enterprise bundle and adds AI dev tools, GitLab auth, Podman,
    # and standard team settings.
    #
    # Layers are convenience bundles, not gatekeepers:
    # - Another team can independently import claude-code, opencode, etc.
    # - Any host can cherry-pick individual modules instead of using this bundle.
    homeManager.home-dev-team = { config, lib, pkgs, ... }: {
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
        # AWS CLI with Azure AD SSO
        inputs.self.modules.homeManager.awscli
        # JFrog CLI with Artifactory credential injection
        inputs.self.modules.homeManager.jfrog-cli
      ];

      # === Development Tools ===
      # Enable the development toolchain bundle (Python, Rust, Node, Go, etc.)
      # Imported above but mkEnableOption defaults to false.
      developmentTools.enable = lib.mkDefault true;

      # === Claude Code Configuration ===
      # Team-shared structural config: work account template + enterprise defaults.
      # Hosts ADD personal accounts (max, pro) via module system merging --
      # accounts is attrsOf submodule, so dev-team's work + host's max/pro coexist.
      #
      # Deployment-specific values (baseUrl, bitwarden items, modelMappings) must be
      # set by the host config or a private flake input overlay.
      programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
        defaultAccount = "work";
        accounts = inputs.self.lib.claudeCode.workAccount;
        statusline = inputs.self.lib.claudeCode.defaultStatusline;
        mcpServers = inputs.self.lib.claudeCode.defaultMcpServers;
        subAgents.custom = inputs.self.lib.claudeCode.defaultSubAgents;
      };

      # === OpenCode Configuration ===
      # Team-shared structural config: work account template + base settings.
      # Same merging pattern as claude-code for host personal accounts.
      #
      # Deployment-specific values (baseURL, bitwarden items, models) must be
      # set by the host config or a private flake input overlay.
      programs.opencode = inputs.self.lib.openCode.baseConfig // {
        defaultAccount = "work";
        accounts = inputs.self.lib.openCode.workAccount;
        provider = inputs.self.lib.openCode.baseConfig.provider
          // inputs.self.lib.openCode.workProvider;
        mcpServers = inputs.self.lib.openCode.defaultMcpServers;
        commands = inputs.self.lib.openCode.defaultCommands;
        agentFiles.custom = inputs.self.lib.openCode.defaultAgentFiles;
        skills = inputs.self.lib.openCode.defaultSkills;
        fileCommands.custom = inputs.self.lib.openCode.defaultFileCommands;
      };

      # === GitLab Authentication ===
      # Team GitLab config structure. Host must set gitAuth.gitlab.host to
      # their GitLab instance. Personal credential details (bitwarden item/field,
      # mode, apiUser) are also left to hosts.
      gitAuth.gitlab = {
        enable = lib.mkDefault true;
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

      # === AWS CLI ===
      # Team-standard AWS CLI v2. Only the base CLI is enabled here;
      # azureAuth requires secretsManagement (Bitwarden) which is personal.
      # Hosts with secretsManagement enable azureAuth themselves.
      awscli.enable = lib.mkDefault true;

      # === JFrog CLI ===
      # Team-standard JFrog CLI. Host must set jfrogCli.host and
      # bitwarden item/field for their Artifactory instance.
      jfrogCli.enable = lib.mkDefault true;

      # === Team CLI Tools ===
      # Standalone CLI tools that don't warrant their own module.
      home.packages = with pkgs; [
        confluence-markdown-exporter # Confluence → Markdown bulk exporter
      ];

      # Does NOT configure (left to host):
      # - homeMinimal.username / homeMinimal.homeDirectory
      # - secretsManagement.* (personal bitwarden email)
      # - gitAuth.github.* (personal GitHub PATs)
      # - gitAuth.gitlab.bitwarden.* (personal credential details)
      # - gitAuth.gitlab.mode (bitwarden vs token -- personal choice)
      # - gitAuth.gitlab.cli.apiUser (personal GitLab username)
      # - awscli.azureAuth.* (requires secretsManagement for Bitwarden)
      # - jfrogCli.host (team Artifactory hostname)
      # - jfrogCli.bitwarden.* (personal credential details)
    };

  };
}
