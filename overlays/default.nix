# Overlays for the Nix configuration
{ inputs }:
_final: prev:
let
  customPkgs = import ../pkgs { pkgs = prev; };

  # Import nixpkgs-docling ONLY for docling-parse fix (isolated)
  # This ensures only docling packages use the custom fork
  pkgsDocling = import inputs.nixpkgs-docling {
    inherit (prev) system;
    config.allowUnfree = true;
  };

  # Pinned nixpkgs for newer package versions not yet in our flake's nixpkgs
  # claude-code 2.1.97 (2026-04-10)
  pkgsClaudeCode = import
    (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/a5673e674446d540fab626b2692e8be09365f776.tar.gz";
      sha256 = "0i34kiq1nk93wyfsy7nx6f5l65nnw0qira1s3nr43mim02pavgg2";
    })
    {
      inherit (prev) system;
      config.allowUnfree = true;
    };

  # opencode 1.4.3 (2026-04-10)
  pkgsOpenCode = import
    (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/ca4120ec8edf1085d0c7f6c5b3ea37bf546333ec.tar.gz";
      sha256 = "18326vfr7g24jyvvs4qw92mb2ql3pz3gprbspbkvl63n1sbb1bh9";
    })
    {
      inherit (prev) system;
      config.allowUnfree = true;
    };
in
{
  # Custom packages and overrides go here
  inherit (customPkgs) markitdown;
  inherit (customPkgs) marker-pdf;
  inherit (customPkgs) confluence-markdown-exporter;

  # ISOLATED: docling from custom nixpkgs (temporary until PR #184 merges)
  inherit (pkgsDocling) docling;

  # Pinned package upgrades (ahead of our nixpkgs input)
  inherit (pkgsClaudeCode) claude-code; # 2.1.97
  inherit (pkgsOpenCode) opencode; # 1.4.3

  # Fix watchfiles test failure that affects MCP servers
  # Fallback: Disable problematic tests while working on version update
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_python-final: python-prev: {
      watchfiles = python-prev.watchfiles.overridePythonAttrs (_old: {
        # Disable tests completely - environment-specific expectations
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    })
  ];

  # Also override specific Python package sets directly
  python311Packages = prev.python311Packages.override {
    overrides = _self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (_old: {
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    };
  };

  python312Packages = prev.python312Packages.override {
    overrides = _self: super: {
      watchfiles = super.watchfiles.overridePythonAttrs (_old: {
        doCheck = false;
        pytestFlagsArray = [ ];
      });
    };
  };
}
