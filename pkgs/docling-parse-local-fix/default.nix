{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  pname = "docling-parse-local-fix";
  version = "4.5.0-fixed";

  # Use our local git repository with the fixes applied
  src = /home/tim/src/docling-parse;

  # Ensure cmake and other build deps are available
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
    pkgs.cmake
    pkgs.pkg-config
    pkgs.python312Packages.cmake # Python cmake package required by pyproject.toml
    pkgs.python312Packages.scikit-build-core
    pkgs.python312Packages.setuptools
    pkgs.python312Packages.pybind11
    pkgs.python312Packages.wheel
  ];

  buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
    pkgs.nlohmann_json
  ];

  # No need for postPatch since we've fixed the source directly
  postPatch = "";

  meta = oldAttrs.meta // {
    description = oldAttrs.meta.description + " (with nlohmann_json 3.12 compatibility fixes from local source)";
  };
})
