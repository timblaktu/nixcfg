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
  };

  outputs = inputs @ { self, nixpkgs, nixpkgs-stable, home-manager, darwin, nixos-wsl, sops-nix, flake-utils, nvf, ... }:
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
      
      # Standalone home-manager configurations (for non-NixOS systems)
      homeConfigurations = {
        # For MacBook Pro (based on existing config)
        "tim@mbp" = mkHomeConfig {
          system = "x86_64-linux";
          username = "tim";
          homeConfig = {
            username = "tim";
            homeDirectory = "/home/tim";
          };
        };
        
        # Ubuntu WSL configuration
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
      };
      
      # Development shells and packages
      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system}; in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nix
              git
              nixpkgs-fmt
              nil # Nix language server
              sops # For secrets
            ];
          };
        }
      );
    };
}
