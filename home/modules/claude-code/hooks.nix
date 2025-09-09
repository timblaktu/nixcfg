{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.claude-code;

  mkHook = {
    matcher,
    type ? "command",
    command ? null,
    script ? null,
    env ? {},
    timeout ? 60,
    continueOnError ? true
  }: {
    inherit matcher;
    hooks = [({
      inherit type timeout;
    } // (if command != null 
      then { command = command; }
      else { script = script; })
    // (optionalAttrs (env != {}) { inherit env; })
    // (optionalAttrs continueOnError { continueOnError = true; }))];
  };

in {
  options.programs.claude-code.hooks = {
    formatting = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auto-formatting hooks";
      };
      commands = mkOption {
        type = types.attrsOf types.str;
        default = {
          py = "${pkgs.black}/bin/black \"$file_path\" 2>/dev/null || true";
          nix = "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt \"$file_path\" 2>/dev/null || true";
          js = "${pkgs.nodePackages.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
          json = "${pkgs.nodePackages.prettier}/bin/prettier --write \"$file_path\" 2>/dev/null || true";
          rs = "${pkgs.rustfmt}/bin/rustfmt \"$file_path\" 2>/dev/null || true";
          go = "${pkgs.go}/bin/gofmt -w \"$file_path\" 2>/dev/null || true";
        };
        description = "Formatting commands by file extension";
      };
    };
    
    linting = {
      enable = mkEnableOption "linting hooks";
      commands = mkOption {
        type = types.attrsOf types.str;
        default = {
          py = "${pkgs.python3Packages.pylint}/bin/pylint \"$file_path\" 2>/dev/null || true";
          js = "${pkgs.nodePackages.eslint}/bin/eslint \"$file_path\" 2>/dev/null || true";
        };
        description = "Linting commands by file extension";
      };
    };
    
    security = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable security hooks";
      };
      blockedPatterns = mkOption {
        type = types.listOf types.str;
        default = [ "\\\\.env" "\\\\.secrets" "id_rsa" "\\\\.key$" ];
        description = "File patterns to block access to";
      };
    };
    
    git = {
      enable = mkEnableOption "git integration hooks";
      autoStage = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically stage modified files";
      };
      autoCommit = mkEnableOption "automatically commit changes";
    };
    
    testing = {
      enable = mkEnableOption "test automation hooks";
      sourcePattern = mkOption {
        type = types.str;
        default = "src/.*\\\\.(py|js|ts)$";
        description = "Pattern for source files that trigger tests";
      };
      command = mkOption {
        type = types.str;
        default = "npm test 2>/dev/null || pytest 2>/dev/null || true";
        description = "Test command to run";
      };
    };
    
    logging = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable logging hooks";
      };
      logPath = mkOption {
        type = types.str;
        default = "~/.claude/logs/tool-usage.log";
        description = "Path to log file";
      };
      verbose = mkEnableOption "include tool inputs in logs";
    };
    
    notifications = {
      enable = mkEnableOption "notification hooks";
      matcher = mkOption {
        type = types.str;
        default = "";
        description = "Event matcher for notifications";
      };
      title = mkOption {
        type = types.str;
        default = "Claude Code";
        description = "Notification title";
      };
      message = mkOption {
        type = types.str;
        default = "Finished working in current project";
        description = "Notification message";
      };
    };
    
    custom = mkOption {
      type = types.attrs;
      default = { PreToolUse = []; PostToolUse = []; Start = []; Stop = []; };
      description = "Custom hook definitions";
    };
  };

  config.programs.claude-code._internal.hooks = {
    PreToolUse = null;
    PostToolUse = null;  
    Start = null;
    Stop = null;
  };
}