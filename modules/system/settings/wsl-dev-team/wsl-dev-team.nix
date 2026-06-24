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

          # Add plugdev for hardware programmer access (Dediprog udev rule), and
          # libvirtd/kvm for non-root VM management (systemCli.enableLibvirt). These
          # must be set here, not via users.users.*.extraGroups: wsl.nix replaces
          # extraGroups at mkOverride 90, so the dev-team/system-cli additions would
          # otherwise be dropped on WSL.
          wsl-settings.userGroups = [ "wheel" "plugdev" "libvirtd" "kvm" ];

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
                  REBUILD_RC=0
                  sudo nixos-rebuild switch --flake "$WORKDIR#${sr.flakeAttr}"${lib.optionalString (sr.extraRebuildArgs != [ ]) " ${lib.escapeShellArgs sr.extraRebuildArgs}"} || REBUILD_RC=$?

                  if [ "$REBUILD_RC" -ne 0 ]; then
                    # On NixOS-WSL the new user has no running systemd --user
                    # instance (no session bus), so switch-to-configuration cannot
                    # reload its user units and reports a non-fatal failure
                    # (typically exit 4) even though the system switched and Home
                    # Manager activated. Treat ONLY that case as success: confirm the
                    # declarative rename applied (new user present) and the new user's
                    # Home Manager activation succeeded; otherwise fail loudly.
                    HM_STATUS="$(${pkgs.systemd}/bin/systemctl show -p ExecMainStatus --value "home-manager-$NEW_USER.service" 2>/dev/null || echo unknown)"
                    if ${pkgs.gnugrep}/bin/grep -q "^$NEW_USER:" /etc/passwd && [ "$HM_STATUS" = "0" ]; then
                      echo ""
                      echo "Note: nixos-rebuild reported a non-fatal warning (exit $REBUILD_RC) from"
                      echo "the WSL systemd user-session reload. The system switched and your Home"
                      echo "Manager environment activated successfully, so this is safe to ignore."
                    else
                      echo "Error: nixos-rebuild failed (exit $REBUILD_RC) and the switch did not" >&2
                      echo "apply cleanly (home-manager status: $HM_STATUS). Your user was not changed." >&2
                      exit "$REBUILD_RC"
                    fi
                  fi

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

    # NOTE: the home-dev-team Home Manager bundle moved to the platform-neutral
    # dev-team tier (modules/system/settings/dev-team/dev-team.nix), mirroring
    # nixos.dev-team. Its WSL-only piece (windows-terminal) moved to home-wsl
    # (wsl-enterprise.nix). WSL hosts now import home-dev-team + home-wsl.

  };
}
