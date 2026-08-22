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
    overlays = [
      # WORKAROUND (2026-08-22, plan 054 P9): two upstream issues break build-docling
      # fresh, both in the fork's pinned nlohmann_json 3.10.5 - a transitive dep
      # (arrow-cpp -> onnxruntime -> docling-parse -> docling). Overriding the single
      # top-level nlohmann_json attribute propagates through the whole docling closure
      # (all three consume it via callPackage). Scoped to pkgsDocling only - no blast
      # radius on the main pkgs set.
      #
      #   (1) GitHub-tarball hash drift: GitHub's auto-generated /archive/v3.10.5.tar.gz
      #       is not byte-stable, so the fork's pinned FOD hash no longer matches what
      #       codeload serves (specified sha256-DTsZrdB9GcaNkx7ZKxcJwp3pCVXCDlnoRHwn6R6AJnI=
      #       vs got sha256-DTsZrdB9GcaNkx7ZKxcgCA3A9ShM5icSF0xyGguJNbk=). Fix = pin the
      #       src to the currently-served content hash.
      #   (2) CMake 4.x dropped compatibility for `cmake_minimum_required(VERSION < 3.5)`,
      #       which nlohmann_json 3.10.5's CMakeLists.txt still declares -> configurePhase
      #       aborts ("Compatibility with CMake < 3.5 has been removed"). Fix = pass
      #       -DCMAKE_POLICY_VERSION_MINIMUM=3.5 (CMake's own suggested escape hatch).
      #       Masked in CI because issue (1) failed at fetch, before configure ran.
      #   (3) nlohmann_json 3.10.5's own unit tests (unit-allocator.cpp) fail to compile
      #       under GCC 14's stricter libstdc++ allocator_traits static assertion. These
      #       are the library's tests, not needed for a header-only build dep of
      #       arrow-cpp/onnxruntime. Fix = doCheck=false (also flips the package's
      #       JSON_BuildTests to OFF so the broken tests never compile).
      #
      # Migration path: drop this overlay once the nixpkgs-docling fork (or its pinned
      # nixpkgs rev) ships a corrected nlohmann_json hash AND a version whose CMakeLists
      # requires CMake >= 3.5 AND whose test suite builds on the pinned GCC.
      (_finalDocling: prevDocling: {
        nlohmann_json = prevDocling.nlohmann_json.overrideAttrs (old: {
          src = prevDocling.fetchFromGitHub {
            owner = "nlohmann";
            repo = "json";
            rev = "v${old.version}";
            hash = "sha256-DTsZrdB9GcaNkx7ZKxcgCA3A9ShM5icSF0xyGguJNbk=";
          };
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
          doCheck = false;
        });
      })
    ];
  };

in
{
  # Custom packages and overrides go here
  inherit (customPkgs) markitdown;
  inherit (customPkgs) marker-pdf;
  inherit (customPkgs) confluence-markdown-exporter;

  # ISOLATED: docling from custom nixpkgs (temporary until PR #184 merges)
  inherit (pkgsDocling) docling;

  # claude-code 2.1.191 - pinned ahead of nixpkgs input (which has 2.1.158).
  # Plan 046: features needed for the CC-centric CCv2 workflow postdate 2.1.158 -
  # fallbackModel (2.1.166), Fable (2.1.170), availableModels/enforceAvailableModels
  # (2.1.172-175), reliability env (2.1.186). Vendored copy is byte-identical to the
  # nixpkgs derivation; only pkgs/claude-code-pinned/manifest.json moves the version.
  # Refresh: pkgs/claude-code-pinned/update.sh
  claude-code = prev.callPackage ../pkgs/claude-code-pinned/package.nix { };

  # opencode 1.14.48 - pinned ahead of nixpkgs input (which has 1.2.5)
  opencode = prev.callPackage ../pkgs/opencode-pinned/package.nix { };
  # glab: patch fixes index-out-of-range panic when navigating to/from
  # downstream pipelines in ci view (unfixed upstream through v1.93.0)
  # Upstream MR: https://gitlab.com/gitlab-org/cli/-/merge_requests/3179
  # TODO: upgrade to newer glab when nixpkgs-unstable input is updated (needs Go 1.26.1)
  glab = prev.glab.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./glab-ci-view-navigator-reset.patch
    ];
  });

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
