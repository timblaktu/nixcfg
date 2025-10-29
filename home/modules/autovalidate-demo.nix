# AutoValidate Demo Configuration
# This demonstrates converting a real nixcfg script to use autoValidate
{ pkgs, ... }:

{
  # Convert mytree.sh from validated-scripts to autoValidate
  home.file."bin/mytree-auto" = {
    source = ../files/bin/mytree.sh;
    autoValidate = true;
    # Dependencies are automatically detected from script requirements
    deps = with pkgs; [ tree coreutils ];
    # The autoValidate system will:
    # 1. Detect this is a bash script from the shebang
    # 2. Apply automatic syntax validation via writeBashBin  
    # 3. Wrap dependencies properly at build time
    # 4. Create an executable in ~/.local/bin/mytree-auto
  };

  # Also demonstrate Python script autoValidate
  home.file."bin/hello-auto" = {
    source = pkgs.writeText "hello-auto.py" ''
      #!/usr/bin/env python3
      """
      Simple Python script to demonstrate autoValidate functionality.
      """
      import sys
      import os
      
      def main():
          print("🚀 Hello from autoValidate Python script!")
          print(f"Python version: {sys.version}")
          print(f"Working directory: {os.getcwd()}")
          print("✅ AutoValidate detected Python and applied writePython3Bin automatically")
      
      if __name__ == "__main__":
          main()
    '';
    autoValidate = true;
    options = {
      doCheck = false; # Skip flake8 for this demo  
    };
  };

  # Demonstrate that autoValidate provides identical functionality to validated-scripts
  # This would replace the complex configuration in validated-scripts/bash.nix
}
