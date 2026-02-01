# flake-modules/dev-shells.nix
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
          drawio-headless # For .drawio.svg rendering (unfree license)
        ];

        shellHook = ''
          echo "Nixcfg development environment"
          echo "Available commands:"
          echo "  nix build .#<package>     - Build a package"
          echo "  nix develop               - Enter development shell"
          echo "  nix flake check           - Check flake validity"
          echo "  nixos-rebuild switch --flake .#<hostname> - Apply NixOS config"
          echo "  home-manager switch --flake .#<user@hostname> - Apply home config"
          echo "  nix run .#drawio-render   - Re-render .drawio.svg files"
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
      drawio-render = {
        type = "app";
        program = toString (pkgs.writeShellScript "drawio-render" ''
          set -euo pipefail

          # Colors for output
          RED='\033[0;31m'
          GREEN='\033[0;32m'
          YELLOW='\033[0;33m'
          NC='\033[0m' # No Color

          usage() {
            echo "Usage: drawio-render [OPTIONS] [FILE...]"
            echo ""
            echo "Re-render .drawio.svg files from embedded mxGraphModel XML."
            echo ""
            echo "OPTIONS:"
            echo "  -a, --all      Find and render all .drawio.svg files recursively"
            echo "  -d, --dry-run  Show what would be rendered without executing"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  drawio-render docs/diagram.drawio.svg     # Render single file"
            echo "  drawio-render -a                          # Render all .drawio.svg files"
            echo "  drawio-render -d -a                       # Dry run for all files"
          }

          render_file() {
            local file="$1"
            local dry_run="''${2:-false}"

            if [[ ! -f "$file" ]]; then
              echo -e "''${RED}Error: File not found: $file''${NC}" >&2
              return 1
            fi

            if [[ ! "$file" =~ \.drawio\.svg$ ]]; then
              echo -e "''${YELLOW}Warning: Skipping non-.drawio.svg file: $file''${NC}" >&2
              return 0
            fi

            if [[ "$dry_run" == "true" ]]; then
              echo -e "''${YELLOW}[dry-run]''${NC} Would render: $file"
              return 0
            fi

            echo -n "Rendering: $file ... "

            # Export to temporary file, then move back
            # drawio -x exports based on embedded XML, regenerating SVG body
            local tmpfile
            tmpfile=$(mktemp --suffix=.svg)
            trap "rm -f $tmpfile" RETURN

            if ${pkgs.drawio-headless}/bin/drawio -x -f svg -o "$tmpfile" "$file" 2>/dev/null; then
              mv "$tmpfile" "$file"
              echo -e "''${GREEN}done''${NC}"
            else
              echo -e "''${RED}failed''${NC}"
              return 1
            fi
          }

          # Parse arguments
          ALL=false
          DRY_RUN=false
          FILES=()

          while [[ $# -gt 0 ]]; do
            case $1 in
              -a|--all)
                ALL=true
                shift
                ;;
              -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              -*)
                echo -e "''${RED}Unknown option: $1''${NC}" >&2
                usage
                exit 1
                ;;
              *)
                FILES+=("$1")
                shift
                ;;
            esac
          done

          # Validate arguments
          if [[ "$ALL" == "false" && ''${#FILES[@]} -eq 0 ]]; then
            echo -e "''${RED}Error: No files specified. Use -a for all files or specify files.''${NC}" >&2
            usage
            exit 1
          fi

          # Find all files if --all
          if [[ "$ALL" == "true" ]]; then
            while IFS= read -r -d "" file; do
              FILES+=("$file")
            done < <(${pkgs.fd}/bin/fd -e drawio.svg -0)
          fi

          # Render files
          success=0
          failed=0
          for file in "''${FILES[@]}"; do
            if render_file "$file" "$DRY_RUN"; then
              ((success++)) || true
            else
              ((failed++)) || true
            fi
          done

          # Summary
          if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "\n''${YELLOW}Dry run complete.''${NC} Would render $success file(s)."
          else
            echo -e "\nRendered: ''${GREEN}$success''${NC} file(s)"
            if [[ $failed -gt 0 ]]; then
              echo -e "Failed:   ''${RED}$failed''${NC} file(s)"
              exit 1
            fi
          fi
        '');
        meta = {
          description = "Re-render .drawio.svg files from embedded mxGraphModel XML";
          longDescription = ''
            Re-renders the visible SVG body of .drawio.svg files from the
            embedded mxGraphModel XML, which is the source of truth.

            Use this after editing .drawio.svg files directly (e.g., with Claude Code)
            to ensure the visible SVG matches the XML data.
          '';
          platforms = [ "x86_64-linux" ];
          category = "documentation";
        };
      };
    };
  };
}
