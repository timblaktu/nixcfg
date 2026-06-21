# modules/system/settings/wsl-enterprise/wsl-enterprise.nix
# Enterprise WSL base configuration
#
# Provides:
#   flake.modules.nixos.wsl-enterprise - Company-wide NixOS-WSL system base
#   flake.modules.homeManager.home-wsl - WSL-only HM layer (wsl-home, onedrive,
#     windows-terminal). The common HM tiers (home-enterprise, home-dev-team)
#     are platform-neutral and live in enterprise.nix / dev-team.nix.
#
# This is the foundational layer for all enterprise WSL images.
# Team modules (wsl-dev-team, etc.) import this to get the shared base.
#
# NixOS side: Imports system-cli + wsl, sets conservative enterprise defaults.
# HM side: home-wsl bundles the WSL-specific user tools; composed by WSL hosts
#          alongside the common home-dev-team tier.
#
# All defaults use mkDefault so team modules and hosts can override.
#
# Usage:
#   # In a team module:
#   imports = [ inputs.self.modules.nixos.wsl-enterprise ];
#
#   # In a WSL host HM config (common tier + WSL layer):
#   imports = [
#     inputs.self.modules.homeManager.home-dev-team
#     inputs.self.modules.homeManager.home-wsl
#   ];
{ config, lib, inputs, ... }:
{
  flake.modules = {

    # =========================================================================
    # NixOS Module: wsl-enterprise
    # =========================================================================
    # Company-wide base for all WSL NixOS images.
    # Imports system-cli (which chains: minimal -> default -> cli) and wsl.
    # Teams get all of this automatically when they import wsl-enterprise.
    nixos.wsl-enterprise = { config, lib, pkgs, inputs, ... }:
      let
        cfg = config.enterprise;

        # Windows Terminal profile template (JSON)
        # This file is referenced by wsl-distribution.conf [windowsterminal] section.
        # Terminal reads it when discovering WSL distros to set profile appearance.
        terminalProfileJson = builtins.toJSON (
          { name = cfg.terminal.profileName; }
          // lib.optionalAttrs (cfg.terminal.icon != null) { inherit (cfg.terminal) icon; }
          // lib.optionalAttrs (cfg.terminal.colorScheme != null) { inherit (cfg.terminal) colorScheme; }
          // lib.optionalAttrs (cfg.terminal.font != { }) { inherit (cfg.terminal) font; }
        );

        # WORKAROUND: NixOS-WSL build-tarball.nix hardcodes wsl-distribution.conf
        # without [windowsterminal] section. We override the tarball builder to
        # include our enhanced version.
        # TODO: Contribute [windowsterminal] option upstream to NixOS-WSL
        # See: .claude/user-plans/024-nixos-wsl-upstream.md (when created)
        enterpriseDistributionConf = pkgs.writeText "wsl-distribution.conf" (
          lib.generators.toINI { } (
            {
              oobe.defaultName = cfg.terminal.profileName;
              shortcut.icon = "/etc/nixos.ico";
            }
            // lib.optionalAttrs cfg.terminal.enable {
              windowsterminal.ProfileTemplate = "/etc/wsl-terminal-profile.json";
            }
          )
        );
      in
      {
        imports = [
          # System type layer: minimal -> default -> cli
          inputs.self.modules.nixos.system-cli
          # WSL integration (wsl.conf, users, SSH, SOPS, USBIP, etc.)
          inputs.self.modules.nixos.wsl
          # CrowdStrike Falcon sensor (systemd service + FHS-wrapped package).
          # On WSL2, sensor enters Reduced Functionality Mode (RFM) — compliance
          # inventory only. Detection comes from the Windows-side Falcon WSL2
          # Visibility Plugin. See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md.
          inputs.self.modules.nixos.crowdstrike-falcon
        ];

        # === Enterprise Options ===
        options.enterprise = {
          welcomeMessage = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Show welcome message on first login";
            };
          };

          terminal = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Windows Terminal profile customization via wsl-distribution.conf";
            };

            profileName = lib.mkOption {
              type = lib.types.str;
              default = "NixOS";
              description = "Display name in Windows Terminal tab and profile list";
            };

            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "/etc/nixos.ico";
              description = "Icon path (Linux FS) or emoji for Terminal profile";
            };

            colorScheme = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Windows Terminal color scheme name";
              example = "One Half Dark";
            };

            font = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Font configuration for Terminal profile";
              example = { face = "CaskaydiaMono Nerd Font"; size = 11; };
            };
          };
        };

        # === Enterprise Defaults ===
        # All use mkDefault so team modules and hosts can override.
        config = lib.mkMerge [
          # Core system defaults
          {
            # Generic username for distribution (not personal)
            systemDefault.userName = lib.mkDefault "user";

            # WSL settings -- conservative enterprise defaults
            wsl-settings = {
              hostname = lib.mkDefault "nixos-wsl";
              defaultUser = lib.mkDefault "user";
              sshPort = lib.mkDefault 22;
              userGroups = lib.mkDefault [ "wheel" ];
              sshAuthorizedKeys = lib.mkDefault [ ];
              sops.enable = lib.mkDefault false;
              cuda.enable = lib.mkDefault false;
              binfmt.enable = lib.mkDefault false;
              systemdUserSession.fixRuntimeDir = lib.mkDefault true;
              tarballChecks.enable = lib.mkDefault true;
              # No personal names in enterprise base
              tarballChecks.personalIdentifiers = lib.mkDefault [ ];
            };

            # Passwordless sudo for wheel group (standard for WSL dev images)
            security.sudo.wheelNeedsPassword = lib.mkDefault false;

            # State version for enterprise images
            system.stateVersion = lib.mkDefault "24.11";

            # Suppress zsh-newuser-install prompt for all users.
            # Zsh triggers this wizard when ~/.zshrc doesn't exist.
            # On fresh images before Home Manager activation, no user has .zshrc.
            # /etc/skel/.zshrc covers new users; activation script covers default user.
            environment.etc."skel/.zshrc".text = ''
              # Managed by NixOS -- Home Manager will replace this file.
              # This stub prevents the zsh-newuser-install wizard on first login.
            '';

            # NOTE: hardware.graphics.enable override moved to wsl.nix (applies to all
            # hosts importing the wsl module, not just enterprise). See wsl.nix for details.

            # Enterprise FOSS-clean: allowUnfree false
            # Team modules override this if they need unfree packages
            nixpkgs.config.allowUnfree = lib.mkDefault false;

            # Windows Terminal profile template (installed into system closure)
            environment.etc."wsl-terminal-profile.json" = lib.mkIf cfg.terminal.enable {
              text = terminalProfileJson;
            };

            # WORKAROUND: Override tarball builder to use our wsl-distribution.conf
            # that includes [windowsterminal] section. Upstream NixOS-WSL hardcodes
            # the conf without Terminal profile support.
            # Mirrors upstream build-tarball.nix logic with our enhanced conf.
            system.build.tarballBuilder = lib.mkForce (pkgs.writeShellApplication {
              name = "nixos-wsl-tarball-builder";

              runtimeInputs = [
                pkgs.coreutils
                pkgs.e2fsprogs
                pkgs.gnutar
                pkgs.nixos-install-tools
                pkgs.pigz
                config.nix.package
              ];

              text = ''
                if ! [ $EUID -eq 0 ]; then
                  echo "This script must be run as root!"
                  exit 1
                fi

                out=''${1:-nixos.wsl}

                root=$(mktemp -p "''${TMPDIR:-/tmp}" -d nixos-wsl-tarball.XXXXXXXXXX)
                trap 'chattr -Rf -i "$root" || true && rm -rf "$root" || true' INT TERM EXIT

                chmod o+rx "$root"

                echo "[NixOS-WSL] Installing..."
                nixos-install \
                  --root "$root" \
                  --no-root-passwd \
                  --system ${config.system.build.toplevel} \
                  --substituters ""

                echo "[NixOS-WSL] Adding channel..."
                nixos-enter --root "$root" --command 'HOME=/root nix-channel --add https://github.com/nix-community/NixOS-WSL/archive/refs/heads/main.tar.gz nixos-wsl'

                echo "[NixOS-WSL] Adding wsl-distribution.conf (enterprise-enhanced)"
                install -Dm644 ${enterpriseDistributionConf} "$root/etc/wsl-distribution.conf"
                install -Dm644 ${inputs.nixos-wsl}/assets/NixOS-WSL.ico "$root/etc/nixos.ico"

                echo "[NixOS-WSL] Adding default config..."
                install -Dm644 ${pkgs.writeText "default-configuration.nix" ''
                  { config, lib, pkgs, ... }:
                  {
                    imports = [ <nixos-wsl/modules> ];
                    wsl.enable = true;
                    wsl.defaultUser = "${config.wsl.defaultUser}";
                    system.stateVersion = "${config.system.nixos.release}";
                  }
                ''} "$root/etc/nixos/configuration.nix"

                echo "[NixOS-WSL] Compressing..."
                tar -C "$root" \
                  -c \
                  --sort=name \
                  --mtime='@1' \
                  --owner=0 \
                  --group=0 \
                  --numeric-owner \
                  --hard-dereference \
                  . \
                | pigz > "$out"
              '';
            });
          }

          # CrowdStrike Falcon sensor enterprise defaults (opt-in per policy).
          # The actual module is in modules/programs/crowdstrike-falcon/.
          # Teams and hosts set services.falcon-sensor.package + .cid to activate.
          # NOTE: On WSL2, the sensor provides compliance inventory only (RFM).
          # Hosts enabling this on WSL must also set acknowledgeWslRfm = true.
          # See docs/CROWDSTRIKE-WSL2-SECURITY-BRIEF.md.
          {
            services.falcon-sensor = {
              enable = lib.mkDefault false;
              backend = lib.mkDefault "bpf";
              tags = lib.mkDefault [ "Environment/Enterprise" ];
            };
          }

          # Ensure default user has .zshrc (prevents zsh-newuser-install wizard)
          # /etc/skel only applies to useradd; this covers the pre-created default user.
          {
            system.activationScripts.ensureZshrc = ''
              USER_HOME="/home/${config.wsl-settings.defaultUser}"
              if [ ! -f "$USER_HOME/.zshrc" ]; then
                echo "# Managed by NixOS -- Home Manager will replace this file." > "$USER_HOME/.zshrc"
                chown ${config.wsl-settings.defaultUser}:users "$USER_HOME/.zshrc"
              fi
            '';
          }

          # Git identity reminder — shown until user configures git
          (lib.mkIf cfg.welcomeMessage.enable (
            let
              gitIdentityCheck = ''
                if [ -z "$(git config --global user.name 2>/dev/null)" ] || \
                   [ -z "$(git config --global user.email 2>/dev/null)" ]; then
                  echo "======================================="
                  echo "NixOS-WSL: git identity not configured"
                  echo ""
                  echo "  git config --global user.name \"Your Name\""
                  echo "  git config --global user.email \"you@company.com\""
                  echo "======================================="
                fi
              '';
            in
            {
              programs.bash.interactiveShellInit = gitIdentityCheck;
              programs.zsh.interactiveShellInit = lib.mkAfter gitIdentityCheck;
            }
          ))
        ];
      };

    # =========================================================================
    # Home Manager Module: home-wsl (WSL-only HM layer)
    # =========================================================================
    # The WSL-specific Home Manager modules, factored out of the (now
    # platform-neutral) home-enterprise / home-dev-team tiers so those evaluate
    # on aarch64-darwin. WSL hosts import home-dev-team + home-wsl to get the
    # full WSL experience unchanged; Darwin hosts import home-dev-team +
    # home-darwin instead.
    #
    # This mirrors the NixOS side: the WSL-coupled bits live in the wsl-* tier
    # while the common tier (home-enterprise in enterprise.nix, home-dev-team in
    # dev-team.nix) stays platform-neutral.
    #
    # Contains: wsl-home (WSL user tweaks, Windows aliases), onedrive (sync
    # utilities), windows-terminal (Terminal settings), plus their settings that
    # previously lived inline in home-enterprise/home-dev-team.
    homeManager.home-wsl = { config, lib, pkgs, ... }: {
      imports = [
        # WSL user-level configuration (targets.wsl, Windows interop aliases)
        inputs.self.modules.homeManager.wsl-home
        # OneDrive sync utilities (Windows host integration)
        inputs.self.modules.homeManager.onedrive
        # Windows Terminal settings management
        inputs.self.modules.homeManager.windows-terminal
      ];

      # WSL defaults (overridable by team/host). Moved here from the old
      # WSL-coupled home-enterprise.
      oneDriveUtils.enable = lib.mkDefault true;
      wsl-home-settings.distroName = lib.mkDefault "nixos";

      # === Windows Terminal ===
      # Team-standard font, size, and keybindings for consistent appearance.
      # Moved here from the old home-dev-team (windows-terminal is WSL-only).
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
    };

  };
}
