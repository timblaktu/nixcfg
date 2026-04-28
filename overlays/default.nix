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

in
{
  # Custom packages and overrides go here
  inherit (customPkgs) markitdown;
  inherit (customPkgs) marker-pdf;
  inherit (customPkgs) confluence-markdown-exporter;

  # ISOLATED: docling from custom nixpkgs (temporary until PR #184 merges)
  inherit (pkgsDocling) docling;

  # Pinned package upgrades (ahead of our nixpkgs input)
  # claude-code 2.1.97 — overrideAttrs to avoid importing a separate nixpkgs
  claude-code =
    let
      cc-src = prev.fetchzip {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.97.tgz";
        hash = "sha256-J92ILqBJmXyAueUPZ+HYZY0ls3OfN2EAhFyQHTOQF5A=";
      };
      cc-postPatch = ''
        cp ${./claude-code-package-lock.json} package-lock.json
        substituteInPlace cli.js \
              --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
      '';
    in
    prev.claude-code.overrideAttrs (old: {
      version = "2.1.97";
      src = cc-src;
      postPatch = cc-postPatch;
      npmDepsHash = "sha256-0fZu5r/zQjUSbm49FhZSqiIyMKdmH050NSxoVWd3XoU=";
      npmDeps = prev.fetchNpmDeps {
        name = "claude-code-2.1.97-npm-deps";
        src = cc-src;
        postPatch = cc-postPatch;
        hash = "sha256-0fZu5r/zQjUSbm49FhZSqiIyMKdmH050NSxoVWd3XoU=";
      };
      postInstall = ''
        wrapProgram $out/bin/claude \
          --set DISABLE_AUTOUPDATER 1 \
          --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
          --set DISABLE_INSTALLATION_CHECKS 1 \
          --unset DEV \
          --prefix PATH : ${
            prev.lib.makeBinPath (
              [ prev.procps ]
              ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
                prev.bubblewrap
                prev.socat
              ]
            )
          }
      '';
      meta = old.meta // {
        sourceProvenance = with prev.lib.sourceTypes; [ binaryBytecode ];
      };
    });
  # opencode 1.4.3 — requires bun ≥1.3.11 for undici support
  opencode =
    let
      bun_1_3_11 = prev.bun.overrideAttrs (_old: {
        version = "1.3.11";
        src = prev.fetchurl {
          url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.11/bun-linux-x64.zip";
          hash = "sha256-hhG6k1r4hvBabzh0ChUWAybBXl1dB63vlmEwtEk2B+0=";
        };
      });
    in
    prev.callPackage ../pkgs/opencode-pinned/package.nix { bun = bun_1_3_11; };
  # glab: upgrade from nixpkgs-unstable (1.92.1, needs Go 1.26.1 unavailable in our nixpkgs)
  # Patch fixes index-out-of-range panic when navigating to/from downstream pipelines in ci view
  glab =
    let
      pkgsUnstable = import inputs.nixpkgs-unstable {
        inherit (prev) system;
        config.allowUnfree = true;
      };
    in
    pkgsUnstable.glab.overrideAttrs (old: {
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
