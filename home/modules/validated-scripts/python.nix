# Python Scripts - Validated Python script definitions
{ config, lib, pkgs, mkValidatedScript, mkPythonScript, writers, ... }:

with lib;

let
  cfg = config.validatedScripts;
  
  # Define Python scripts using the mkPythonScript helper
  pythonScripts = {
    
    # Example Python script to demonstrate the infrastructure
    system-info-py = mkPythonScript {
      name = "system-info-py";
      deps = with pkgs.python3Packages; [ psutil ];
      text = /* python */ ''
        # !/usr/bin/env python3
        """
        Example validated Python script with dependency management
        Demonstrates system information gathering with psutil
        """
        
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
          # Test help output
          ${pythonScripts.system-info-py}/bin/system-info-py --info | grep -q "Validated Python Script"
          echo "✅ Python help test passed"
        '';
        json_output = writers.testBash "test-system-info-py-json" ''
          # Test JSON output format
          output=$(${pythonScripts.system-info-py}/bin/system-info-py --json)
          echo "$output" | python3 -m json.tool > /dev/null
          echo "✅ JSON output test passed"
        '';
        basic = writers.testBash "test-system-info-py-basic" ''
          # Test basic execution
          ${pythonScripts.system-info-py}/bin/system-info-py | grep -q "System Information"
          echo "✅ Python basic execution test passed"
        '';
      };
    };
    
    # System monitoring script temporarily disabled due to Python formatting issues
    # TODO: Re-enable after fixing PEP8 compliance
    
  };
  
in {
  config = mkIf (cfg.enable && cfg.enablePythonScripts) {
    validatedScripts.pythonScripts = pythonScripts;
  };
}