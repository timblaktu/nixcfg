#!/usr/bin/env bash
# Make script executable
chmod +x "$0" 2>/dev/null || true

# Targeted debug for .env file issue
set -euo pipefail

cd /home/tim/src/nixcfg

echo "=== STEP-BY-STEP DEBUG ==="

echo
echo "1. Test our mkHomeFiles function in isolation:"
nix eval --impure --expr '
let 
  lib = import <nixpkgs/lib>;
  filesDir = ./home/files;
  mkHomeFiles = { sourceDir, targetDir, executable ? false }: 
    let
      dirContents = builtins.readDir sourceDir;
      files = lib.filterAttrs (name: type: type == "regular") dirContents;
      fileEntries = lib.mapAttrs'\'' (name: value: {
        name = "${targetDir}/${name}";
        value = {
          source = sourceDir + "/${name}";
          executable = executable;
        };
      }) files;
    in fileEntries;
  result = mkHomeFiles { 
    sourceDir = filesDir + "/bin"; 
    targetDir = "bin"; 
    executable = true; 
  };
in builtins.hasAttr "bin/.env" result
'

echo
echo "2. Check what our module config section produces:"
nix eval --impure --expr '
let 
  lib = import <nixpkgs/lib>;
  filesDir = ./home/files;
  mkHomeFiles = { sourceDir, targetDir, executable ? false }: 
    let
      dirContents = builtins.readDir sourceDir;
      files = lib.filterAttrs (name: type: type == "regular") dirContents;
      fileEntries = lib.mapAttrs'\'' (name: value: {
        name = "${targetDir}/${name}";
        value = {
          source = sourceDir + "/${name}";
          executable = executable;
        };
      }) files;
    in fileEntries;
  
  mkHomeDirectories = { sourceDir, targetDir }:
    {
      "${targetDir}" = {
        source = sourceDir;
        recursive = true;
      };
    };
    
  result = (mkHomeFiles {
    sourceDir = filesDir + "/bin";
    targetDir = "bin";
    executable = true;
  }) // (mkHomeDirectories {
    sourceDir = filesDir + "/claude";
    targetDir = "claude";
  });
in builtins.hasAttr "bin/.env" result
'

echo
echo "3. Check what the full home configuration has:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq 'has("bin/.env")'

echo
echo "4. Look for any .env anywhere in home.file:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | grep -i env || echo "No env files found"

echo
echo "5. Check for conflicts - are there other modules setting bin files?"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | grep "^bin/" | wc -l

