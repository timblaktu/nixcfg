# modules/flake-parts/dev-shells.nix
# Development shells and environments
{ inputs, ... }: {
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    devShells = {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nix
          git
          nixpkgs-fmt
          nil # Nix language server
          sops # For secrets
          inputs.drawio-svg-sync.packages.${system}.default # For .drawio.svg rendering
          self'.packages.dev-switch # Fast dev loop: switch with local --override-input
        ];

        # dev-switch usage is listed in the shellHook banner below.

        shellHook = ''
          echo "Nixcfg development environment"
          echo "Available commands:"
          echo "  nix build .#<package>     - Build a package"
          echo "  nix develop               - Enter development shell"
          echo "  nix flake check           - Check flake validity"
          echo "  nixos-rebuild switch --flake .#<hostname> - Apply NixOS config"
          echo "  home-manager switch --flake .#<user@hostname> - Apply home config"
          echo "  nix run .#drawio-svg-sync - Re-render .drawio.svg files"
          echo "  dev-switch -o nixcfg=~/src/nixcfg ~/src/nixcfg-work - Switch with local input override (fast dev loop)"
        '';
      };

      # ESP32-C5 development shell from upstream nixpkgs-esp-dev, with mods/additions
      # Temporarily disabled due to invalid derivation path
      # esp32c5 = let
      #   # Override the esp-idf package to use custom revision
      #   esp-idf-c5-custom = inputs.nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c5.override {
      #     rev = "d930a386dae";
      #     sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
      #   };
      # in pkgs.mkShell {
      #   name = "esp32c5-wireless-development";
      #
      #   buildInputs = [
      #     esp-idf-c5-custom
      #     pkgs.tio
      #   ];
      #
      #   shellHook = ''
      #     echo "Forcing ESP-IDF to use its own Python environment.."
      #     export PATH="$IDF_PYTHON_ENV_PATH/bin:$PATH"
      #     echo "Exporting required environment variables.."
      #     export PROJECT_COMMON_PATH=$HOME/src/project_common
      #     export PROJECT_RLTK_PATH=$HOME/src/project_rltk
      #     export SDK_RLTK_PATH=$HOME/src/sdk_rltk
      #     export WIRELESS_SERVER_PATH=$HOME/src/wireless_server
      #     echo "Sourcing export.sh in \$IDF_PATH.."
      #     # source $IDF_PATH/export.sh
      #     echo "Wireless ESP32-C5 development environment activated!"
      #     cd $SWT_RLTK_PATH
      #   '';
      # };
    };

    # Convenient shell aliases for development
    apps = {
      # Quick development commands
      check = {
        type = "app";
        program = toString (pkgs.writeShellScript "check" ''
          echo "🔍 Running flake checks..."
          nix flake check
        '');
        meta = {
          description = "Validate flake configuration and run all checks";
          longDescription = ''
            Runs 'nix flake check' to validate the entire flake configuration,
            including derivations, NixOS configurations, and custom checks.
          '';
          platforms = [ "x86_64-linux" ];
          category = "development";
        };
      };

      update = {
        type = "app";
        program = toString (pkgs.writeShellScript "update" ''
          echo "Updating flake inputs..."
          nix flake update
        '');
        meta = {
          description = "Update all flake inputs to their latest versions";
          longDescription = ''
            Updates the flake.lock file by fetching the latest versions of all
            declared inputs, equivalent to running 'nix flake update'.
          '';
          platforms = [ "x86_64-linux" ];
          category = "development";
        };
      };

      # Draw.io SVG rendering - re-renders SVG body from embedded mxGraphModel XML
      # Using external flake: github:timblaktu/drawio-svg-sync
      drawio-svg-sync = inputs.drawio-svg-sync.apps.${system}.default // {
        meta = (inputs.drawio-svg-sync.apps.${system}.default.meta or { }) // {
          description = "Re-render .drawio.svg files from embedded mxGraphModel XML";
        };
      };

      # Fast dev loop: switch a downstream flake config with local --override-input
      # checkouts, so upstream module changes apply without commit/push/relock.
      dev-switch = {
        type = "app";
        program = pkgs.lib.getExe self'.packages.dev-switch;
        meta = {
          description = "Activate a flake config with local --override-input checkouts (fast dev loop)";
          longDescription = ''
            Runs home-manager / nixos-rebuild / darwin-rebuild switch against a
            downstream flake while overriding one or more inputs with local checkouts.
            Generic over input name, local path, activation front-end and target.
            Example: nix run '.#dev-switch' -- -o nixcfg=~/src/nixcfg ~/src/nixcfg-work
          '';
          category = "development";
        };
      };
    };
  };
}
