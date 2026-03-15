# modules/flake-parts/version.nix
# Version management for nixcfg flake
#
# Reads VERSION file as the single source of truth, composes a full
# version string with git metadata, and provides a lint-version check.
#
# Why a VERSION file? Nix flake evaluation has no access to git tags
# (no self.tag, no git describe). The VERSION file bridges this gap —
# it's a tracked source file that participates in flake evaluation.
# See RELEASE.md for the full rationale.
{ self, lib, ... }:
let
  baseVersion = lib.trim (builtins.readFile "${self}/VERSION");
  version =
    if self ? rev then "${baseVersion}+${self.shortRev}"
    else "${baseVersion}-dirty";
in
{
  options.meta = {
    baseVersion = lib.mkOption {
      type = lib.types.str;
      default = baseVersion;
      readOnly = true;
      description = ''
        Base version from the VERSION file (e.g., "0.1.0").
        This is the human-meaningful release version without git metadata.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = version;
      readOnly = true;
      description = ''
        Full version string composed from VERSION file + git metadata.
        Clean builds: "0.1.0+a1b2c3d" (baseVersion + shortRev).
        Dirty builds: "0.1.0-dirty" (uncommitted changes).
      '';
    };
  };

  config = {
    perSystem = { pkgs, lib, ... }:
      let
        valid = builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)(-.+)?" baseVersion;
      in
      {
        checks = {
          lint-version =
            lib.seq
              (if valid == null then
                throw "VERSION '${baseVersion}' is not valid semver (expected N.N.N or N.N.N-suffix)"
              else
                true)
              (pkgs.runCommand "lint-version" { } ''
                echo "VERSION: ${baseVersion} (full: ${version})"
                touch $out
              '');
        };
      };
  };
}
