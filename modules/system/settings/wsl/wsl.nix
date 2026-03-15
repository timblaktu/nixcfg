# modules/system/settings/wsl/wsl.nix
# WSL NixOS system configuration [N]
#
# Provides:
#   flake.modules.nixos.wsl - Complete WSL system configuration
#
# PLATFORM REQUIREMENTS: NixOS-WSL distribution ONLY
# This is a NixOS system configuration module that requires a full NixOS-WSL distribution.
# It CANNOT be used on vanilla Ubuntu/Debian/Alpine WSL installations.
#
# For portable WSL config (works on ANY WSL distro), see:
#   modules/system/settings/wsl-home/ (Task 3.6) - Home Manager module
#
# Features:
#   - WSL integration (wsl.conf, interop, path handling)
#   - USBIP for USB device passthrough
#   - SSH daemon with WSL-specific settings
#   - SOPS-nix secrets management integration
#   - Security checks for tarball builds
#   - Optional CUDA GPU passthrough
#
# Usage in host config:
#   imports = [
#     inputs.self.modules.nixos.system-cli  # Base system type
#     inputs.self.modules.nixos.wsl         # WSL configuration
#   ];
#   wsl-settings = {
#     hostname = "thinky-nixos";
#     defaultUser = "tim";
#     sshPort = 2223;
#   };
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === NixOS WSL Module ===
    nixos.wsl = { config, lib, pkgs, ... }:
      let
        cfg = config.wsl-settings;

        # Personal identifiers for tarball security checks
        defaultPersonalIdentifiers = [
          "tim"
          "tblack"
          "timblack"
        ];

        # Sensitive environment variable patterns
        defaultSensitivePatterns = [
          "TOKEN"
          "API_KEY"
          "SECRET"
          "PASSWORD"
          "PRIVATE_KEY"
          "AWS_"
          "GITHUB_TOKEN"
          "GITLAB_TOKEN"
          "NPM_TOKEN"
          "OPENAI"
          "ANTHROPIC"
        ];

        # Generate security check script for tarball builds
        securityCheckScript = pkgs.writers.writeBashBin "wsl-tarball-security-check" ''
          set -e

          # Colors for output
          RED='\033[0;31m'
          YELLOW='\033[1;33m'
          GREEN='\033[0;32m'
          BLUE='\033[0;34m'
          NC='\033[0m'

          echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
          echo -e "''${BLUE}    WSL Tarball Security & Privacy Check       ''${NC}"
          echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
          echo ""

          WARNINGS=0
          ERRORS=0
          CONFIG_NAME="''${1:-unknown}"

          # Function to check for personal identifiers
          check_personal() {
            local value="$1"
            local context="$2"
            for id in ${lib.concatStringsSep " " cfg.tarballChecks.personalIdentifiers}; do
              if [[ "$value" =~ $id ]]; then
                echo -e "''${YELLOW}⚠ WARNING: Personal identifier '$id' found in $context: $value''${NC}"
                WARNINGS=$((WARNINGS + 1))
                return 0
              fi
            done
            return 1
          }

          # Check wsl.defaultUser
          DEFAULT_USER="${cfg.defaultUser}"
          if [ -n "$DEFAULT_USER" ]; then
            check_personal "$DEFAULT_USER" "wsl.defaultUser" || true
          fi

          # Check hostname
          HOSTNAME="${cfg.hostname}"
          if [ -n "$HOSTNAME" ]; then
            if check_personal "$HOSTNAME" "networking.hostName"; then
              echo "  Consider using a generic hostname like 'nixos-wsl'"
            fi
          fi

          # Check for sensitive environment variables
          echo "Checking for sensitive environment variables..."
          for pattern in ${lib.concatStringsSep " " cfg.tarballChecks.sensitivePatterns}; do
            if env | grep -q "^$pattern"; then
              echo -e "''${RED}✗ ERROR: Sensitive environment variable pattern detected: $pattern*''${NC}"
              ERRORS=$((ERRORS + 1))
            fi
          done

          # Summary
          echo ""
          echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"
          echo -e "''${BLUE}                   Summary                      ''${NC}"
          echo -e "''${BLUE}════════════════════════════════════════════════''${NC}"

          if [ $ERRORS -gt 0 ]; then
            echo -e "''${RED}✗ Found $ERRORS error(s) - Build blocked''${NC}"
            echo ""
            echo "Critical issues must be resolved before building."
            echo "To bypass checks (NOT RECOMMENDED), run:"
            echo "  WSL_TARBALL_SKIP_CHECKS=1 build-wsl-tarball $CONFIG_NAME"
          elif [ $WARNINGS -gt 0 ]; then
            echo -e "''${YELLOW}⚠ Found $WARNINGS warning(s)''${NC}"
            echo ""
            echo "These warnings indicate personal information that will be"
            echo "included in the tarball. Consider:"
            echo "  1. Creating a generic configuration for distribution"
            echo "  2. Using 'nixos' as defaultUser instead of personal names"
            echo "  3. Removing SSH keys and personal git config"
          else
            echo -e "''${GREEN}✓ No sensitive information detected''${NC}"
            echo "Configuration appears safe for distribution."
          fi

          # Exit with error if critical issues found
          if [ $ERRORS -gt 0 ] && [ "''${WSL_TARBALL_SKIP_CHECKS:-0}" != "1" ]; then
            exit 1
          fi

          if [ "''${WSL_TARBALL_SKIP_CHECKS:-0}" = "1" ]; then
            echo ""
            echo -e "''${YELLOW}⚠ CHECKS BYPASSED - Proceeding despite warnings''${NC}"
          fi
        '';
      in
      {
        imports = [
          # NixOS-WSL module
          inputs.nixos-wsl.nixosModules.default
          # SOPS-nix for secrets
          inputs.sops-nix.nixosModules.sops
        ];

        options.wsl-settings = {
          # === Core WSL Settings ===
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "System hostname";
            example = "thinky-nixos";
          };

          defaultUser = lib.mkOption {
            type = lib.types.str;
            description = "Default WSL user (must be explicitly set)";
            example = "tim";
          };

          userGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "wheel" ];
            description = "Additional user groups";
          };

          # === SSH Settings ===
          sshPort = lib.mkOption {
            type = lib.types.int;
            default = 22;
            description = "SSH port for this WSL instance";
          };

          sshAuthorizedKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "SSH authorized keys for the default user";
          };

          # === Windows Interop ===
          interop = {
            register = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable WSL interop registration";
            };

            includePath = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable integration with Windows paths";
            };

            appendWindowsPath = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Append Windows PATH to Linux PATH";
            };
          };

          automountRoot = lib.mkOption {
            type = lib.types.str;
            default = "/mnt";
            description = "WSL automount root directory";
          };

          # === USBIP Settings ===
          usbip = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable USB/IP for device passthrough";
            };

            autoAttach = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "USB ports to auto-attach (e.g., ['3-1', '3-2'])";
              example = [ "3-1" "3-2" ];
            };

            snippetIpAddress = lib.mkOption {
              type = lib.types.str;
              default = "localhost";
              description = "IP address for USB/IP snippets";
            };

            autoAttachByHardwareId = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  hardwareId = lib.mkOption {
                    type = lib.types.str;
                    description = "USB hardware ID in VID:PID format (e.g., '0403:6001')";
                    example = "0403:6001";
                  };
                  description = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Human-readable description of the USB device";
                    example = "FTDI USB-UART adapter";
                  };
                };
              });
              default = [ ];
              description = ''
                USB devices to auto-attach by hardware ID (VID:PID) using usbipd-win v5.x.
                Creates one systemd service per device that runs
                `usbipd.exe attach --wsl --hardware-id VID:PID --auto-attach`.
                Hardware IDs are stable across USB ports, unlike bus IDs.
              '';
              example = [
                { hardwareId = "0403:6001"; description = "FTDI USB-UART adapter"; }
                { hardwareId = "0955:7523"; description = "NVIDIA Jetson Recovery Mode (APX)"; }
                { hardwareId = "1d6b:0104"; description = "Linux USB Mass Storage Gadget (Jetson initrd-flash)"; }
              ];
            };
          };

          # === Shell Aliases ===
          enableWindowsAliases = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Windows tool aliases (explorer, code, etc.)";
          };

          extraShellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
          };

          # === SOPS-nix Settings ===
          sops = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable SOPS-nix secrets management";
            };

            hostKeyPath = lib.mkOption {
              type = lib.types.str;
              default = "/etc/sops/age.key";
              description = "Path to the host's age private key";
            };
          };

          # === CUDA Settings ===
          cuda = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable WSL CUDA support for GPU passthrough";
            };

            libraryPath = lib.mkOption {
              type = lib.types.str;
              default = "/usr/lib/wsl/lib";
              description = "Path to WSL CUDA driver stubs";
            };

            enableNixLd = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable nix-ld for dynamically linked CUDA binaries";
            };
          };

          # === Container Runtime ===
          containerRuntime = {
            enablePodman = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Enable Podman container runtime at the NixOS system level.
                Required for ISAR/kas builds and general container workflows.

                This sets virtualisation.podman.enable via the system-cli layer,
                which provides the podman daemon, container storage, subuid/subgid
                mapping, and cgroup delegation that rootless and privileged
                containers require. The Nix devshell can provide the podman
                binary, but system-level infrastructure is not possible to
                provision from a devshell.

                On Darwin, container runtimes are managed externally (Docker
                Desktop) and this option has no counterpart. The n3x devshell
                detects Darwin and uses docker with clear error messaging when
                Docker Desktop is not installed.

                Requires the system-cli layer to be imported alongside this
                module (per standard WSL module usage).
              '';
            };
          };

          # === Cross-Architecture Build Support (binfmt + QEMU) ===
          binfmt = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable QEMU user-mode emulation via binfmt_misc for cross-architecture builds";
            };

            emulatedSystems = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "aarch64-linux" ];
              description = "Systems to emulate (passed to boot.binfmt.emulatedSystems)";
            };

            matchCredentials = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable C flag for setuid binaries in chroot/container postinst scripts";
            };
          };

          # === Systemd User Session Fix ===
          # WSL overlays /run/user with its own tmpfs, causing ownership issues
          # that break systemd user sessions, dbus, and XDG_RUNTIME_DIR
          systemdUserSession = {
            fixRuntimeDir = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Fix /run/user ownership for WSL systemd user sessions at boot";
            };

            enableLinger = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable user linger for persistent systemd user session";
            };
          };

          # === Environment Capture for Systemd-spawned Shells ===
          envCapture = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Capture Windows PATH and WSLg variables at boot for systemd-spawned shells";
            };
          };

          # === Tarball Security Checks ===
          tarballChecks = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable security checks for tarball builds";
            };

            personalIdentifiers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = defaultPersonalIdentifiers;
              description = "Personal identifiers to check for in tarball builds";
            };

            sensitivePatterns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = defaultSensitivePatterns;
              description = "Sensitive environment variable patterns";
            };
          };
        };

        config = lib.mkMerge [
          # === Assertions ===
          {
            assertions = [
              {
                assertion = cfg.hostname != "";
                message = "wsl-settings.hostname must not be empty";
              }
              {
                assertion = cfg.defaultUser != "";
                message = "wsl-settings.defaultUser must not be empty";
              }
              {
                assertion = cfg.sshPort > 0 && cfg.sshPort < 65536;
                message = "wsl-settings.sshPort must be a valid port number (1-65535)";
              }
              {
                assertion = builtins.elem "wheel" cfg.userGroups;
                message = "wsl-settings.userGroups should include 'wheel' for sudo access";
              }
            ];
          }

          # === Core WSL Configuration ===
          {
            # Enable WSL
            wsl = {
              enable = true;
              inherit (cfg) defaultUser;
              interop.includePath = cfg.interop.includePath;
              interop.register = cfg.interop.register;
              wslConf.automount.root = cfg.automountRoot;
              wslConf.interop.appendWindowsPath = cfg.interop.appendWindowsPath;
            };

            # Hostname
            networking.hostName = cfg.hostname;

            # User configuration — fully declarative (no imperative useradd/passwd)
            users.mutableUsers = lib.mkDefault false;
            users.users.${cfg.defaultUser} = {
              isNormalUser = lib.mkDefault true;
              # mkOverride 90: NixOS-WSL's wsl-distro.nix sets extraGroups = [ "wheel" ]
              # as a bare value (priority 100), which silently overrides mkDefault (1000).
              # We need priority < 100 so host userGroups (e.g., [ "wheel" "dialout" ])
              # actually take effect. Hosts can still use mkForce (50) to override.
              extraGroups = lib.mkOverride 90 cfg.userGroups;
              hashedPassword = lib.mkDefault ""; # No password needed in WSL
              openssh.authorizedKeys.keys = lib.mkIf (cfg.sshAuthorizedKeys != [ ]) cfg.sshAuthorizedKeys;
            };

            # SSH daemon
            services.openssh = {
              enable = lib.mkDefault true;
              ports = [ cfg.sshPort ];
            };

            # WSL-specific packages
            environment.systemPackages = with pkgs; [
              wslu # WSL utilities
            ];

            # Disable Mesa/LLVM graphics drivers unless CUDA is needed (~791 MiB savings).
            # NixOS-WSL's wsl-distro.nix unconditionally sets hardware.graphics.enable = true
            # (bare value, priority 100). For CLI-only WSL images this is unnecessary — WSLg
            # provides its own drivers. mkOverride 90 beats upstream's bare value.
            # When wsl-settings.cuda.enable is true, this automatically re-enables graphics.
            # Hosts needing graphics without CUDA can use mkForce true.
            hardware.graphics.enable = lib.mkOverride 90 cfg.cuda.enable;

            # Disable services that don't make sense in WSL
            services.xserver.enable = lib.mkDefault false;
            services.printing.enable = lib.mkDefault false;
          }

          # === Windows Drive Mount Recovery ===
          # WSL generates fstab entries like "C:134 /mnt/c 9p" at boot using internal
          # 9p tag IDs. If a process unmounts these drives (e.g., n3x kas-build prevents
          # sgdisk sync() hangs by temporarily unmounting /mnt/c) and gets killed before
          # remounting, the 9p tag is invalidated. The systemd mount unit then fails with
          # "special device C:134 does not exist" because the tag no longer matches.
          # This service detects missing Windows drive mounts and remounts them using the
          # drvfs device name (e.g., "C:") which always works regardless of tag state.
          {
            systemd.services."wsl-recover-windows-mounts" = {
              description = "Recover unmounted Windows drive mounts in WSL";
              before = [ "local-fs.target" ];
              wantedBy = [ "local-fs.target" ];
              unitConfig = {
                DefaultDependencies = false;
                ConditionPathExists = cfg.automountRoot;
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "wsl-recover-windows-mounts" ''
                  automount_root="${cfg.automountRoot}"
                  recovered=0

                  # Parse /etc/fstab for 9p mounts under the automount root
                  while IFS=' ' read -r device mountpoint fstype _rest; do
                    # Skip comments and non-9p entries
                    [[ "$device" == \#* ]] && continue
                    [[ "$fstype" != "9p" ]] && continue
                    # Only recover /mnt/[a-z] Windows drive mounts
                    [[ "$mountpoint" != "$automount_root"/[a-z] ]] && continue

                    # Check if already mounted
                    if ${pkgs.util-linux}/bin/mountpoint -q "$mountpoint" 2>/dev/null; then
                      continue
                    fi

                    # Extract drive letter from mount point (e.g., /mnt/c -> C)
                    drive_letter="''${mountpoint##*/}"
                    drive_letter="$(echo "$drive_letter" | tr '[:lower:]' '[:upper:]')"

                    echo "Recovering mount: $mountpoint (drive $drive_letter:)"
                    drvfs_opts="metadata,uid=${toString config.users.users.${cfg.defaultUser}.uid},gid=${toString config.users.groups.users.gid}"
                    if ${pkgs.util-linux}/bin/mount -t drvfs "''${drive_letter}:" "$mountpoint" -o "$drvfs_opts" 2>&1; then
                      echo "Recovered: $mountpoint"
                      recovered=$((recovered + 1))
                    else
                      echo "Failed to recover $mountpoint — may need: wsl --shutdown" >&2
                    fi
                  done < /etc/fstab

                  if [ "$recovered" -gt 0 ]; then
                    echo "Recovered $recovered Windows drive mount(s)"
                  fi
                '';
              };
            };
          }

          # === USBIP Configuration ===
          (lib.mkIf cfg.usbip.enable {
            wsl.usbip = {
              enable = true;
              inherit (cfg.usbip) autoAttach;
              inherit (cfg.usbip) snippetIpAddress;
            };

            # Runtime check for Windows-side usbipd-win dependency.
            # During activation (root/systemd context), appendWindowsPath interop
            # isn't active, so we must explicitly add the winget install location.
            system.activationScripts.checkUsbipd = lib.stringAfter [ ] ''
              if ! PATH="$PATH:${cfg.automountRoot}/c/Program Files/usbipd-win" command -v usbipd.exe >/dev/null 2>&1; then
                echo -e "\033[1;31mWARNING: usbipd.exe not found. Install from admin PowerShell: winget install -e --id dorssel.usbipd-win\033[0m"
              fi
            '';
          })

          # === USBIP Hardware-ID Auto-Attach Services ===
          # One systemd service per hardware ID, calling usbipd.exe via binfmt interop.
          # Uses hardware IDs (VID:PID) which are stable across USB ports, unlike bus IDs.
          # Requires usbipd-win v5.x on the Windows side.
          (lib.mkIf (cfg.usbip.enable && cfg.usbip.autoAttachByHardwareId != [ ]) {
            assertions = map
              (dev: {
                assertion = builtins.match "[0-9a-fA-F]{4}:[0-9a-fA-F]{4}" dev.hardwareId != null;
                message = "wsl-settings.usbip.autoAttachByHardwareId: '${dev.hardwareId}' is not a valid VID:PID (expected format: 0403:6001)";
              })
              cfg.usbip.autoAttachByHardwareId;

            systemd.services = lib.listToAttrs (map
              (dev:
                let
                  safeName = builtins.replaceStrings [ ":" ] [ "-" ] dev.hardwareId;
                  desc = if dev.description != "" then " (${dev.description})" else "";
                in
                lib.nameValuePair "usbipd-auto-attach-hwid-${safeName}" {
                  description = "Auto-attach USB device ${dev.hardwareId}${desc} via usbipd-win";
                  after = [ "local-fs.target" "systemd-binfmt.service" "wsl-recover-windows-mounts.service" ];
                  wantedBy = [ "multi-user.target" ];
                  unitConfig = {
                    ConditionPathExists = "${cfg.automountRoot}/c/Program Files/usbipd-win/usbipd.exe";
                  };
                  serviceConfig = {
                    Type = "simple";
                    Restart = "always";
                    RestartSec = "5s";
                    ExecStart = pkgs.writeShellScript "usbipd-auto-attach-${safeName}" ''
                      USBIPD="${cfg.automountRoot}/c/Program Files/usbipd-win/usbipd.exe"
                      HWID="${dev.hardwareId}"

                      # Poll until device appears on the Windows USB bus.
                      # usbipd attach --auto-attach requires the device to be present
                      # at invocation — it watches for reconnects, not first appearance.
                      echo "Watching for USB device $HWID${desc}..."
                      while ! "$USBIPD" list 2>/dev/null | grep -qi "$HWID"; do
                        sleep 5
                      done

                      echo "Device $HWID found, attaching with auto-reattach..."
                      exec "$USBIPD" attach --wsl --hardware-id "$HWID" --auto-attach
                    '';
                  };
                })
              cfg.usbip.autoAttachByHardwareId);
          })

          # === Windows Aliases ===
          (lib.mkIf cfg.enableWindowsAliases {
            environment.shellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
            } // cfg.extraShellAliases;
          })

          # === SOPS-nix Configuration ===
          (lib.mkIf cfg.sops.enable {
            sops = {
              age.keyFile = cfg.sops.hostKeyPath;
              gnupg.sshKeyPaths = [ ];
            };

            systemd.tmpfiles.rules = [
              "d /etc/sops 0755 root root -"
            ];
          })

          # === CUDA Configuration ===
          (lib.mkIf cfg.cuda.enable {
            assertions = [
              {
                assertion = config.wsl.enable;
                message = "wsl-settings.cuda requires WSL to be enabled";
              }
            ];

            # Enable GPU passthrough for CUDA workloads.
            # hardware.graphics pulls in Mesa/LLVM; wsl-enterprise disables it by default.
            # When CUDA is enabled, wsl-enterprise's conditional re-enables graphics,
            # and useWindowsDriver adds the CUDA/d3d12 stubs from /usr/lib/wsl/lib/.
            wsl.useWindowsDriver = true;

            # Enable nix-ld for dynamically linked CUDA binaries
            programs.nix-ld = lib.mkIf cfg.cuda.enableNixLd {
              enable = true;
              libraries = with pkgs; [
                stdenv.cc.cc.lib
                zlib
              ];
            };

            # Set LD_LIBRARY_PATH for CUDA
            environment.variables = {
              LD_LIBRARY_PATH = lib.mkDefault cfg.cuda.libraryPath;
            };

            environment.sessionVariables = {
              LD_LIBRARY_PATH = lib.mkDefault cfg.cuda.libraryPath;
            };

            warnings = [
              ''
                WSL CUDA support enabled. The NVIDIA driver is provided by Windows.
                - Run 'nvidia-smi' to verify GPU access
                - Ensure Windows has NVIDIA driver version 525.60+ for CUDA 12 support
                - WSL CUDA stubs are at: ${cfg.cuda.libraryPath}
              ''
            ];
          })

          # === Container Runtime ===
          # WSL hosts are development machines that need container runtimes
          # for ISAR/kas builds and general container workflows. This delegates
          # to system-cli's enablePodman which configures virtualisation.podman
          # with daemon, storage, subuid/subgid, and auto-prune.
          (lib.mkIf cfg.containerRuntime.enablePodman {
            systemCli.enablePodman = true;
          })

          # === Cross-Architecture Build Support (binfmt + QEMU) ===
          (lib.mkIf cfg.binfmt.enable {
            boot.binfmt.emulatedSystems = cfg.binfmt.emulatedSystems;
            boot.binfmt.preferStaticEmulators = true;
            boot.binfmt.registrations = lib.listToAttrs (
              map
                (system: {
                  name = system;
                  value.matchCredentials = cfg.binfmt.matchCredentials;
                })
                cfg.binfmt.emulatedSystems
            );
          })

          # === Systemd User Session Fix ===
          # WSL overlays /run/user with root-owned tmpfs, breaking systemd user sessions.
          # See: microsoft/WSL#13143, nix-community/NixOS-WSL#346
          (lib.mkIf cfg.systemdUserSession.fixRuntimeDir (
            let
              uid = toString config.users.users.${cfg.defaultUser}.uid;
            in
            {
              # Oneshot service to fix /run/user/<UID> ownership after WSL overlay
              systemd.services."fix-wsl-user-runtime-dir" = {
                description = "Fix /run/user/${uid} ownership for WSL systemd user session";
                documentation = [ "man:systemd-user-runtime-dir(8)" ];
                before = [ "user@${uid}.service" ];
                after = [ "user-runtime-dir@${uid}.service" ];
                wants = [ "user-runtime-dir@${uid}.service" ];
                wantedBy = [ "multi-user.target" ];
                unitConfig = {
                  StopWhenUnneeded = true;
                };
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = pkgs.writeShellScript "fix-wsl-user-runtime-dir" ''
                    RUNDIR="/run/user/${uid}"
                    if [ -d "$RUNDIR" ] && [ "$(${pkgs.coreutils}/bin/stat -c %u "$RUNDIR")" != "${uid}" ]; then
                      ${pkgs.coreutils}/bin/chown ${uid} "$RUNDIR"
                      ${pkgs.coreutils}/bin/chmod 0700 "$RUNDIR"
                      echo "Fixed ownership of $RUNDIR for ${cfg.defaultUser} (UID ${uid})"
                    fi
                  '';
                };
              };

              # Tmpfiles safety net
              systemd.tmpfiles.rules = [
                "d /run/user/${uid} 0700 ${cfg.defaultUser} users -"
              ];
            }
          ))

          # User linger for persistent user session
          (lib.mkIf cfg.systemdUserSession.enableLinger {
            users.users.${cfg.defaultUser}.linger = true;
          })

          # === WSL Environment Capture for Systemd-spawned Shells ===
          # UPSTREAM-WORTHY: nix-community/NixOS-WSL#171, #375
          #
          # PROBLEM: WSL injects environment variables (Windows PATH, WSLg display
          # vars, WSL_INTEROP) into Relay-spawned login shells only. Processes spawned
          # by systemd (tmux, SSH, user services) never receive these because systemd
          # starts at VM boot before any Windows Terminal session exists. NixOS-WSL's
          # split-path is a classifier, not a provider: it cannot discover missing paths.
          #
          # SOLUTION: A oneshot boot service queries Windows PATH via cmd.exe (binfmt
          # interop), probes filesystem for WSLg state, and writes a sourceable cache
          # to /run/wsl-env. An environment.extraInit snippet (mkAfter split-path)
          # sources the cache only when WSLPATH is empty (systemd-spawned shells).
          #
          # REFERENCES: microsoft/WSL#8842, #9213, #10205
          (lib.mkIf cfg.envCapture.enable {
            systemd.services."wsl-env-capture" = {
              description = "Capture Windows PATH and WSLg variables for systemd-spawned shells";
              after = [ "local-fs.target" "systemd-binfmt.service" "wsl-recover-windows-mounts.service" ];
              before = [ "multi-user.target" ];
              wantedBy = [ "multi-user.target" ];
              unitConfig = {
                ConditionPathExists = "${cfg.automountRoot}/c/WINDOWS/system32/cmd.exe";
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "wsl-env-capture" ''
                  automount_root="${cfg.automountRoot}"

                  # Query Windows PATH via binfmt interop
                  # Use printf throughout: Windows paths contain \U, \W, \v which echo
                  # interprets as escape sequences
                  if win_path=$("''${automount_root}/c/WINDOWS/system32/cmd.exe" /c "echo %PATH%" 2>/dev/null); then
                    # Remove trailing carriage return from cmd.exe output
                    win_path=$(printf '%s' "$win_path" | tr -d '\r')
                  else
                    echo "WARNING: Could not query Windows PATH via cmd.exe" >&2
                    win_path=""
                  fi

                  # Convert Windows paths to WSL mount paths
                  # Windows PATH is semicolon-separated: C:\foo;D:\bar
                  # Result: /mnt/c/foo:/mnt/d/bar
                  wsl_path=""
                  IFS=';' read -ra win_entries <<< "$win_path"
                  for entry in "''${win_entries[@]}"; do
                    [ -z "$entry" ] && continue
                    # Match drive letter prefix (C:, D:, etc.)
                    if [[ "$entry" =~ ^([A-Za-z]): ]]; then
                      drive_lower=$(printf '%s' "''${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
                      rest="''${entry#[A-Za-z]:}"
                      rest=$(printf '%s' "$rest" | tr '\\' '/')
                      linux_path="''${automount_root}/''${drive_lower}''${rest}"
                      linux_path="''${linux_path%/}"
                      if [ -n "$wsl_path" ]; then
                        wsl_path="''${wsl_path}:''${linux_path}"
                      else
                        wsl_path="$linux_path"
                      fi
                    fi
                  done

                  # Probe filesystem for WSLg state (stable paths, no cmd.exe needed)
                  display=""
                  wayland_display=""
                  pulse_server=""
                  [ -e /tmp/.X11-unix/X0 ] && display=":0"
                  [ -e /mnt/wslg/runtime-dir/wayland-0 ] && wayland_display="wayland-0"
                  [ -e /mnt/wslg/PulseServer ] && pulse_server="/mnt/wslg/PulseServer"

                  # Write sourceable cache (printf, not echo, for safety)
                  {
                    printf 'WSLPATH="%s"\nexport WSLPATH\n' "$wsl_path"
                    [ -n "$display" ] && printf 'DISPLAY="%s"\nexport DISPLAY\n' "$display"
                    [ -n "$wayland_display" ] && printf 'WAYLAND_DISPLAY="%s"\nexport WAYLAND_DISPLAY\n' "$wayland_display"
                    [ -n "$pulse_server" ] && printf 'PULSE_SERVER="%s"\nexport PULSE_SERVER\n' "$pulse_server"
                    ${lib.optionalString cfg.interop.includePath ''printf 'PATH="''${PATH:+$PATH:}$WSLPATH"\nexport PATH\n' ''}
                  } > /run/wsl-env

                  chmod 644 /run/wsl-env
                  echo "WSL environment captured to /run/wsl-env ($(wc -c < /run/wsl-env) bytes)"
                '';
              };
            };

            # Use interactiveShellInit (goes into /etc/bashrc + /etc/zshrc) rather
            # than extraInit (goes into /etc/set-environment).  tmux panes inherit
            # __NIXOS_SET_ENVIRONMENT_DONE from the server, which causes
            # /etc/set-environment to be skipped entirely in new panes.
            environment.interactiveShellInit = lib.mkAfter ''
              if [ -z "''${WSLPATH-}" ] && [ -f /run/wsl-env ]; then
                . /run/wsl-env
              fi
            '';
          })

          # === Tarball Security Checks ===
          (lib.mkIf cfg.tarballChecks.enable {
            system.build.tarballSecurityCheck = securityCheckScript;
          })
        ];
      };
  };
}
