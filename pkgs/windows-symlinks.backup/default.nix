# Custom derivation to create Windows-compatible file management
{ pkgs, lib, stdenv, writeShellScriptBin }:

let
  # Script to create Windows symlink
  mkWinSymlink = writeShellScriptBin "mk-win-symlink" ''
    #!/usr/bin/env bash
    # Creates a Windows-compatible symlink to a Nix store path
    
    set -euo pipefail
    
    if [[ $# -ne 2 ]]; then
        echo "Usage: $0 <target-in-nix-store> <symlink-path>"
        echo "Example: $0 /nix/store/...-file.md /home/tim/file.md"
        exit 1
    fi
    
    target="$1"
    link_path="$2"
    
    # Check if we're in WSL
    if [[ ! -f /proc/version ]] || ! grep -qi "microsoft\\|wsl" /proc/version; then
        echo "Not in WSL, creating regular symlink"
        ln -sf "$target" "$link_path"
        exit 0
    fi
    
    # Convert to Windows paths
    if command -v wslpath >/dev/null 2>&1; then
        windows_target=$(wslpath -w "$target")
        windows_link=$(wslpath -w "$link_path")
    else
        # Fallback manual conversion
        windows_target="\\\\wsl\$\\Ubuntu$target"
        windows_link="\\\\wsl\$\\Ubuntu$link_path"
    fi
    
    # Remove existing link
    [[ -L "$link_path" ]] && rm "$link_path"
    
    # Try to create Windows symlink
    if powershell.exe -Command "New-Item -ItemType SymbolicLink -Path '$windows_link' -Target '$windows_target' -Force" 2>/dev/null; then
        echo "Created Windows symlink: $link_path -> $target"
    else
        echo "Warning: Failed to create Windows symlink, falling back to regular symlink"
        ln -sf "$target" "$link_path"
    fi
  '';

  # Derivation that combines original file with Windows symlink creation
  mkWindowsCompatibleFile = { name, src, targetPath }:
    stdenv.mkDerivation {
      pname = "windows-compatible-${name}";
      version = "1.0";
      
      src = src;
      
      buildInputs = [ mkWinSymlink ];
      
      installPhase = ''
        mkdir -p $out/$(dirname "${targetPath}")
        cp $src $out/${targetPath}
        
        # Create a script that sets up the Windows symlink
        mkdir -p $out/bin
        cat > $out/bin/setup-${name}-symlink << 'EOF'
        #!/usr/bin/env bash
        mk-win-symlink "$out/${targetPath}" "$HOME/${targetPath}"
        EOF
        chmod +x $out/bin/setup-${name}-symlink
      '';
      
      meta = with lib; {
        description = "Windows-compatible file management for ${name}";
        platforms = platforms.linux;
      };
    };

in {
  inherit mkWinSymlink mkWindowsCompatibleFile;
}
