# Nix Script Writers Implementation Guide

## Overview
Transform nixcfg from using simple `writeShellScriptBin` to leveraging the comprehensive nix script writers framework (`pkgs.writers`) for build-time validation, proper dependency management, and multi-language support.

## Core Architecture Pattern

```nix
# modules/dev-scripts/default.nix
{ config, lib, pkgs, ... }:
let
  writers = pkgs.writers;
  
  # Create a script with embedded tests
  mkValidatedScript = { name, lang ? "bash", deps ? [], tests ? {}, text }:
    let
      writer = writers."write${lib.strings.capitalize lang}Bin";
      script = writer name (
        if deps != [] then { libraries = deps; } else {}
      ) text;
    in script // { 
      passthru.tests = tests // {
        syntax = writers."test${lib.strings.capitalize lang}" "${name}-syntax" ''
          # Automatic syntax validation happens at build time
          echo "Syntax OK"
        '';
      };
    };

  # Scripts defined declaratively
  scripts = {
    git-clean-branches = mkValidatedScript {
      name = "git-clean-branches";
      lang = "bash";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        git branch --merged | grep -v "\*\|main\|master" | xargs -r git branch -d
      '';
      tests.integration = writers.testBash "test-git-clean" ''
        # Test logic here
      '';
    };
    
    data-processor = mkValidatedScript {
      name = "data-processor";
      lang = "python3";
      deps = with pkgs.python3Packages; [ pandas numpy ];
      text = ''
        import pandas as pd
        import numpy as np
        import sys
        
        # Your Python code here
      '';
    };
  };
in {
  home.packages = lib.attrValues scripts;
  
  # Run all tests as part of system checks
  system.checks = lib.mapAttrs' (name: script:
    lib.nameValuePair "script-${name}" script.passthru.tests.syntax
  ) scripts;
}
```

## Available Writers

### Script Writers (with automatic syntax checking)
- `writeBashBin` / `writeBash` - Bash with shellcheck validation
- `writePython3Bin` / `writePython3` - Python with syntax checking
- `writeFishBin` / `writeFish` - Fish shell
- `writeJSBin` / `writeJS` - Node.js
- `writeRubyBin` / `writeRuby` - Ruby
- `writeLuaBin` / `writeLua` - Lua
- `writePerlBin` / `writePerl` - Perl
- `writeNuBin` / `writeNu` - Nushell

### Compiled Language Writers
- `writeC` / `writeCBin` - C with gcc
- `writeRustBin` - Rust with rustc
- `writeGo` - Go programs
- `writeHaskellBin` - Haskell

### Configuration Writers
- `writeJSON`, `writeYAML`, `writeTOML` - With validation

## Key Features to Implement

### 1. Dependency Management
```nix
writers.writePython3Bin "my-script" {
  libraries = [ pkgs.python3Packages.requests pkgs.python3Packages.numpy ];
} ''
  import requests
  import numpy as np
  # Code has access to these libraries
''
```

### 2. Build-time Validation
All scripts are validated during `nix build`:
- Bash scripts run through shellcheck
- Python checks syntax
- Compiled languages fail on compilation errors

### 3. Testing Integration
```nix
writers.writeBashBin "my-script" {} ''
  echo "Hello, world"
'' // {
  passthru.tests = {
    simple = writers.testBash "test-my-script" ''
      ${my-script}/bin/my-script | grep "Hello"
    '';
  };
}
```

### 4. Flake Checks
```nix
checks = {
  my-script-syntax = writers.testBash "check-syntax" ''
    ${pkgs.shellcheck}/bin/shellcheck ${./scripts/my-script.sh}
  '';
};
```

## Treesitter Integration for Editor Support

Use language-specific comment hints for proper syntax highlighting in nix files:

```nix
let
  scriptSources = {
    myPythonScript = /* python */ ''
      import sys
      
      def main():
          print("Hello from Nix!")
      
      if __name__ == "__main__":
          main()
    '';
    
    myBashScript = /* bash */ ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "Running from Nix!"
    '';
  };
in {
  # Editor recognizes /* lang */ comments for syntax highlighting
}
```

## Advanced Validation

```nix
writers.writePython3Bin "validated-script" {
  libraries = [ pkgs.python3Packages.mypy ];
  postCheck = ''
    mypy --strict $out/bin/validated-script
  '';
} ''
  # Type-checked Python code
''
```

