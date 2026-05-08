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

    # === OpenCode Configuration Presets ===
    #
    # Reusable configuration blocks for opencode. Hosts use these with
    # attribute merging (//) to compose their config while staying DRY.
    #
    # Usage in host:
    #   programs.opencode = inputs.self.lib.openCode.baseConfig // {
    #     accounts = inputs.self.lib.openCode.personalAccounts;
    #   };
    #
    # For work machines:
    #   accounts = inputs.self.lib.openCode.personalAccounts
    #           // inputs.self.lib.openCode.workAccount;

    openCode = {
      # Base config (enable, defaults, common settings)
      # NOTE: defaultAccount intentionally omitted — each deployment layer sets its own.
      # Dev-team sets "work", personal hosts override to "max".
      baseConfig = {
        enable = true;
        defaultModel = "anthropic/claude-sonnet-4-5";
        # Provider configuration - API key via environment variable
        provider = {
          anthropic = {
            options = {
              apiKey = "{env:ANTHROPIC_API_KEY}";
            };
          };
        };
        # OpenCode permission keys are lowercase tool names.
        # Valid: read, edit, glob, grep, list, bash, task, skill, lsp,
        #        todowrite, question, webfetch, websearch, codesearch,
        #        external_directory, doom_loop
        # Note: "edit" covers write+edit+apply_patch+multiedit operations.
        # Object syntax enables pattern-based rules (last match wins).
        #
        # Parity with Claude Code permissions:
        #   CC allows: Bash, Read, Write, Edit, WebFetch + MCP servers
        #   CC denies: Search, Find, Bash(rm -rf /*)
        #   OC equivalents: glob=Glob, grep=Grep, edit=Write+Edit, bash=Bash
        permissions = {
          bash = {
            "*" = "allow";
            "rm -rf /*" = "deny";
          };
          read = "allow";
          edit = "allow";
          glob = "allow";
          grep = "allow";
          list = "allow";
          task = "allow";
          skill = "allow";
          lsp = "allow";
          webfetch = "allow";
          websearch = "allow";
          codesearch = "allow";
          todowrite = "allow";
          question = "allow";
          external_directory = "allow";
          "mcp__context7" = "allow";
          "mcp__mcp-nixos" = "allow";
          "mcp__sequential-thinking" = "allow";
        };
      };

      # Personal accounts (max + pro) - used on all personal machines
      personalAccounts = {
        max = {
          enable = true;
          displayName = "OpenCode Max Account";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
          };
        };
        pro = {
          enable = true;
          displayName = "OpenCode Pro Account";
          model = "anthropic/claude-sonnet-4-5";
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
          };
        };
      };

      # Work account template - structural preset for enterprise AI proxy access.
      # Deployment-specific values (bitwarden items, model names) are set in the
      # team or host layer that consumes this preset.
      workAccount = {
        work = {
          enable = true;
          displayName = "OpenCode Work";
          provider = "custom";
          # model: set by team/host layer (e.g., "bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0")
          secrets.envTokens = {
            BEDROCK_API_TOKEN = {
              # bitwarden: set by team/host layer
            };
            AI_PROXY_API_KEY = {
              # bitwarden: set by team/host layer
            };
          };
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
          };
        };
      };

      # Work provider templates - structural presets for enterprise AI proxy providers.
      # baseURL and model lists are deployment-specific; set by team/host layer.
      workProvider = {
        bedrock = {
          npm = "@ai-sdk/openai-compatible";
          name = "Bedrock";
          options = {
            # baseURL: set by team/host layer
            apiKey = "{env:BEDROCK_API_TOKEN}";
          };
          # models: set by team/host layer
        };
        ai-proxy = {
          npm = "@ai-sdk/openai-compatible";
          name = "AI Proxy";
          options = {
            # baseURL: set by team/host layer
            apiKey = "{env:AI_PROXY_API_KEY}";
          };
          # models: set by team/host layer
        };
      };

      # Default MCP servers (same as claude-code)
      defaultMcpServers = {
        context7.enable = true;
        sequentialThinking.enable = true;
        nixos.enable = true;
      };

      # Default agent files (file-based agents deployed to agents/)
      defaultAgentFiles = {
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

            **Small PDFs (<=50 pages):** Extract all pages
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
          '';
          examples = [
            "Index this PDF: /path/to/document.pdf"
            "Index all PDFs in /path/to/docs/ and return a markdown table"
            "Extract the TOC from /path/to/large-manual.pdf"
          ];
        };
      };

      # Default skills
      defaultSkills = {
        enable = true;
        builtins.adr-writer = true;
      };

      # Default file-based slash commands (.md files deployed via fileCommands)
      defaultFileCommands = {
        analyze-package-updates = {
          category = "maintenance";
          content = builtins.readFile ../programs/claude-code/_hm/commands/maintenance/analyze-package-updates.md;
        };
      };

      # Default slash commands
      defaultCommands = {
        plans = {
          description = "Generate high-level summary table of all plans";
          template = ''
            Generate a high-level summary of all plans in this repository.

            ## Instructions

            1. Find all plan files in `.claude/user-plans/` using: `fd -t f -e md . .claude/user-plans/`

            2. For each plan file, extract:
               - Plan number/name (from filename)
               - Status (look for `**Status**:` line)
               - Brief description (from title or first paragraph)

            3. Present as a concise markdown table with columns:
               | Plan | Status | Description |

            4. Use these status indicators:
               - `Planning` or `Design` → show as-is
               - `COMPLETE` or `TASK:COMPLETE` → show as "Complete"
               - `PENDING` → show as "Pending"
               - Partial completion → note which tasks done (e.g., "Tasks 1-2 done")

            5. After the table, briefly note:
               - Which plans are actively blocked or waiting
               - Any plans with remaining tasks that could be worked on

            Keep the output concise - this is meant to be a quick overview, not detailed analysis.
          '';
        };
      };
    };

    # Shared GitHub authentication presets for all personal hosts.
    # Usage: gitAuth.github = inputs.self.lib.gitAuthPresets.github;
    gitAuthPresets.github = {
      enable = true;
      mode = "bitwarden";
      bitwarden = {
        item = "github.com";
        field = "PAT-timtam2026";
      };
      cli.tokenOverrides.pr = {
        item = "github.com";
        field = "PAT-pubclassic";
      };
      orgs.kyosaku-kai = {
        bitwarden = {
          item = "github.com";
          field = "kyosaku-kai-2026";
        };
      };
    };

    claudeCode = {
      # Base config (enable, defaults, common settings)
      # NOTE: defaultAccount intentionally omitted — each deployment layer sets its own.
      # Dev-team sets "work", personal hosts override to "max".
      baseConfig = {
        enable = true;
        defaultModel = "opus";
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
            CLAUDE_CODE_MAX_OUTPUT_TOKENS = "65536";
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
            CLAUDE_CODE_MAX_OUTPUT_TOKENS = "65536";
          };
        };
      };

      # Work account template - structural preset for enterprise AI proxy access.
      # Deployment-specific values (baseUrl, bitwarden item, modelMappings) are
      # set by the team or host layer that consumes this preset.
      workAccount = {
        work = {
          enable = true;
          displayName = "Work Bedrock";
          model = "sonnet";
          api = {
            # baseUrl: set by team/host layer
            authMethod = "bedrock";
            # modelMappings: set by team/host layer
          };
          secrets.bearerToken.bitwarden = {
            # item + field: set by team/host layer
          };
          extraEnvVars = {
            DISABLE_TELEMETRY = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_ERROR_REPORTING = "1";
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
