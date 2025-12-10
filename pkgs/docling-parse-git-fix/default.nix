{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  pname = "docling-parse-git-fix";
  version = "4.5.0-git";

  # Use our local git repository with the fixes
  src = pkgs.fetchgit {
    url = "/home/tim/src/docling-parse";
    rev = "4d6fb6c1f1797502b95c9bfc966b4e43b02e8c08"; # The commit we just made
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Nix will tell us the correct hash
  };

  # No need for postPatch since we've fixed the source directly
  postPatch = "";

  meta = oldAttrs.meta // {
    description = oldAttrs.meta.description + " (with nlohmann_json 3.12 compatibility fixes)";
  };
})
