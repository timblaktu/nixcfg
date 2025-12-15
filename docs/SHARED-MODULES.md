# Shared NixOS and Home Manager Modules

This repository exports reusable NixOS and Home Manager modules for sharing with colleagues and the community.

## Available Modules

### NixOS Modules (System-Level)

#### `nixosModules.wsl-base`
Common WSL system configuration for NixOS-WSL hosts.

**Platform Requirements**: NixOS-WSL distribution ONLY
- Requires full NixOS-WSL distribution installed
- Cannot be used on vanilla Ubuntu/Debian/Alpine WSL

**Provides**:
- System-level WSL integration (wsl.conf, systemd services)
- User and group management
- SSH daemon configuration with WSL-specific settings
- SOPS-nix secrets management integration
- USB/IP support for hardware passthrough

**Usage Example**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, nixos-wsl, nixcfg, ... }: {
    nixosConfigurations.my-wsl-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nixcfg.nixosModules.wsl-base
        {
          # Override defaults as needed
          wslCommon = {
            hostname = "my-wsl-host";
            defaultUser = "myuser";
            sshPort = 2222;
          };
        }
      ];
    };
  };
}
```

**Default Configuration**:
```nix
{
  base = {
    userName = "tim";  # Override this!
    userGroups = [ "wheel" "dialout" ];
    enableClaudeCodeEnterprise = false;
    nixMaxJobs = 8;
    nixCores = 0;
    enableBinaryCache = true;
    sshPasswordAuth = true;
    requireWheelPassword = false;
    additionalShellAliases = {
      esp32c5 = "esp-idf-shell";
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
    };
  };

  wsl = {
    enable = true;
    interop.register = true;
    usbip.enable = true;
    usbip.autoAttach = [ "3-1" "3-2" ];
  };

  sopsNix = {
    enable = true;
    hostKeyPath = "/etc/sops/age.key";
  };

  system.stateVersion = "24.11";
}
```

All settings use `lib.mkDefault`, so you can override them in your host configuration.

---

#### `nixosModules.ssh-keys`
Centralized SSH authorized keys registry.

**Provides**: Attribute set of SSH public keys for user access

**Usage Example**:
```nix
let
  sshKeys = inputs.nixcfg.nixosModules.ssh-keys;
in
{
  users.users.myuser = {
    openssh.authorizedKeys.keys = [
      sshKeys.timblaktu  # Add specific keys
    ];
  };
}
```

**Available Keys**:
```nix
{
  timblaktu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP58REN5jOx+Lxs6slx2aepF/fuO+0eSbBXrUhijhVZu timblaktu@gmail.com";
}
```

---

### Home Manager Modules (User-Level)

#### `homeManagerModules.wsl-home-base`
Common home-manager configuration for WSL environments.

**Platform Requirements**: ANY WSL distribution + Nix + home-manager ✅
- Works on NixOS-WSL, Ubuntu, Debian, Alpine, or any WSL distro
- Only requires Nix package manager and home-manager installed
- Does NOT require NixOS system

**Provides**:
- User-level WSL tweaks (shell wrappers, environment variables)
- Windows Terminal settings management
- WSL utilities (wslu)
- Home Manager `targets.wsl` configuration

**Usage Example (Vanilla Ubuntu WSL)**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."myuser@ubuntu-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      modules = [
        nixcfg.homeManagerModules.wsl-home-base  # Works on vanilla WSL!
        {
          homeBase = {
            username = "myuser";
            homeDirectory = "/home/myuser";
          };
        }
      ];
    };
  };
}
```

