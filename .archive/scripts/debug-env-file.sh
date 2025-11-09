#!/usr/bin/env bash

# Debug .env file issue specifically
set -euo pipefail

cd /home/tim/src/nixcfg

echo "=== DEBUGGING .env FILE ISSUE ==="

echo
echo "1. Checking if .env file exists on filesystem:"
ls -la home/files/bin/.env

echo
echo "2. What readDir sees:"
nix eval --impure --expr 'builtins.readDir ./home/files/bin' --json | jq '.'

echo
echo "3. After filtering for regular files:"
nix eval --impure --expr 'let lib = import <nixpkgs/lib>; dirContents = builtins.readDir ./home/files/bin; files = lib.filterAttrs (name: type: type == "regular") dirContents; in files' --json | jq '.'

echo  
echo "4. Testing our mkHomeFiles function directly:"
nix eval --impure --expr '
let 
  lib = import <nixpkgs/lib>;
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
in mkHomeFiles { 
  sourceDir = ./home/files/bin; 
  targetDir = "bin"; 
  executable = true; 
}' --json | jq 'keys[]' | sort

echo
echo "5. What actual home.file contains for bin files:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq -r 'keys[]' | grep "^bin/" | sort

echo
echo "6. Checking if .env exists in actual home.file:"
nix eval .#homeConfigurations."tim@thinky-ubuntu".config.home.file --json | jq '.["bin/.env"]'
