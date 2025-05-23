{
  description = "Unified Nix configuration for all systems";

  inputs = {
    # Package sources
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Additional modules for different platforms
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Secret management
    sops-nix.url = "github:Mic92/sops-nix";

    # Additional utilities
    flake-utils.url = "github:numtide/flake-utils";

    # Neovim configuration framework from nixconf
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # ESP32-C5 development tools - specify branch in the URL
    nixpkgs-esp-dev = {
      url = "github:timblaktu/nixpkgs-esp-dev/c5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, nixpkgs-stable, home-manager, darwin, nixos-wsl, sops-nix, flake-utils, nvf, nixpkgs-esp-dev, ... }:
    let
      # System types to support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      
      # Helper function to generate an attrset for each supported system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      # Nixpkgs instantiation with overlays for each system
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (import ./overlays)
          # Additional overlays
        ];
      });
      
      # Helper function to create NixOS configurations with parameterized base module
      mkNixosSystem = { 
        system ? "x86_64-linux", 
        hostname,
        extraModules ? [],
        isWSL ? false,
        sshPort ? 22,
        # Base module parameters
        baseConfig ? {},
        homeConfig ? {},
      }: 
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            # Global config for nixpkgs
            { nixpkgs.config.allowUnfree = true; }
            
            # Host-specific configuration
            ./hosts/${hostname}
            
            # Base module
            ./modules/base.nix
            
            # Apply base module configuration
            { base = baseConfig; }
            
            # Configure SSH port explicitly
            {
                services.openssh = {
                    enable = true;
                    ports = [ sshPort ];
                };
            }            
            
            # Home-manager module
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.tim = { 
                imports = [
                  ./home/modules/base.nix
                  ./profiles/development.nix
                ];
                # Pass configuration to homeBase
                homeBase = homeConfig;
              };
              home-manager.extraSpecialArgs = { 
                inherit inputs;
                inherit (inputs) nixpkgs-stable;
              };
            }
            
            # Secrets management
            sops-nix.nixosModules.sops
          ] 
          # Add WSL module if required
          ++ (if isWSL then [ nixos-wsl.nixosModules.default ] else [])
          # Add host-specific extra modules
          ++ extraModules;
          
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        };
      
      # Helper function to create standalone home-manager configurations
      # (for non-NixOS systems with Nix installed)
      mkHomeConfig = { 
        system, 
        username ? "tim",
        extraModules ? [],
        # Home-manager base module parameters
        homeConfig ? {},
      }: 
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgsFor.${system};
          modules = [
            # Global config for nixpkgs
            { nixpkgs.config.allowUnfree = true; }
            
            # Apply the base module directly
            ./home/modules/base.nix
            ./profiles/development.nix
            {
              # Pass the main configuration
              homeBase = homeConfig;
            }
          ] ++ extraModules;
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        };
      
      # Helper function to create Darwin configurations
      mkDarwinSystem = { 
        system ? "x86_64-darwin", 
        hostname,
        extraModules ? [],
        # Home-manager base module parameters
        homeConfig ? {},
      }: 
        darwin.lib.darwinSystem {
          inherit system;
          modules = [
            # Global config for nixpkgs
            { nixpkgs.config.allowUnfree = true; }
            
            # Base configuration
            ./hosts/${hostname}
            
            # Home-manager module
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.tim = { 
                imports = [
                  ./home/modules/base.nix
                  ./profiles/wsl.nix
                ];
                # Pass configuration to homeBase
                homeBase = homeConfig;
              };
              home-manager.extraSpecialArgs = { 
                inherit inputs;
                inherit (inputs) nixpkgs-stable;
              };
            }
            
            # Secrets management
            sops-nix.darwinModules.sops
          ] 
          # Add host-specific extra modules
          ++ extraModules;
          
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        };
    in {
      # NixOS configurations
      nixosConfigurations = {
        # Your MacBook Pro
        mbp = mkNixosSystem {
          hostname = "mbp";
          system = "x86_64-linux";
          baseConfig = {
            # Override common defaults for MBP
            sshPasswordAuth = true;
            requireWheelPassword = false;
            userGroups = [ "wheel" "networkmanager" "audio" "video" ];
            additionalPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              kbd
              terminus_font
              powerline-fonts
            ];
            consolePackages = with nixpkgs.legacyPackages.x86_64-linux; [
              kbd
              terminus_font
              powerline-fonts
            ];
            # Additional shell aliases
            additionalShellAliases = {
              # MBP-specific aliases would go here
            };
          };
          homeConfig = {
            environmentVariables = {
              EDITOR = "nvim";
            };
          };
        };
        
        # ARM-based Libre Computer board
        potato = mkNixosSystem {
          hostname = "potato";
          system = "aarch64-linux";
          baseConfig = {
            # Potato-specific base params
            userGroups = [ "wheel" "networkmanager" "gpio" ];
          };
          homeConfig = {};
        };
        
        # WSL configuration
        thinky-nixos = mkNixosSystem {
          hostname = "thinky-nixos";
          system = "x86_64-linux";
          isWSL = true;
          sshPort = 2223;  # Must bind to unique port since sharing winHost with another WSL guest
                           # in this case, thinky-ubuntu happens to be using 2222
          baseConfig = {
            # WSL-specific configuration
            requireWheelPassword = false;
            userGroups = [ "wheel" ];
            additionalShellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
            };
            additionalPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              # wslu is already provided by the WSL profile
            ];
          };
          homeConfig = {
            environmentVariables = {
              EDITOR = "nvim";
              WSL_DISTRO = "nixos";
            };
          };
        };
        tblack-t14-nixos = mkNixosSystem {
          hostname = "tblack-t14-nixos";
          system = "x86_64-linux";
          isWSL = true;
          baseConfig = {
            # WSL-specific configuration
            requireWheelPassword = false;
            userGroups = [ "wheel" ];
            additionalShellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
            };
            additionalPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              # wslu is already provided by the WSL profile
            ];
          };
          homeConfig = {
            environmentVariables = {
              EDITOR = "nvim";
              WSL_DISTRO = "nixos";
            };
          };
        };
      };
      
      # macOS configurations (if any)
      darwinConfigurations = {
        # Example macOS configuration
        macbook-air = mkDarwinSystem {
          hostname = "macbook-air";
          system = "aarch64-darwin";
          homeConfig = {
            homeDirectory = "/Users/tim";
          };
        };
      };
      
      # Standalone home-manager configurations
      #
      # These configurations can be applied in two ways:
      #
      # 1. For NixOS systems:
      #    - Primary: These configurations are already integrated into NixOS through
      #      the home-manager.nixosModules.home-manager module in mkNixosSystem
      #    - Optional: Can be applied separately with:
      #      nix run home-manager -- switch --flake .#user@hostname
      #    - Benefit: Allows testing home-manager changes without rebuilding the system
      #
      # 2. For non-NixOS systems (Ubuntu, macOS):
      #    - Required: These are the only way to apply home-manager on non-NixOS systems
      #    - Applied with: nix run home-manager -- switch --flake .#user@hostname
      #    - Works on any system with Nix installed (Linux, macOS, WSL)
      #
      # Using standalone configurations for all hosts provides deployment flexibility 
      # and consistent user environments across different systems.
      #
      homeConfigurations = {
        "tim@mbp" = mkHomeConfig {
          system = "x86_64-linux";
          username = "tim";
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
          };
        };
        
        "tim@thinky-ubuntu" = mkHomeConfig {
          system = "x86_64-linux";
          username = "tim";
          extraModules = [
            ./hosts/thinky-ubuntu
            ./profiles/wsl.nix  # Include WSL-specific profile
            # ./home/modules/dotfiles  # Commented out: Include personal dotfiles
          ];
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
            additionalPackages = with nixpkgs.legacyPackages.x86_64-linux; [
              wslu
            ];
            environmentVariables = {
              WSL_DISTRO = "ubuntu";
              EDITOR = "nvim";
            };
            # WSL-specific shell aliases
            shellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
            };
            # Enable personal dotfiles - commented out to fix build error
            # customDotfiles.enable = true;
          };
        };
        
        "tim@thinky-nixos" = mkHomeConfig {
          system = "x86_64-linux";
          username = "tim";
          extraModules = [
            ./profiles/wsl.nix  # Include WSL-specific profile
          ];
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
            environmentVariables = {
              WSL_DISTRO = "nixos";
              EDITOR = "nvim";
            };
            # WSL-specific shell aliases
            shellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
            };
          };
        };
        
        "tim@tblack-t14-nixos" = mkHomeConfig {
          system = "x86_64-linux";
          username = "tim";
          extraModules = [
            ./profiles/wsl.nix  # Include WSL-specific profile
          ];
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
            environmentVariables = {
              WSL_DISTRO = "nixos";
              EDITOR = "nvim";
            };
            # WSL-specific shell aliases
            shellAliases = {
              explorer = "explorer.exe .";
              code = "code.exe";
              code-insiders = "code-insiders.exe";
              esp32c5 = "nix develop .#esp32c5";
            };
          };
        };
        
        "tim@potato" = mkHomeConfig {
          system = "aarch64-linux";
          username = "tim";
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
            environmentVariables = {
              EDITOR = "nvim";
            };
          };
        };
      };
      
      # Development shells and packages
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nix
              git
              nixpkgs-fmt
              nil # Nix language server
              sops # For secrets
            ];
          };
          
          # ESP32-C5 development shell from upstream nixpkgs-esp-dev, with mods/additions
          esp32c5 = nixpkgs-esp-dev.devShells.${system}.esp32c5-idf.overrideAttrs (oldAttrs: {
            buildInputs = (oldAttrs.buildInputs or []) ++ (with pkgs; [
              tio
            ]);
            
            shellHook = (oldAttrs.shellHook or "") + ''
              export SWT_COMMON_PATH=$HOME/src/dev_swt_common
              export SWT_RLTK_PATH=$HOME/src/dev_swt_rltk
              export SDK_RLTK_PATH=$HOME/src/dev_sdk_rltk
              export WISA_CONNECT_PATH=$HOME/src/wisa_server/wisa_server
              cd $SWT_RLKT_PATH
              
              echo "Trusting ESP-IDF directory in nix store to prevent dubious ownership errors.."
              git config --local --add safe.directory "$IDF_PATH" 2>/dev/null || true
              
              echo "WiSA ESP32-C5 development environment activated!"
            '';
          });
      });
  };
}
