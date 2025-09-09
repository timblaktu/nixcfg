{ config, lib, ... }:

with lib;

let
  cfg = config.programs.claude-code;

in {
  options.programs.claude-code.slashCommands = {
    documentation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable documentation commands";
      };
      commands = mkOption {
        type = types.attrs;
        default = {
          generateReadme = "claude-doc-gen readme";
          apiDocs = "claude-doc-gen api";
        };
        description = "Documentation command handlers";
      };
    };
    
    security = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable security commands";
      };
      commands = mkOption {
        type = types.attrs;
        default = {
          audit = "claude-security audit";
          secretsScan = "claude-security secrets";
        };
        description = "Security command handlers";
      };
    };
    
    refactoring = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable refactoring commands";
      };
      commands = mkOption {
        type = types.attrs;
        default = {
          extractFunction = "claude-refactor extract";
          renameSymbol = "claude-refactor rename";
        };
        description = "Refactoring command handlers";
      };
    };
    
    context = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable context management commands";
      };
      commands = mkOption {
        type = types.attrs;
        default = {
          cleanup = "claude-context cleanup";
          save = "claude-context save";
          load = "claude-context load";
        };
        description = "Context command handlers";
      };
    };
    
    custom = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            description = "Command description";
          };
          usage = mkOption {
            type = types.str;
            description = "Usage string";
          };
          handler = mkOption {
            type = types.str;
            description = "Command handler";
          };
          aliases = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Command aliases";
          };
          permissions = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Required permissions";
          };
        };
      });
      default = {};
      description = "Custom slash command definitions";
    };
  };

  config.programs.claude-code._internal.slashCommandDefs = {
    documentation = mkIf cfg.slashCommands.documentation.enable {
      "generate-readme" = {
        name = "generate-readme";
        description = "Generate comprehensive README documentation";
        usage = "/documentation generate-readme [--format markdown|rst]";
        command = cfg.slashCommands.documentation.commands.generateReadme;
      };
      
      "api-docs" = {
        name = "api-docs";
        description = "Generate API documentation";
        usage = "/documentation api-docs [--output path]";
        command = cfg.slashCommands.documentation.commands.apiDocs;
      };
    };

    security = mkIf cfg.slashCommands.security.enable {
      "audit" = {
        name = "audit";
        description = "Run security audit on codebase";
        usage = "/security audit [--severity high|medium|low]";
        command = cfg.slashCommands.security.commands.audit;
      };
      
      "secrets-scan" = {
        name = "secrets-scan";
        description = "Scan for exposed secrets";
        usage = "/security secrets-scan";
        command = cfg.slashCommands.security.commands.secretsScan;
      };
    };

    refactoring = mkIf cfg.slashCommands.refactoring.enable {
      "extract-function" = {
        name = "extract-function";
        description = "Extract code into a function";
        usage = "/refactor extract-function <start-line> <end-line>";
        command = cfg.slashCommands.refactoring.commands.extractFunction;
      };
      
      "rename-symbol" = {
        name = "rename-symbol";
        description = "Rename a symbol across the codebase";
        usage = "/refactor rename-symbol <old-name> <new-name>";
        command = cfg.slashCommands.refactoring.commands.renameSymbol;
      };
    };

    context = mkIf cfg.slashCommands.context.enable {
      "cleanup" = {
        name = "cleanup";
        description = "Clean up conversation context";
        usage = "/context cleanup";
        command = cfg.slashCommands.context.commands.cleanup;
      };
      
      "save" = {
        name = "save";
        description = "Save current context";
        usage = "/context save <name>";
        command = cfg.slashCommands.context.commands.save;
      };
      
      "load" = {
        name = "load";
        description = "Load saved context";
        usage = "/context load <name>";
        command = cfg.slashCommands.context.commands.load;
      };
    };

    custom = cfg.slashCommands.custom;
  };
}