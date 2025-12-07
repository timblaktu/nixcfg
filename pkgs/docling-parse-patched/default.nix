{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ../patches/docling-parse-boolean-t-wrapper.patch
  ];

  # Add metadata about the fix
  meta = old.meta // {
    description = old.meta.description + " (patched for nlohmann_json bool conversion)";
    longDescription = ''
      ${old.meta.longDescription or ""}

      This package has been patched to fix a C++20 template resolution issue
      with nlohmann_json bool conversions. The patch uses nlohmann::json::boolean_t
      wrapper type to avoid SFINAE failures when converting bool values to JSON.

      Upstream issue: Template resolution fails with "'bool' is not a class, struct, or union type"
      Fix: Use nlohmann::json::boolean_t(val) instead of direct assignment
    '';
  };
})
