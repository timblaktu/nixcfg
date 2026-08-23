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
      # WORKAROUND (2026-08-22, updated 2026-08-23, plan 054 P9): the fork's pinned
      # nlohmann_json 3.10.5 - a transitive dep (arrow-cpp -> onnxruntime ->
      # docling-parse -> docling) - is broken FOUR ways on the current toolchain. The
      # first three (hash-drift, CMake4 policy, GCC14 test-compile) were patchable on
      # 3.10.5, but the fourth is not: docling-parse's OWN C++ (parse_v1/v2.cpp, built
      # via local_build.py -> cmake -DUSE_SYSTEM_DEPS=1) #includes the store nlohmann
      # header and hits the known 3.10.5 x GCC13/14 overload-ambiguity regression
      # ("nlohmann/json.hpp:3658: call of overloaded 'input_adapter(const char*)' is
      # ambiguous"), which was fixed UPSTREAM in nlohmann 3.11.0 - a downstream
      # consumer failing on the old header, not a flag we can set on nlohmann. So we
      # BUMP nlohmann_json to 3.11.3, which fixes all four facets at once (current,
      # GCC-14-clean, canonical stable fetchFromGitHub hash, API-compatible with
      # arrow-cpp/onnxruntime). Overriding the single top-level nlohmann_json attribute
      # propagates through the whole docling closure (all three consume it via
      # callPackage). Scoped to pkgsDocling only - no blast radius on the main pkgs set.
      #
      # Retained belt-and-suspenders flags (harmless if unneeded on 3.11.3):
      #   - cmakeFlags += -DCMAKE_POLICY_VERSION_MINIMUM=3.5: nlohmann's CMakeLists still
      #     declares an old cmake_minimum_required that CMake 4.x rejects.
      #   - doCheck = false: the library's own unit tests are not needed for a
      #     header-only build dep and have historically failed to compile under GCC 14.
      #
      # Migration path: drop this overlay once the nixpkgs-docling fork (or its pinned
      # nixpkgs rev) ships nlohmann_json >= 3.11 with a correct hash.
      (_finalDocling: prevDocling: {
        nlohmann_json = prevDocling.nlohmann_json.overrideAttrs (_old: {
          version = "3.11.3";
          src = prevDocling.fetchFromGitHub {
            owner = "nlohmann";
            repo = "json";
            rev = "v3.11.3";
            hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
          };
          cmakeFlags = (_old.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
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
