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
      # docling-parse -> docling) - is broken on the current toolchain. THREE facets are
      # fixed below; a FOURTH is an unresolved upstream compat blocker (docling deferred).
      #
      # FIXED here (lets the entire C++ closure - nlohmann + arrow-cpp + onnxruntime +
      # google-cloud-cpp - build; all CI-proven, run 32618353622):
      #   (1) GitHub-tarball hash drift: GitHub's auto-generated /archive/v3.10.5.tar.gz
      #       is not byte-stable, so the fork's pinned FOD hash no longer matches what
      #       codeload serves (specified sha256-DTsZrdB9GcaNkx7ZKxcJwp3pCVXCDlnoRHwn6R6AJnI=
      #       vs got sha256-DTsZrdB9GcaNkx7ZKxcgCA3A9ShM5icSF0xyGguJNbk=). Fix = pin src to
      #       the served content hash. (fetchFromGitHub hashes the unpacked tree, so it is
      #       drift-immune going forward.)
      #   (2) CMake 4.x dropped `cmake_minimum_required(VERSION < 3.5)` compat, which
      #       3.10.5's CMakeLists declares -> configure aborts. Fix =
      #       -DCMAKE_POLICY_VERSION_MINIMUM=3.5 (CMake's own escape hatch).
      #   (3) 3.10.5's own unit tests (unit-allocator.cpp) fail to compile under GCC 14
      #       (allocator_traits static assert). Header-only dep -> tests not needed.
      #       Fix = doCheck=false (also flips JSON_BuildTests OFF).
      #
      # UNRESOLVED facet (4) - docling itself does NOT build; DEFERRED as a separate,
      # non-gating backlog item (build-docling is nightly-only, never per-PR): docling-parse
      # 4.5.0's OWN C++ (parse_v1/v2.cpp, built via local_build.py -> cmake
      # -DUSE_SYSTEM_DEPS=1) does not compile against nlohmann under GCC 14 with EITHER
      # candidate version:
      #     - 3.10.5 -> "json.hpp:3658: call of overloaded 'input_adapter(const char*)'
      #       is ambiguous" (GCC13/14 strictness; fixed upstream in nlohmann 3.11.0).
      #     - 3.11.3 -> "json_sax.hpp:313: no matching function for
      #       basic_json(bool&)" + enable_if<false> SFINAE failures (docling-parse's usage
      #       is tied to the pre-3.11 API). Proven by CI run 32628030378.
      # So a version bump cannot satisfy both the compiler and docling-parse's API
      # expectations. The real fix (separate focused task, NOT trial-and-error CI builds):
      # either backport ONLY the upstream 3.11.0 input_adapter disambiguation into 3.10.5's
      # json.hpp (keep docling-parse's expected API, satisfy GCC14), OR build docling-parse
      # with gcc13Stdenv (watch onnxruntime ABI), OR track docling nixpkgs PR #184. Until
      # then we keep 3.10.5 (the version the fork deliberately pinned for docling-parse).
      #
      # Migration path: drop this overlay once the fork/PR-#184 ships an nlohmann + docling-parse
      # combination that compiles on the pinned CMake+GCC.
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