## Implementation Strategy

### ✅ **Phase 1: Foundation Infrastructure** - COMPLETED
**Create nix-writers infrastructure with multi-language support**

**Completed:**
- ✅ Created `home/modules/validated-scripts/` module structure
- ✅ Built `mkValidatedScript` helper with automatic syntax validation
- ✅ Language-specific modules: `bash.nix`, `python.nix`, `powershell.nix`, `tests.nix`
- ✅ Integration with `home/modules/base.nix` via `enableValidatedScripts` option
- ✅ Working example scripts with build-time validation:
  - `hello-validated` (Bash) - ✅ Build-time shellcheck validation
  - `system-info-py` (Python) - ✅ PEP 8 validation with flake8, dependency management
  - `windows-terminal-config` (PowerShell) - ✅ Structure validation (disabled by default)
- ✅ Treesitter integration with `/* lang */` comments
- ✅ Automatic dependency management per script
- ✅ Environment variable integration (`NIXCFG_VALIDATED_SCRIPTS_ENABLED=1`)

### 📋 **Phase 2: Convert writeShellScriptBin** - NEXT
**Priority migration of existing inline scripts**

**Target scripts:**
1. `home/common/git.nix` - smart-nvimdiff → `writeBashBin` with git/neovim deps
2. `home/modules/terminal-verification.nix` - check-terminal-setup, setup-terminal-fonts
3. `home/common/esp-idf.nix` - All 4 ESP-IDF tools
4. `home/common/claude-code.nix` - claudeCodeWrapper

**Benefits:** Build-time validation, dependency management, consistent error handling

### 📋 **Phase 3: Strategic Script Migration**
**Convert key utility scripts from `home/files/bin/`**

**Tier 1 - Core Infrastructure:**
- `tmux-auto-attach` → `writeBashBin` with tmux dependency + tests
- `tmux-session-picker` → `writeBashBin` with fzf, tmux deps + comprehensive tests
- `colorfuncs.sh` → Script library as `writeBash` (sourced, not executable)

**Tier 2 - Development Tools:**
- `functions.sh` → Modular breakdown into smaller validated scripts
- `diagnose-emoji-rendering` → `writeBashBin` with font testing framework
- Cross-platform utilities with proper validation

### 📋 **Phase 4: Advanced Features**
**Multi-language expansion and testing integration**

1. **PowerShell scripts:** Enable conditionally on Windows/WSL systems
2. **Python conversions:** Data processing scripts with numpy/pandas
3. **Comprehensive test suites:** Integration tests, cross-platform compatibility
4. **Flake checks integration:** All script tests available via `nix flake check`

### 📋 **Phase 5: Advanced Organization**
**Optimize and enhance the validated scripts ecosystem**

1. **Modular function libraries:** Break down large scripts into reusable components
2. **Enhanced validation:** Custom linting rules, performance benchmarks
3. **Documentation generation:** Auto-generated docs from script metadata
4. **Template system:** Easy creation of new validated scripts

## Current Status: Phase 1 ✅ Complete, Ready for Phase 2

## Benefits
- **Build-time validation**: Syntax errors caught during `nix build`, not runtime
- **Dependency management**: Each script gets exactly the libraries it needs
- **Testing framework**: Built-in test support with CI/CD integration
- **Multi-language**: Unified interface across all supported languages
- **Editor support**: Treesitter highlighting with language hints
- **Reproducibility**: Pinned interpreters and dependencies

## Implemented File Structure
```
nixcfg/
├── home/modules/
│   ├── validated-scripts/          # ✅ IMPLEMENTED
│   │   ├── default.nix            # ✅ Main module with mkValidatedScript
│   │   ├── bash.nix               # ✅ Bash script definitions
│   │   ├── python.nix             # ✅ Python script definitions  
│   │   ├── powershell.nix         # ✅ PowerShell script definitions
│   │   └── tests.nix              # ✅ Test framework and utilities
│   ├── base.nix                   # ✅ UPDATED - imports validated-scripts
│   └── ...
├── flake-modules/                 # 📋 TODO: Add flake checks integration
└── flake.nix                      # 📋 TODO: Expose script tests as checks
```

This transforms nixcfg into a polyglot development platform where every script is validated, tested, and packaged with its dependencies at build time.