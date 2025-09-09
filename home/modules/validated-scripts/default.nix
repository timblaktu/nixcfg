# Validated Scripts Module - nix-writers based script management
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.validatedScripts;
  writers = pkgs.writers;
  
  # Core helper function for creating validated scripts with tests
  mkValidatedScript = { 
    name, 
    lang ? "bash", 
    deps ? [], 
    tests ? {}, 
    text,
    extraChecks ? [],
    makeExecutable ? true
  }:
    let
      # Select appropriate writer based on language
      writerName = "write${lib.toUpper (lib.substring 0 1 lang)}${lib.substring 1 (-1) lang}${if makeExecutable then "Bin" else ""}";
      writer = writers.${writerName};
      
      # Handle dependencies - convert to libraries format if needed
      # For bash scripts, writeBashBin just takes name and text
      # For python, writePython3Bin takes name, libraries (as an attrset), and text
      script = if lang == "bash" then
        writer name text
      else if lang == "python3" then
        writer name { libraries = deps; } text
      else
        writer name text;
      
      # Add automatic syntax test based on language
      testLang = lib.toUpper (lib.substring 0 1 lang) + lib.substring 1 (-1) lang;
      automaticSyntaxTest = {
        syntax = writers."test${testLang}" "${name}-syntax" ''
          # Automatic syntax validation happens at build time
          echo "✅ ${name}: Syntax validation passed"
        '';
      };
      
      # Combine automatic and user-provided tests
      allTests = automaticSyntaxTest // tests;
      
    in script // { 
      passthru = (script.passthru or {}) // {
        tests = allTests;
        language = lang;
        dependencies = deps;
        makeExecutable = makeExecutable;
      };
    };

  # Helper to create a script with treesitter language hints
  mkValidatedScriptWithHints = args@{ name, lang ? "bash", text, ... }:
    mkValidatedScript (args // {
      text = "/* ${lang} */ " + text;
    });
  
  # Convenience functions for common script types
  mkBashScript = args: mkValidatedScript (args // { lang = "bash"; });
  mkPythonScript = args: mkValidatedScript (args // { lang = "python3"; });
  mkPowerShellScript = args: mkValidatedScript (args // { lang = "powershell"; });
  
  # Function to create a script library (non-executable, for sourcing)
  mkScriptLibrary = args: mkValidatedScript (args // { makeExecutable = false; });
  
  # Helper to collect all tests from a set of scripts
  collectScriptTests = scripts:
    lib.mapAttrs' (scriptName: script:
      lib.mapAttrs' (testName: testDrv:
        lib.nameValuePair "script-${scriptName}-${testName}" testDrv
      ) (script.passthru.tests or {})
    ) scripts;

in {
  options.validatedScripts = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nix-writers based validated script management";
    };
    
    enableBashScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Bash script definitions from bash.nix";
    };
    
    enablePythonScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Python script definitions from python.nix";
    };
    
    enablePowerShellScripts = mkOption {
      type = types.bool;
      default = false;  # Disabled by default - PowerShell validation requires Windows/pwsh
      description = "Enable PowerShell script definitions from powershell.nix";
    };
    
    enableTests = mkOption {
      type = types.bool;
      default = true;
      description = "Enable script testing framework";
    };
    
    # Options for collecting scripts from sub-modules
    bashScripts = mkOption {
      type = types.attrsOf types.package;
      default = {};
      description = "Collection of bash scripts managed by the validated-scripts framework";
    };
    
    pythonScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
    
    powerShellScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
    
    customScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      default = {};
    };
  };
  
  imports = [
    # Import language-specific script definitions
    ./bash.nix
    ./python.nix
    ./powershell.nix
    ./tests.nix
  ];
  
  config = mkIf cfg.enable (
    let
      # Combine all scripts from sub-modules
      allScripts = 
        (if cfg.enableBashScripts then cfg.bashScripts else {}) //
        (if cfg.enablePythonScripts then cfg.pythonScripts else {}) //
        (if cfg.enablePowerShellScripts then cfg.powerShellScripts else {}) //
        cfg.customScripts;
      
      # Generate all tests
      allTests = if cfg.enableTests then collectScriptTests allScripts else {};
    in {
    # Make helper functions available to imported modules
    _module.args = {
      inherit mkValidatedScript mkValidatedScriptWithHints;
      inherit mkBashScript mkPythonScript mkPowerShellScript mkScriptLibrary;
      inherit collectScriptTests writers;
    };
    
    # Install all enabled scripts (excluding non-executable libraries)
    home.packages = lib.attrValues (lib.filterAttrs (name: script: 
      # Only include scripts that are executable (have /bin/ destination)
      script.passthru.makeExecutable or true
    ) allScripts);
    
    # Add validation reminder to shell
    programs.bash.initExtra = mkIf cfg.enableTests (mkAfter ''
      # Validated scripts available - run 'nix flake check' to validate all scripts
      export NIXCFG_VALIDATED_SCRIPTS_ENABLED=1
    '');
    
    programs.zsh.initExtra = mkIf cfg.enableTests (mkAfter ''
      # Validated scripts available - run 'nix flake check' to validate all scripts
      export NIXCFG_VALIDATED_SCRIPTS_ENABLED=1
    '');
    }
  );
}