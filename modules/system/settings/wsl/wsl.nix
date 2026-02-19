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

            # Disable services that don't make sense in WSL
            services.xserver.enable = lib.mkDefault false;
            services.printing.enable = lib.mkDefault false;
          }

          # === USBIP Configuration ===
          (lib.mkIf cfg.usbip.enable {
            wsl.usbip = {
              enable = true;
              inherit (cfg.usbip) autoAttach;
              inherit (cfg.usbip) snippetIpAddress;
            };
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

          # === Tarball Security Checks ===
          (lib.mkIf cfg.tarballChecks.enable {
            system.build.tarballSecurityCheck = securityCheckScript;
          })
        ];
      };
  };
}
