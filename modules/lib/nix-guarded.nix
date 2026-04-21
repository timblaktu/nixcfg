# modules/lib/nix-guarded.nix
# Provides a nix wrapper package that applies systemd cgroup memory limits.
# Used by claude-code and opencode wrapper scripts to prevent OOM from
# runaway nix evaluations in multi-agent sessions.
#
# Each invocation runs in a systemd --user --scope under nix-eval.slice
# with percentage-based MemoryHigh/MemoryMax limits. No fds, no locks.
#
# Per-scope defaults (overridable via NIX_GUARD_MEM_HIGH / NIX_GUARD_MEM_MAX):
#   MemoryHigh=65% — soft limit; kernel throttles above this (swap pressure)
#   MemoryMax=75% — hard limit; kernel OOM-kills at this ceiling
#
# The aggregate nix-eval.slice (MemoryHigh=80%, MemoryMax=90%) is deployed
# separately via home-manager in modules/programs/claude-code/claude-code.nix.
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
  runtimeInputs = [ pkgs.systemd ]; # provides systemd-run
  text = script;
}
