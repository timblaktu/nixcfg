# Demonstration: AutoValidate vs Validated Scripts
# This shows the target configuration using autoValidate
{ pkgs, ... }:

{
  # Example 1: Python script with sidecar dependencies
  home.file."bin/system-info-py" = {
    source = ./scripts/system-info.py;
    autoValidate = true;
    # Dependencies loaded automatically from ./scripts/system-info.py.nix
  };

  # Example 2: Simple bash script with inline dependencies  
  home.file."bin/hello-bash" = {
    source = pkgs.writeText "hello-bash.sh" ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "🎉 Hello from autoValidate bash script!"
      echo "Current time: $(date)"
      echo "Script validation: ✅ Automatic via shellcheck"
    '';
    autoValidate = true;
    deps = with pkgs; [ coreutils ];
  };

  # Example 3: Python script with inline options
  home.file."bin/quick-test" = {
    source = pkgs.writeText "quick-test.py" ''
      #!/usr/bin/env python3
      print("Quick test script!")
      # This might not meet PEP8 standards, but that's OK for demos
    '';
    autoValidate = true;
    options = {
      doCheck = false; # Disable flake8 for quick scripts
    };
  };

  # Example 4: File-based script (most common pattern)
  home.file."bin/diagnostic-tool" = {
    source = ./scripts/diagnostic-tool.sh; # (if it existed)
    autoValidate = true;
    # Uses automatic bash detection via shebang/extension
  };
}
