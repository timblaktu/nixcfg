# Overlays for the Nix configuration
{ inputs }:
final: prev:
let
  customPkgs = import ../pkgs { pkgs = prev; };

  # Import nixpkgs-docling ONLY for docling-parse fix (isolated)
  # This ensures only docling packages use the custom fork
  pkgsDocling = import inputs.nixpkgs-docling {
    inherit (prev) system;
    config.allowUnfree = true;
  };
in
{
  # Custom packages and overrides go here
  markitdown = customPkgs.markitdown;
  marker-pdf = customPkgs.marker-pdf;

  # ISOLATED: docling from custom nixpkgs (temporary until PR #184 merges)
  docling = pkgsDocling.docling;

  # Fix watchfiles test failure that affects MCP servers
  # Fallback: Disable problematic tests while working on version update
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      watchfiles = python-prev.watchfiles.overridePythonAttrs (old: {
        # Disable tests completely - environment-specific expectations
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    })
  ];

  # Also override specific Python package sets directly
  python311Packages = prev.python311Packages.override {
    overrides = self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (old: {
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    };
  };

  python312Packages = prev.python312Packages.override {
    overrides = self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (old: {
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    };
  };
}
