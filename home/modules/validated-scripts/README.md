# Validated Scripts System

A Nix-based framework for creating scripts with automatic validation, dependency management, and multi-language support.

## Quick Start

Enable in your home-manager configuration:

```nix
homeBase.enableValidatedScripts = true;
```

## What It Does

Instead of writing scripts that might break at runtime, this system:

- ✅ **Validates syntax** at build time (catches errors before deployment)
- ✅ **Manages dependencies** automatically (each script gets exactly what it needs)
- ✅ **Supports multiple languages** (Bash, Python, PowerShell, etc.)
- ✅ **Includes testing** framework for reliable scripts
- ✅ **Works with editors** (syntax highlighting with `/* lang */` comments)

## Examples

### Simple Bash Script
```nix
hello-script = mkBashScript {
  name = "hello";
  text = /* bash */ ''
    #!/usr/bin/env bash
    echo "Hello from validated script!"
  '';
};
```

### Python Script with Dependencies
```nix
system-info = mkPythonScript {
  name = "system-info";
  deps = with pkgs.python3Packages; [ psutil ];
  text = /* python */ ''
    import psutil
    print(f"CPU cores: {psutil.cpu_count()}")
    print(f"Memory: {psutil.virtual_memory().total // (1024**3)} GB")
  '';
};
```

### Script with Tests
```nix
my-tool = mkBashScript {
  name = "my-tool";
  text = /* bash */ ''
    echo "Working correctly"
  '';
  tests = {
    basic = writers.testBash "test-my-tool" ''
      ${my-tool}/bin/my-tool | grep -q "Working correctly"
    '';
  };
};
```

## Available Languages

| Language | Writer | Validation |
|----------|--------|------------|
| Bash | `mkBashScript` | shellcheck |
| Python | `mkPythonScript` | flake8/syntax |
| PowerShell | `mkPowerShellScript` | AST validation |

## Key Benefits

**Before (traditional scripts):**
- Runtime errors 💥
- Missing dependencies 📦❌
- No validation ⚠️
- Hard to test 🧪❌

**After (validated scripts):**
- Build-time validation ✅
- Automatic dependencies 📦✅
- Syntax checking ✅
- Built-in testing 🧪✅

## File Structure

```
home/modules/validated-scripts/
├── README.md          # This file
├── default.nix       # Main module
├── bash.nix          # Bash scripts
├── python.nix        # Python scripts
├── powershell.nix    # PowerShell scripts
└── tests.nix         # Test framework
```

## Current Status

- ✅ **Phase 1 Complete**: Infrastructure working
- 📋 **Phase 2 Next**: Convert existing `writeShellScriptBin` scripts
- 📋 **Phase 3 Later**: Migrate utility scripts from `home/files/bin/`

## How It Works

1. **Define scripts** in language-specific modules
2. **Build-time validation** catches syntax errors
3. **Dependency injection** ensures libraries are available
4. **Testing integration** with `nix flake check`
5. **Deploy to `$HOME/bin`** via home-manager

This transforms script management from error-prone manual processes into a reliable, tested, and validated system.