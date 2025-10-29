# AutoValidate Migration Examples

This document demonstrates migrating from the current `validated-scripts` approach to the new upstream `autoValidate` functionality.

## Example 1: Python Script Migration

### Before: Validated Scripts Approach (Current)

```nix
# home/modules/validated-scripts/python.nix
system-info-py = mkPythonScript {
  name = "system-info-py";
  deps = with pkgs.python3Packages; [ psutil ];
  text = /* python */ ''
    #!/usr/bin/env python3
    """Example validated Python script with dependency management"""
    
    import sys
    import platform
    import json
    import argparse
    
    try:
        import psutil
    except ImportError:
        print("Error: psutil not available", file=sys.stderr)
        sys.exit(1)

    def get_system_info():
        """Gather basic system information"""
        return {
            "platform": platform.system(),
            "release": platform.release(), 
            "architecture": platform.architecture()[0],
            "cpu_count": psutil.cpu_count(),
            "memory_total_gb": round(psutil.virtual_memory().total / (1024**3), 2),
            "python_version": sys.version.split()[0]
        }

    def main():
        parser = argparse.ArgumentParser(description="Get system information")
        parser.add_argument("--json", action="store_true", help="Output as JSON")
        parser.add_argument("--info", action="store_true", help="Show script info")
        args = parser.parse_args()

        if args.info:
            print("🐍 Validated Python Script")
            print("Language: Python 3")
            print("Dependencies: psutil")
            print("Validated: ✅ at build time")
            return

        info = get_system_info()

        if args.json:
            print(json.dumps(info, indent=2))
        else:
            print("🖥️  System Information:")
            for key, value in info.items():
                print(f"  {key}: {value}")

    if __name__ == "__main__":
        main()
  '';
  tests = {
    help = writers.testBash "test-system-info-py-help" ''
      ${pythonScripts.system-info-py}/bin/system-info-py --info | grep -q "Validated Python Script"
      echo "✅ Python help test passed"
    '';
    json_output = writers.testBash "test-system-info-py-json" ''
      output=$(${pythonScripts.system-info-py}/bin/system-info-py --json)
      echo "$output" | python3 -m json.tool > /dev/null
      echo "✅ JSON output test passed"
    '';
    basic = writers.testBash "test-system-info-py-basic" ''
      ${pythonScripts.system-info-py}/bin/system-info-py | grep -q "System Information"
      echo "✅ Python basic execution test passed"
    '';
  };
};
```

### After: AutoValidate Approach (Target)

```nix
# home/modules/base.nix or similar
home.file."bin/system-info-py" = {
  source = ./scripts/system-info.py;
  autoValidate = true;
  deps = with pkgs.python3Packages; [ psutil ];
  options = {
    # Optional: disable flake8 for scripts that don't meet PEP8
    # doCheck = false;
  };
};
```

**Benefits of Migration:**
- ✅ **50% less code** - No custom test definitions needed
- ✅ **Upstream support** - Uses standard nixpkgs writers
- ✅ **Automatic validation** - Build-time syntax and style checking
- ✅ **Sidecar support** - Can use `./scripts/system-info.py.nix` for complex deps
- ✅ **Zero home-manager changes** - Standard `home.file` interface

## Example 2: Bash Script Migration

### Before: Validated Scripts Approach

```nix
smart-nvimdiff = mkBashScript {
  name = "smart-nvimdiff";
  deps = with pkgs; [ git neovim coreutils ];
  text = /* bash */ ''
    #!/usr/bin/env bash
    # Smart mergetool wrapper for neovim
    # Automatically switches to 2-way diff when BASE is empty
    
    BASE="$1"
    LOCAL="$2"  
    REMOTE="$3"
    MERGED="$4"
    
    # Check if BASE file exists and is not empty
    if [ -f "$BASE" ] && [ -s "$BASE" ]; then
        # Normal 4-way diff with non-empty BASE
        exec nvim -d "$MERGED" "$LOCAL" "$BASE" "$REMOTE" \
          -c "wincmd J" \
          -c "call timer_start(250, {-> execute('wincmd b')})"
    else
        # Empty or missing BASE, overwrite MERGED with LOCAL
        cp "$LOCAL" "$MERGED"
        exec nvim -d "$MERGED" "$REMOTE"
    fi
  '';
  tests = {
    syntax = writers.testBash "test-smart-nvimdiff-syntax" ''
      echo "✅ Syntax validation passed at build time"
    '';
    argument_validation = writers.testBash "test-smart-nvimdiff-args" ''
      echo "✅ Argument validation test passed (placeholder)"
    '';
  };
};
```

### After: AutoValidate Approach

```nix
home.file."bin/smart-nvimdiff" = {
  source = ./scripts/smart-nvimdiff.sh;
  autoValidate = true;
  deps = with pkgs; [ git neovim coreutils ];
  # No need for explicit tests - shellcheck validates syntax automatically
};
```

**Benefits:**
- ✅ **Automatic shellcheck** - Built-in bash validation
- ✅ **Dependency management** - Same interface, cleaner syntax  
- ✅ **File-based scripts** - Easier to edit and maintain
- ✅ **No test boilerplate** - Automatic syntax validation

## Example 3: Complex Dependencies with Sidecar Files

For scripts with complex dependency requirements, use sidecar `.nix` files:

### Script: `./scripts/complex-tool.py`
```python
#!/usr/bin/env python3
import requests
import click
import numpy as np

# Complex tool implementation...
```

### Sidecar: `./scripts/complex-tool.py.nix`
```nix
{ lib, pkgs }:
{
  deps = with pkgs.python3Packages; [
    requests
    click
    numpy
    # More complex dependencies...
  ];
  
  options = {
    doCheck = false;  # Skip flake8 for this specific script
    flakeIgnore = [ "E501" "W503" ];  # Or ignore specific rules
  };
}
```

### Configuration:
```nix
home.file."bin/complex-tool" = {
  source = ./scripts/complex-tool.py;
  autoValidate = true;
  # Dependencies and options loaded automatically from sidecar file
  # Can still override with explicit deps/options if needed
};
```

## Migration Strategy

1. **Phase 1: Test Conversion**
   - Convert 1-2 simple scripts to autoValidate
   - Verify functionality works as expected
   - Document any limitations discovered

2. **Phase 2: Gradual Migration**  
   - Convert scripts one-by-one from validated-scripts
   - Keep both systems running during transition
   - Migrate most commonly used scripts first

3. **Phase 3: Cleanup**
   - Remove validated-scripts module once all scripts migrated
   - Update documentation to use autoValidate examples
   - Submit upstream contributions to nixpkgs/home-manager

## Compatibility Matrix

| Feature | Validated Scripts | AutoValidate | Migration Notes |
|---------|------------------|--------------|----------------|
| Bash scripts | ✅ | ✅ | Direct migration |
| Python scripts | ✅ | ✅ | Same dependency syntax |
| Custom tests | ✅ | ⚠️ | Move to separate test files |
| Build-time validation | ✅ | ✅ | Better - uses nixpkgs writers |
| Complex dependencies | ✅ | ✅ | Use sidecar .nix files |
| Multiple languages | ✅ | ✅ | Automatic detection |

## Limitations Discovered

1. **Testing Framework**: AutoValidate provides automatic syntax validation but custom test logic needs separate implementation
2. **Migration Effort**: Scripts need to be moved to external files (can't be inline in Nix)
3. **Validation Rules**: Python scripts get stricter flake8 validation by default (can be disabled)

## Next Steps

The autoValidate system is ready for production use and provides a clean migration path from the current validated-scripts approach.