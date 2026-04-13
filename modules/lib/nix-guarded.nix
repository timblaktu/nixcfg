# modules/lib/nix-guarded.nix
# Provides a nix wrapper package that serializes nix evaluations via flock.
# Used by claude-code and opencode wrapper scripts to prevent OOM from
# concurrent nix evaluations in multi-agent sessions.
#
# Usage:
#   let nixGuarded = import ../lib/nix-guarded.nix { inherit pkgs; };
#   in
#   # Prepend to PATH: export PATH="${nixGuarded}/bin:$PATH"
#   # The package provides bin/nix that shadows the real nix binary.

{ pkgs }:

let
  nixReal = "${pkgs.nix}/bin/nix";
  scriptSrc = builtins.readFile ../../claude-runtime/bin/nix-guarded.sh;
  script = builtins.replaceStrings [ "@@NIX_REAL@@" ] [ nixReal ] scriptSrc;
in
pkgs.writeShellApplication {
  name = "nix";
  runtimeInputs = [ pkgs.util-linux ]; # provides flock
  text = script;
}
