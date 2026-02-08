# modules/flake-parts/lib.nix
# Helper functions for creating configurations from flake.modules.*
#
# These functions provide a standardized way to create NixOS, Darwin, and
# Home Manager configurations from the dendritic flake.modules.* namespace.
#
# Simple usage (no extra options):
#   flake.nixosConfigurations = inputs.self.lib.mkNixos "x86_64-linux" "thinky-nixos";
#   flake.homeConfigurations = inputs.self.lib.mkHomeManager "x86_64-linux" "tim@thinky-nixos";
#
# Advanced usage (with extra options):
#   flake.nixosConfigurations = inputs.self.lib.mkNixosWithArgs "x86_64-linux" "thinky-nixos" {
#     extraModules = [ ./hardware-quirks.nix ];
#     extraSpecialArgs = { wslHostname = "thinky-nixos"; };
#   };
#
# Each helper:
# - Looks up the module from config.flake.modules.{nixos,darwin,homeManager}.<name>
# - Applies common defaults (nixpkgs config, specialArgs)
# - Returns an attrset suitable for merging into flake.*Configurations
{ lib, config, inputs, withSystem, ... }:
let
  # === Utilities (migrated from flake-modules/systems.nix) ===

  # Helper to get nixpkgs for a specific system with our overlays
  nixpkgsFor = system: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (import ../../overlays { inherit inputs; })
    ];
  };

  # Helper to extract hostname from configuration name pattern "user@hostname"
  extractHostname = configName:
    builtins.elemAt (lib.splitString "@" configName) 1;

  # === Configuration Builders ===

  # Internal implementation with all options
  mkNixosImpl = system: name: { extraModules ? [ ]
                              , extraSpecialArgs ? { }
                              ,
                              }: {
    ${name} = withSystem system ({ pkgs, ... }:
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          config.flake.modules.nixos.${name}
        ] ++ extraModules;
        specialArgs = {
          inherit inputs;
          inherit (inputs) nixpkgs-stable;
        } // extraSpecialArgs;
      }
    );
  };

  mkDarwinImpl = system: name: { extraModules ? [ ]
                               , extraSpecialArgs ? { }
                               ,
                               }: {
    ${name} = withSystem system ({ pkgs, ... }:
      inputs.darwin.lib.darwinSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          config.flake.modules.darwin.${name}
          inputs.sops-nix.darwinModules.sops
        ] ++ extraModules;
        specialArgs = {
          inherit inputs;
          inherit (inputs) nixpkgs-stable;
        } // extraSpecialArgs;
      }
    );
  };

  mkHomeManagerImpl = system: name: { extraModules ? [ ]
                                    , extraSpecialArgs ? { }
                                    , useWslVariant ? false
                                    ,
                                    }:
    let
      hmInput = if useWslVariant then inputs.home-manager-wsl else inputs.home-manager;
    in
    {
      ${name} = withSystem system ({ pkgs, ... }:
        hmInput.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            config.flake.modules.homeManager.${name}
          ] ++ extraModules;
          extraSpecialArgs = {
            inherit inputs;
            inherit (inputs) nixpkgs-stable;
          } // extraSpecialArgs;
        }
      );
    };