**Usage Example (NixOS-WSL)**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."myuser@nixos-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        nixcfg.homeManagerModules.wsl-home-base
        {
          homeBase = {
            username = "myuser";
            homeDirectory = "/home/myuser";
          };
        }
      ];
    };
  };
}
```

**Default Configuration**:
```nix
{
  homeBase = {
    enableDevelopment = true;
    enableEspIdf = true;
    enableOneDriveUtils = true;
    enableShellUtils = true;
    enableTerminal = true;

    environmentVariables = {
      WSL_DISTRO = "nixos";  # Override this!
      EDITOR = "nvim";
    };

    shellAliases = {
      explorer = "explorer.exe .";
      code = "code.exe";
      code-insiders = "code-insiders.exe";
      esp32c5 = "esp-idf-shell";
    };
  };

  home.packages = [ pkgs.wslu ];

  targets.wsl = {
    enable = true;
    windowsTools = {
      enablePowerShell = true;
      enableCmd = false;
      enableWslPath = true;
      wslPathPath = "/bin/wslpath";
    };
  };
}
```

All settings use `lib.mkDefault`, so you can override them.

---

## Platform Compatibility Matrix

| Module | NixOS-WSL | Ubuntu WSL | Debian WSL | Alpine WSL |
|--------|-----------|------------|------------|------------|
| `nixosModules.wsl-base` | ✅ | ❌ | ❌ | ❌ |
| `nixosModules.ssh-keys` | ✅ | ❌ | ❌ | ❌ |
| `homeManagerModules.wsl-home-base` | ✅ | ✅ | ✅ | ✅ |

**Key Insight**: Home Manager modules work on ANY WSL distro, but NixOS modules require NixOS-WSL.

---

## Package Duplication: wslu

The `wslu` package appears in BOTH `wsl-base` and `wsl-home-base` intentionally:
- **System level** (NixOS module): Provides system-wide access on NixOS-WSL
- **User level** (Home Manager module): Ensures availability on ANY WSL distro

This duplication is harmless on NixOS-WSL (Nix deduplicates automatically) and essential for portability to vanilla WSL distributions.

---

## Getting Started

### For NixOS-WSL Users

You can use both the NixOS system module and Home Manager module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    home-manager.url = "github:nix-community/home-manager";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, nixos-wsl, home-manager, nixcfg, ... }: {
    # System configuration
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-wsl.nixosModules.default
        nixcfg.nixosModules.wsl-base  # System-level WSL config
        {
          wslCommon.hostname = "my-host";
        }
      ];
    };

    # User configuration
    homeConfigurations."me@my-host" = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixcfg.homeManagerModules.wsl-home-base  # User-level WSL config
        {
          homeBase = {
            username = "me";
            homeDirectory = "/home/me";
          };
        }
      ];
    };
  };
}
```

### For Vanilla WSL Users (Ubuntu, Debian, etc.)

You can ONLY use the Home Manager module (system module requires NixOS):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nixcfg.url = "github:timblaktu/nixcfg";
  };

  outputs = { nixpkgs, home-manager, nixcfg, ... }: {
    homeConfigurations."me@ubuntu-wsl" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        nixcfg.homeManagerModules.wsl-home-base  # Works on vanilla WSL!
        {
          homeBase = {
            username = "me";
            homeDirectory = "/home/me";
          };
        }
      ];
    };
  };
}
```

---

## Customization Guide

### Overriding Defaults

All module options use `lib.mkDefault`, allowing easy overrides:

```nix
{
  imports = [ nixcfg.homeManagerModules.wsl-home-base ];

  # Override any default
  homeBase = {
    enableEspIdf = false;  # Disable ESP-IDF if not needed
    environmentVariables.EDITOR = "vim";  # Change editor
    shellAliases.explorer = "xdg-open";  # Custom alias
  };

  # Add your own packages
  home.packages = with pkgs; [
    ripgrep
    fd
  ];
}
```

### Extending Modules

You can layer additional modules on top:

```nix
{
  imports = [
    nixcfg.homeManagerModules.wsl-home-base
    ./my-custom-wsl-tweaks.nix
  ];

  # Your customizations here
}
```

---

## Contributing

Found a bug or want to add features? Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure `nix flake check` passes
5. Submit a pull request

---

## Support

- **Repository**: https://github.com/timblaktu/nixcfg
- **Issues**: https://github.com/timblaktu/nixcfg/issues
- **Documentation**: This file and `docs/CONSOLIDATION-PLAN.md`

---

## License

See repository LICENSE file.

---

**Last Updated**: 2025-12-13
**Module Version**: Phase 2 - Flake exports added
