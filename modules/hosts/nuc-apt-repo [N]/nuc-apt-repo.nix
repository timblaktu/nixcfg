# modules/hosts/nuc-apt-repo [N]/nuc-apt-repo.nix
# Dendritic host composition for nuc-apt-repo (bare metal NixOS)
#
# Always-on Intel NUC hosting the local Debian apt repository (aptly) and
# upstream Debian proxy (apt-cacher-ng). Caddy provides HTTPS for aptly
# and plain HTTP for ISAR builds.
#
# Features:
# - Aptly Debian repository with GPG signing (generateKey mode)
# - apt-cacher-ng upstream Debian proxy
# - Caddy reverse proxy (HTTPS + plain HTTP)
# - ZFS-backed /nix (disko, single-disk layout)
# - Full dev-team CLI stack (system-cli)
# - Home Manager dev-team user environment
#
# Deployment:
#   nixos-anywhere --flake ~/src/nixcfg#nuc-apt-repo root@<ip>
#   sudo nixos-rebuild switch --flake ~/src/nixcfg#nuc-apt-repo
{ config, lib, inputs, ... }:
let
  inherit (config.meta) username;
  homeDirectory = "/home/${username}";
in
{
  # === NixOS System Module ===
  flake.modules.nixos.nuc-apt-repo = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      ./_hardware-config.nix
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.self.modules.nixos.system-cli
      inputs.self.modules.nixos.aptly-repo
      inputs.self.modules.nixos.apt-cacher-ng
    ];

    config = {
      # System default layer configuration (required by system types)
      systemDefault.userName = username;

      networking.hostName = "nuc-apt-repo";

      # Networking: single NIC, DHCP
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = true;
      };
      systemd.network = {
        enable = true;
        networks."10-mgmt" = {
          matchConfig.Name = "enp2s0";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
          };
          dhcpV4Config.RouteMetric = 100;
        };
      };

      # Aptly: primary service role
      services.aptly-repo = {
        enable = true;
        signing = {
          enable = true;
          gpgProvider = "internal";
          generateKey = true;
        };
        repos = {
          converix-local = {
            distribution = "main";
            component = "main";
            comment = "n3x custom packages";
          };
        };
      };

      # Apt proxy for the network
      services.apt-cacher-ng = {
        enable = true;
        openFirewall = true;
      };

      # Caddy: HTTPS for aptly + plain HTTP for ISAR builds
      services.caddy = {
        enable = true;
        virtualHosts."apt.nuc-apt-repo.n3x.internal" = {
          extraConfig = ''
            tls internal

            handle /api/* {
              reverse_proxy http://127.0.0.1:8080
            }

            handle {
              root * /var/lib/aptly/public
              file_server browse
            }

            header Cache-Control "public, max-age=300"
          '';
        };
        virtualHosts.":8088" = {
          extraConfig = ''
            handle /api/* {
              reverse_proxy http://127.0.0.1:8080
            }

            handle {
              root * /var/lib/aptly/public
              file_server browse
            }

            header Cache-Control "public, max-age=300"
          '';
        };
      };
      networking.firewall.allowedTCPPorts = [ 443 8088 ];

      networking.extraHosts = ''
        127.0.0.1 nuc-apt-repo apt.nuc-apt-repo.n3x.internal
      '';

      # SSH access
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };

      users.users.root = {
        hashedPassword = "$6$2bKnbzySlia6rSF2$lyEdR80tJwOnZdj3nEFWcEYkLB6RYyr6ABkxwL3Zno0QyHoEwU6wiy.y6DYTZRvf3BwqRFj77Edc/5QC7Hrmy.";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGhp78KALWz16/B12OrBmCjEmb1QDIWpiuKfEkFqNKI4 tim@nixos"
        ];
      };

      # ZFS maintenance
      services.zfs.autoScrub.enable = true;
      services.zfs.trim.enable = true;

      # Admin packages (on top of what system-cli provides)
      environment.systemPackages = with pkgs; [ aptly iotop ethtool ];

      system.stateVersion = "25.11";
    };
  };

  # === Home Manager Module ===
  # Cherry-picks from home-enterprise + home-dev-team, excluding WSL-specific
  # modules (wsl-home, terminal, windows-terminal, onedrive) that require
  # targets.wsl option only available under home-manager-wsl.
  flake.modules.homeManager."${username}@nuc-apt-repo" = { config, lib, pkgs, ... }: {
    imports = [
      # Base HM layer
      inputs.self.modules.homeManager.home-default
      # Core CLI tools
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.tmux
      inputs.self.modules.homeManager.neovim
      # Utilities
      inputs.self.modules.homeManager.shell-utils
      inputs.self.modules.homeManager.system-tools
      inputs.self.modules.homeManager.yazi
      inputs.self.modules.homeManager.files
      inputs.self.modules.homeManager.git-auth-helpers
      # AI development tools
      inputs.self.modules.homeManager.claude-code
      inputs.self.modules.homeManager.opencode
      # Authentication
      inputs.self.modules.homeManager.gitlab-auth
      # Containers
      inputs.self.modules.homeManager.podman
      # Development toolchain
      inputs.self.modules.homeManager.development-tools
      # Cloud tools
      inputs.self.modules.homeManager.awscli
      inputs.self.modules.homeManager.jfrog-cli
    ];

    # Required by system types
    homeMinimal = {
      inherit username homeDirectory;
    };
  };
}
