# modules/flake-parts/nixos-configurations.nix
# Simplified NixOS system configurations - all config in hosts/*/default.nix
{ inputs, self, withSystem, ... }: {
  flake = {
    nixosConfigurations = {
      # mbp: Dendritic pattern - module defined in modules/hosts/mbp [N]/
      mbp = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.mbp
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );

      # potato: Dendritic pattern - module defined in modules/hosts/potato [N]/
      potato = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.potato
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );

      # pa161878-nixos: Dendritic pattern - module defined in modules/hosts/pa161878-nixos/
      pa161878-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.pa161878-nixos
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "pa161878-nixos";
          };
        }
      );

      # thinky-nixos: Dendritic pattern - module defined in modules/hosts/thinky-nixos/
      thinky-nixos = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.thinky-nixos
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
            wslHostname = "thinky-nixos";
          };
        }
      );

      # nixos-wsl-minimal: Dendritic pattern - module defined in modules/hosts/nixos-wsl-minimal [N]/
      nixos-wsl-minimal = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Keep allowUnfree = false for distribution
            self.modules.nixos.nixos-wsl-minimal
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nixos-wsl-dev-team: Dev team distribution image
      # module defined in modules/hosts/nixos-wsl-dev-team [N]/
      nixos-wsl-dev-team = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # allowUnfree set by wsl-dev-team module (true)
            self.modules.nixos.nixos-wsl-dev-team
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nixos-dev-team: Pure NixOS dev team image (no WSL)
      # module defined in modules/hosts/nixos-dev-team [N]/
      nixos-dev-team = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.nixos-dev-team
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nixos-dev-team-ec2: EC2 AMI for dev team (x86_64)
      # module defined in modules/hosts/nixos-dev-team-ec2 [N]/
      nixos-dev-team-ec2 = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.nixos-dev-team-ec2
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nixos-dev-team-graviton: EC2 AMI for dev team (aarch64 Graviton)
      # module defined in modules/hosts/nixos-dev-team-graviton [N]/
      nixos-dev-team-graviton = withSystem "aarch64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.nixos-dev-team-graviton
          ];
          specialArgs = {
            inherit inputs;
          };
        }
      );

      # nuc-apt-repo: Dendritic pattern - module defined in modules/hosts/nuc-apt-repo [N]/
      nuc-apt-repo = withSystem "x86_64-linux" ({ pkgs, ... }:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            self.modules.nixos.nuc-apt-repo
          ];
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          };
        }
      );

    };
  };
}
