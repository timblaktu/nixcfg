{ pkgs ? import <nixpkgs> { } }:

# Override docling-parse with patches for bool conversion issues
# The issue occurs with both nlohmann_json 3.11.3 and 3.12.x in C++20 environments
pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    ../patches/docling-parse-bool-conversion-explicit.patch
  ];

  # Optional: Add build diagnostics
  preConfigure = (oldAttrs.preConfigure or "") + ''
    echo "Applying bool conversion patches for nlohmann_json compatibility"
    echo "C++ compiler version:"
    $CXX --version || true
    echo "nlohmann_json version detected:"
    pkg-config --modversion nlohmann_json || echo "pkg-config not available"
  '';

  # Add metadata about the fix
  meta = (oldAttrs.meta or { }) // {
    description = (oldAttrs.meta.description or "docling-parse") + " (patched for bool conversion issues)";
    longDescription = ''
      This is a patched version of docling-parse that fixes bool conversion issues
      with nlohmann_json in C++20 environments.

      The patches ensure explicit json construction for bool values using ternary
      operators with literal true/false json objects to avoid template resolution
      failures that occur with both nlohmann_json 3.11.x and 3.12.x when using
      C++20 standard.

      The issue is that in C++20 mode, the implicit bool to json conversion fails,
      requiring explicit construction like: val ? nlohmann::json(true) : nlohmann::json(false)

      Upstream issue: https://github.com/DS4SD/docling-parse/issues/TBD
    '';
  };
})
