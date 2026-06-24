# modules/system/types/3-cli/cli.nix
# CLI-focused system configuration layer
#
# Provides:
#   flake.modules.nixos.system-cli - NixOS with full CLI tooling
#   flake.modules.darwin.system-cli - Darwin with full CLI tooling
#   flake.modules.homeManager.home-cli - Home Manager with full CLI tooling
#
# This layer IMPORTS system-default and adds:
#   - SSH daemon with secure defaults
#   - SSH authorized_keys management
#   - Advanced CLI/development tools
#   - Git configuration
#   - Network utilities
#   - Optional container runtime (Docker/Podman)
#
# Does NOT include:
#   - Desktop environments (4-desktop)
#   - GUI applications (4-desktop)
#
# Usage in host config:
#   imports = [ inputs.self.modules.nixos.system-cli ];
#   systemCli = {
#     sshAuthorizedKeys = [ "ssh-ed25519 AAAA..." ];
#     enableDocker = true;
#   };
#   # Also set systemDefault options as needed
#   systemDefault.userName = "tim";
{ config, lib, inputs, ... }:
{
  flake.modules = {
    # === NixOS CLI Module ===
    nixos.system-cli = { config, lib, pkgs, ... }:
      let
        cfg = config.systemCli;
        defaultCfg = config.systemDefault;
      in
      {
        imports = [
          # Import default layer
          inputs.self.modules.nixos.system-default
        ];

        options.systemCli = {
          # SSH daemon configuration
          sshEnable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable SSH daemon";
          };

          sshPasswordAuth = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Allow SSH password authentication (not recommended)";
          };

          sshRootLogin = lib.mkOption {
            type = lib.types.enum [ "no" "yes" "prohibit-password" "forced-commands-only" ];
            default = "no";
            description = "SSH root login policy";
          };

          sshAuthorizedKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "SSH public keys for the primary user";
            example = [ "ssh-ed25519 AAAA... user@host" ];
          };

          # Git configuration
          gitDefaultBranch = lib.mkOption {
            type = lib.types.str;
            default = "main";
            description = "Default git branch name";
          };

          gitEditor = lib.mkOption {
            type = lib.types.str;
            default = "nvim";
            description = "Default git editor";
          };

          # Container runtime
          enableDocker = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Docker container runtime";
          };

          enablePodman = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Podman container runtime";
          };

          enableLibvirt = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable the libvirt/KVM virtualization stack: the libvirtd daemon,
              QEMU, and the "default" NAT network (virbr0, 192.168.122.0/24). Used
              to host local VMs such as the AMI firmware build VM (whose provisioner
              hard-codes <source network='default'/>). Adds the primary user to the
              libvirtd and kvm groups. On WSL these groups must also be listed in
              wsl-settings.userGroups (wsl.nix overrides extraGroups at priority 90).
            '';
          };

          # Network tools
          enableNetworkTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install network diagnostic tools";
          };

          # Development packages
          enableDevTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install development CLI tools";
          };

          # Additional CLI packages
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional CLI packages to install";
          };

          # Claude Code enterprise settings
          enableClaudeCodeEnterprise = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Claude Code enterprise managed settings at /etc/claude-code/managed-settings.json";
          };
        };

        config = lib.mkMerge [
          # Core CLI configuration
          {
            # SSH authorized keys for primary user
            users.users.${defaultCfg.userName}.openssh.authorizedKeys.keys =
              lib.mkIf (cfg.sshAuthorizedKeys != [ ]) cfg.sshAuthorizedKeys;

            # Git configuration system-wide
            programs.git = {
              enable = lib.mkDefault true;
              config = {
                init.defaultBranch = lib.mkDefault cfg.gitDefaultBranch;
                core.editor = lib.mkDefault cfg.gitEditor;
                pull.rebase = lib.mkDefault false;
                push.autoSetupRemote = lib.mkDefault true;
              };
            };

            # Enhanced shell prompt and aliases
            environment.shellAliases = {
              # File listing with eza
              ls = "eza -al --icons -s size";
              la = "eza -a --icons";
              ll = lib.mkForce "eza -l --icons";
              lla = "eza -al --icons";
              lh = "eza -al --icons -s modified";
              lt = "eza --tree --icons -L 3 --git-ignore";
              # Git shortcuts
              gs = "git status";
              gd = "git diff";
              gl = "git log --oneline -20";
              # System shortcuts
              nixfmt = "nixpkgs-fmt";
              rebuild = "sudo nixos-rebuild switch";
            };

            # Enable common CLI programs
            programs.neovim = {
              enable = lib.mkDefault true;
              defaultEditor = lib.mkDefault true;
              viAlias = lib.mkDefault true;
              vimAlias = lib.mkDefault true;
            };

            programs.tmux = {
              enable = lib.mkDefault true;
              clock24 = lib.mkDefault true;
              terminal = lib.mkDefault "screen-256color";
            };
          }

          # SSH daemon configuration
          (lib.mkIf cfg.sshEnable {
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = lib.mkDefault cfg.sshRootLogin;
                PasswordAuthentication = lib.mkDefault cfg.sshPasswordAuth;
              };
            };
          })

          # Development tools
          (lib.mkIf cfg.enableDevTools {
            environment.systemPackages = with pkgs; [
              # Modern CLI replacements
              eza # Better ls
              bat # Better cat
              delta # Better diff
              dust # Better du
              duf # Better df
              procs # Better ps
              bottom # Better top
              hyperfine # Benchmarking

              # Development essentials
              jq # JSON processor
              yq # YAML processor
              fzf # Fuzzy finder
              tree # Directory tree
              tokei # Code statistics
              direnv # Directory-specific environments
              shellcheck # Shell script analysis
              nixpkgs-fmt # Nix formatter

              # Search and navigation
              zoxide # Smarter cd
              broot # Directory navigator

              # Compression
              unzip
              p7zip

              # Misc utilities
              tldr # Simplified man pages
              just # Command runner
            ] ++ cfg.additionalPackages;

            # Enable direnv integration
            programs.direnv = {
              enable = lib.mkDefault true;
              nix-direnv.enable = lib.mkDefault true;
            };
          })

          # Network tools
          (lib.mkIf cfg.enableNetworkTools {
            environment.systemPackages = with pkgs; [
              # Network diagnostics
              netcat-openbsd
              dig # DNS lookup
              whois
              traceroute
              mtr # Better traceroute
              nmap # Port scanner
              tcpdump # Packet capture
              iperf3 # Network performance
              curlie # Better curl with colors
              httpie # HTTP client
              wget2 # Better wget
              aria2 # Download manager
            ];

            # Enable mtr for regular users
            programs.mtr.enable = lib.mkDefault true;
          })

          # Docker configuration
          (lib.mkIf cfg.enableDocker {
            virtualisation.docker = {
              enable = true;
              autoPrune = {
                enable = lib.mkDefault true;
                dates = lib.mkDefault "weekly";
              };
            };
            # Add user to docker group
            users.users.${defaultCfg.userName}.extraGroups = [ "docker" ];
          })

          # Podman configuration
          (lib.mkIf cfg.enablePodman {
            virtualisation.podman = {
              enable = true;
              dockerCompat = lib.mkDefault (!cfg.enableDocker);
              autoPrune = {
                enable = lib.mkDefault true;
                dates = lib.mkDefault "weekly";
              };
            };

            # Enable cgroup delegation for rootless containers (required by kind/k3d)
            systemd.services."user@".serviceConfig.Delegate = "yes";
          })

          # Libvirt / KVM virtualization (firmware build VM, local VMs)
          (lib.mkIf cfg.enableLibvirt {
            virtualisation.libvirtd = {
              enable = true;
              # Do NOT auto-start guests on host boot; a dev box should bring the
              # (heavy) firmware VM up explicitly, not on every login.
              onBoot = "ignore";
              onShutdown = "shutdown";
            };

            # virsh / qemu-img available for interactive use outside the Nix app too.
            environment.systemPackages = [ pkgs.libvirt pkgs.qemu-utils ];

            # Primary user manages VMs without sudo. NOTE: on WSL this is overridden
            # by wsl.nix (mkOverride 90 on extraGroups), so wsl-dev-team also lists
            # "libvirtd"/"kvm" in wsl-settings.userGroups.
            users.users.${defaultCfg.userName}.extraGroups = [ "libvirtd" "kvm" ];

            # Let guests on virbr0 reach the host's dnsmasq (DHCP/DNS) and routing.
            networking.firewall.trustedInterfaces = [ "virbr0" ];

            # Enabling libvirtd does NOT create libvirt's "default" NAT network, yet
            # tools that hard-code <source network='default'/> (the AMI firmware build
            # VM provisioner polls `virsh net-dhcp-leases default`) require it defined,
            # autostarted, and serving DHCP. Define + start it once libvirtd is up.
            systemd.services.libvirt-default-network = {
              description = "Define and start the libvirt default NAT network";
              after = [ "libvirtd.service" ];
              requires = [ "libvirtd.service" ];
              wantedBy = [ "multi-user.target" ];
              path = [ pkgs.libvirt pkgs.gawk ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script =
                let
                  netXml = pkgs.writeText "libvirt-default-net.xml" ''
                    <network>
                      <name>default</name>
                      <forward mode='nat'/>
                      <bridge name='virbr0' stp='on' delay='0'/>
                      <ip address='192.168.122.1' netmask='255.255.255.0'>
                        <dhcp>
                          <range start='192.168.122.2' end='192.168.122.254'/>
                        </dhcp>
                      </ip>
                    </network>
                  '';
                in
                ''
                  uri=qemu:///system
                  if ! virsh -c "$uri" net-info default >/dev/null 2>&1; then
                    virsh -c "$uri" net-define ${netXml}
                  fi
                  virsh -c "$uri" net-autostart default || true
                  if [ "$(virsh -c "$uri" net-info default 2>/dev/null | awk '/^Active:/ {print $2}')" != "yes" ]; then
                    virsh -c "$uri" net-start default || true
                  fi
                '';
            };
          })

          # Claude Code Enterprise Settings
          (lib.mkIf cfg.enableClaudeCodeEnterprise {
            environment.etc."claude-code/managed-settings.json" = {
              text = builtins.toJSON {
                # Top-precedence settings that cannot be overridden by users
                model = "opus";

                # Security and permissions (organization-wide enforcement) - v2.0 schema
                permissions = {
                  allow = [
                    "Bash"
                    "mcp__context7"
                    "mcp__mcp-nixos"
                    "mcp__sequential-thinking"
                    "Read"
                    "Write"
                    "Edit"
                    "WebFetch"
                  ];
                  deny = [
                    "Search"
                    "Find"
                    "Bash(rm -rf /*)"
                    "Read(.env)"
                    "Write(/etc/passwd)"
                  ];
                  ask = [ ];
                  defaultMode = "default";
                  additionalDirectories = [ ];
                };

                # Environment variables
                env = {
                  CLAUDE_CODE_ENABLE_TELEMETRY = "0";
                };

                # Statusline configuration (consistent across all accounts)
                statusLine = {
                  type = "command";
                  command = "claude-statusline-powerline";
                  padding = 0;
                };

                # Project overrides
                projectOverrides = {
                  enabled = true;
                  searchPaths = [
                    ".claude/settings.json"
                    ".claude.json"
                    "claude.config.json"
                  ];
                };
              };
              mode = "0644";
            };
          })
        ];
      };

    # === Darwin CLI Module ===
    darwin.system-cli = { config, lib, pkgs, ... }:
      let
        cfg = config.systemCli;
      in
      {
        imports = [
          # Import default layer
          inputs.self.modules.darwin.system-default
        ];

        options.systemCli = {
          # Git configuration
          gitDefaultBranch = lib.mkOption {
            type = lib.types.str;
            default = "main";
            description = "Default git branch name";
          };

          gitEditor = lib.mkOption {
            type = lib.types.str;
            default = "nvim";
            description = "Default git editor";
          };

          # Development packages
          enableDevTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install development CLI tools";
          };

          # Network tools
          enableNetworkTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Install network diagnostic tools";
          };

          # Additional CLI packages
          additionalPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional CLI packages to install";
          };
        };

        config = lib.mkMerge [
          # Core CLI configuration
          {
            # Git configuration system-wide
            programs.git = {
              enable = lib.mkDefault true;
              config = {
                init.defaultBranch = lib.mkDefault cfg.gitDefaultBranch;
                core.editor = lib.mkDefault cfg.gitEditor;
                pull.rebase = lib.mkDefault false;
                push.autoSetupRemote = lib.mkDefault true;
              };
            };

            # Enhanced shell aliases
            environment.shellAliases = {
              # File listing with eza
              ls = "eza -al --icons -s size";
              la = "eza -a --icons";
              ll = lib.mkForce "eza -l --icons";
              lla = "eza -al --icons";
              lh = "eza -al --icons -s modified";
              lt = "eza --tree --icons -L 3 --git-ignore";
              # Git shortcuts
              gs = "git status";
              gd = "git diff";
              gl = "git log --oneline -20";
              # System shortcuts
              nixfmt = "nixpkgs-fmt";
            };
          }

          # Development tools
          (lib.mkIf cfg.enableDevTools {
            environment.systemPackages = with pkgs; [
              # Modern CLI replacements
              eza # Better ls
              bat # Better cat
              delta # Better diff
              dust # Better du
              duf # Better df
              procs # Better ps
              bottom # Better top
              hyperfine # Benchmarking

              # Development essentials
              jq # JSON processor
              yq # YAML processor
              fzf # Fuzzy finder
              tree # Directory tree
              tokei # Code statistics
              direnv # Directory-specific environments
              shellcheck # Shell script analysis
              nixpkgs-fmt # Nix formatter
              neovim # Editor

              # Search and navigation
              zoxide # Smarter cd
              broot # Directory navigator

              # Compression
              unzip
              p7zip

              # Misc utilities
              tldr # Simplified man pages
              just # Command runner
            ] ++ cfg.additionalPackages;

            # Enable direnv integration
            programs.direnv = {
              enable = lib.mkDefault true;
              nix-direnv.enable = lib.mkDefault true;
            };
          })

          # Network tools
          (lib.mkIf cfg.enableNetworkTools {
            environment.systemPackages = with pkgs; [
              # Network diagnostics (Darwin-compatible subset)
              netcat
              whois
              mtr # Better traceroute
              nmap # Port scanner
              iperf3 # Network performance
              curlie # Better curl with colors
              httpie # HTTP client
              wget # Note: wget2 may have Darwin issues
              aria2 # Download manager
            ];
          })
        ];
      };

    # === Home Manager CLI Module ===
    homeManager.home-cli = { config, lib, pkgs, ... }:
      let
        cfg = config.homeCli;
      in
      {
        imports = [
          # Import default layer
          inputs.self.modules.homeManager.home-default
        ];

        options.homeCli = {
          # Git configuration
          enableGit = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Git configuration";
          };

          # Tmux configuration
          enableTmux = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Tmux configuration";
          };

          # Neovim configuration
          enableNeovim = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Neovim (via nixvim)";
          };

          # Yazi TUI file manager
          enableYazi = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Yazi terminal file manager";
          };

          # Shell aliases
          shellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Additional shell aliases";
          };

          # CLI packages
          cliPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = with pkgs; [
              # Modern CLI replacements (subset for HM)
              dua # Disk usage analyzer
              glow # Markdown renderer
              nixfmt

              # Media tools
              ffmpeg
              ffmpegthumbnailer
              imagemagick
              yt-dlp

              # Terminal capture
              asciinema # Record terminal sessions (.cast)
              asciinema-agg # .cast → animated GIF
              termshot # Static terminal screenshots (PNG)
              svg-term # .cast → animated SVG

              # Development
              act # GitHub Actions local runner
              nix-diff

              # Misc
              lbzip2
              poppler
              resvg
            ] ++ lib.optionals pkgs.stdenv.isLinux [
              inotify-tools
              # Linux-only (no aarch64-darwin support): speedtest is
              # meta.platforms=linux; stress-ng and ueberzugpp are likewise
              # linux-only (kernel stressors / X11-wayland image preview).
              # Gated here so the home-cli tier evaluates on Darwin (Plan 001 T5).
              speedtest
              stress-ng
              ueberzugpp
            ];
            description = "CLI packages to install";
          };

          # Additional CLI packages
          additionalCliPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Additional CLI packages";
          };
        };

        config = lib.mkMerge [
          # Core CLI configuration
          {
            # CLI packages
            home.packages = cfg.cliPackages ++ cfg.additionalCliPackages;

            # Shell aliases for bash and zsh
            programs.bash.shellAliases = cfg.shellAliases;
            programs.zsh.shellAliases = cfg.shellAliases;

            # GNU Parallel with citation notice silenced
            programs.parallel = {
              enable = true;
              will-cite = true;
            };
          }

          # Git configuration
          (lib.mkIf cfg.enableGit {
            programs.git.enable = true;
          })

          # Tmux configuration
          (lib.mkIf cfg.enableTmux {
            programs.tmux.enable = true;
          })

          # Yazi TUI file manager
          (lib.mkIf cfg.enableYazi {
            programs.yazi = {
              enable = true;
              enableZshIntegration = true;
            };
          })
        ];
      };
  };
}
