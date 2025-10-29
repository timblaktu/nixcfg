#!/usr/bin/env python3
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
        print("🐍 AutoValidate Python Script")
        print("Language: Python 3 (auto-detected)")
        print("Dependencies: psutil (auto-managed)")
        print("Validation: ✅ Automatic via autoValidate")
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