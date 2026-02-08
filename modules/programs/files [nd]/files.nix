# modules/programs/files [nd]/files.nix
# Unified files management module [nd]
#
# Provides:
#   flake.modules.homeManager.files - Unified file management with autoWriter
#
# Features:
#   - Auto-generated bash/zsh completions for scripts
#   - Script symlinks to ~/bin/
#   - Claude prompts directory
#   - Bash library files for sourcing
#   - homeFiles module with autoWriter integration
#
# Usage in host config:
#   imports = [ inputs.self.modules.homeManager.files ];
#   homeFiles.enable = true;
#
# Note: This module has known anti-patterns documented in Plan 019 Future Work F5.
# The current structure is preserved for migration; refactoring deferred.
{ config, lib, ... }:
{
  flake.modules = {
    # === Home Manager Module ===
    homeManager.files = { config, pkgs, lib, ... }:
      {
        imports = [
          ./_completion-generator.nix
          ./_homefiles-module.nix
        ];
      };
  };
}