in
{
  flake.lib = {
    # === Utilities ===

    # Helper to get nixpkgs for a specific system with our overlays
    inherit nixpkgsFor;

    # Helper to extract hostname from configuration name pattern "user@hostname"
    inherit extractHostname;

    # === Configuration Builders ===

    # mkNixos: Create a NixOS configuration from flake.modules.nixos.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.nixos.<name>
    #
    # Returns: { <name> = <nixosConfiguration>; }
    mkNixos = system: name: mkNixosImpl system name { };

    # mkNixosWithArgs: Create a NixOS configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.nixos.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #   }
    #
    # Returns: { <name> = <nixosConfiguration>; }
    mkNixosWithArgs = mkNixosImpl;

    # mkDarwin: Create a Darwin configuration from flake.modules.darwin.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "aarch64-darwin", "x86_64-darwin")
    #   name: Configuration name matching flake.modules.darwin.<name>
    #
    # Returns: { <name> = <darwinConfiguration>; }
    mkDarwin = system: name: mkDarwinImpl system name { };

    # mkDarwinWithArgs: Create a Darwin configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "aarch64-darwin", "x86_64-darwin")
    #   name: Configuration name matching flake.modules.darwin.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #   }
    #
    # Returns: { <name> = <darwinConfiguration>; }
    mkDarwinWithArgs = mkDarwinImpl;

    # mkHomeManager: Create a Home Manager configuration from flake.modules.homeManager.<name>
    # Simple 2-argument form uses defaults for all options.
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.homeManager.<name> (typically "user@host")
    #
    # Returns: { <name> = <homeManagerConfiguration>; }
    mkHomeManager = system: name: mkHomeManagerImpl system name { };

    # mkHomeManagerWithArgs: Create a Home Manager configuration with extra options
    #
    # Arguments:
    #   system: Architecture (e.g., "x86_64-linux", "aarch64-linux")
    #   name: Configuration name matching flake.modules.homeManager.<name>
    #   args: {
    #     extraModules?: List of additional modules to include
    #     extraSpecialArgs?: Additional specialArgs to pass to modules
    #     useWslVariant?: Use home-manager-wsl input (for WSL-specific features like windows-terminal)
    #   }
    #
    # Returns: { <name> = <homeManagerConfiguration>; }
    mkHomeManagerWithArgs = mkHomeManagerImpl;

    # === Claude Code Configuration Presets ===
    #
    # Reusable configuration blocks for claude-code. Hosts use these with
    # attribute merging (//) to compose their config while staying DRY.
    #
    # Usage in host:
    #   programs.claude-code = inputs.self.lib.claudeCode.baseConfig // {
    #     accounts = inputs.self.lib.claudeCode.personalAccounts;
    #   };
    #
    # For work machines:
    #   accounts = inputs.self.lib.claudeCode.personalAccounts
    #           // inputs.self.lib.claudeCode.workAccount;

    claudeCode = {
      # Base config (enable, defaults, common settings)
      baseConfig = {
        enable = true;
        defaultModel = "opus";
        defaultAccount = "max";
        taskAutomation.enable = true;
        skills.enable = true;
      };

      # Personal accounts (max + pro) - used on all personal machines
      personalAccounts = {
        max = {
          enable = true;
          displayName = "Claude Max Account";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
        pro = {
          enable = true;
          displayName = "Claude Pro Account";
          model = "sonnet";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
          };
        };
      };

      # Work account (Code-Companion proxy) - only for work machines with VPN access
      workAccount = {
        work = {
          enable = true;
          displayName = "Work Code-Companion";
          model = "sonnet";
          api = {
            baseUrl = "https://codecompanionv2.d-dp.nextcloud.aero";
            authMethod = "bearer";
            disableApiKey = true;
            modelMappings = {
              haiku = "devstral";
              sonnet = "qwen-a3b";
              opus = "claude-sonnet-4-5-20250929";
            };
          };
          secrets.bearerToken.bitwarden = {
            item = "PAC Code Companion v2";
            field = "API Key";
          };
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
            ANTHROPIC_DEFAULT_HAIKU_MODEL = "devstral";
            ANTHROPIC_DEFAULT_SONNET_MODEL = "qwen-a3b";
            ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-sonnet-4-5-20250929";
          };
        };
      };

      # Default statusline config
      defaultStatusline = {
        enable = true;
        style = "powerline";
        enableAllStyles = true;
        testMode = true;
      };

      # Default MCP servers
      defaultMcpServers = {
        context7.enable = true;
        sequentialThinking.enable = true;
        nixos.enable = true;
      };

      # Default sub-agents
      defaultSubAgents = {
        pdf-indexer = {
          description = "Extract TOC, metadata, and key content from PDF documents. Uses pdftotext via Bash to bypass Read tool token limits. Handles PDFs of any size.";
          tools = [ "Bash" "Glob" ];
          capabilities = [
            "Extract metadata (title, pages, size) using pdfinfo"
            "Extract text content using pdftotext with page range control"
            "Size-based routing: full extraction for small PDFs, TOC-only for large"
            "Structured markdown output with page references"
          ];
          instructions = ''
            ## Why This Agent Exists

            The Read tool has a 25,000 token limit for PDFs, which fails on documents > ~30 pages.
            This agent uses `pdftotext` via Bash to extract text content, bypassing that limitation.

            ## Required Tools

            Use `poppler-utils` via nix-shell:

            ```bash
            nix-shell -p poppler-utils --run 'pdfinfo "file.pdf"'
            nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 10 "file.pdf" -'
            ```

            ## Size-Based Extraction Strategy

            **Small PDFs (≤50 pages):** Extract all pages
            ```bash
            nix-shell -p poppler-utils --run 'pdftotext "PATH" -' 2>/dev/null | head -500
            ```

            **Medium PDFs (51-200 pages):** Extract first 15 pages (usually contains TOC)
            ```bash
            nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 15 "PATH" -' 2>/dev/null
            ```

            **Large PDFs (>200 pages):** Extract first 20 pages only
            ```bash
            nix-shell -p poppler-utils --run 'pdftotext -f 1 -l 20 "PATH" -' 2>/dev/null
            ```

            ## Output Format

            Return structured markdown with:
            - Document title and revision
            - Page count and file size
            - Table of contents with page numbers
            - Document type classification

            ## Handling Multiple PDFs

            Use `fd` to list PDFs first:
            ```bash
            fd -t f -e pdf -e PDF . "DIRECTORY_PATH"
            ```
            Then process each individually.
          '';
          examples = [
            "Index this PDF: /path/to/document.pdf"
            "Index all PDFs in /path/to/docs/ and return a markdown table"
            "Extract the TOC from /path/to/large-manual.pdf"
          ];
        };
      };
    };
  };
}
