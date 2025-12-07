{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    ../patches/docling-parse-nlohmann-json-3.12-parse.patch
  ];

  # Optional: search for and fix any additional bool assignments we might have missed
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "Applied nlohmann_json 3.12 compatibility patch"

    # Find any other potential bool-to-json issues in the codebase
    echo "Searching for other potential bool conversion issues..."

    # Look for patterns like "json_var = bool_var;" or ".push_back(bool_var)"
    # This is informational only - the patch should handle known issues
    find src -type f \( -name "*.h" -o -name "*.cpp" \) -exec grep -l "push_back.*bool\|= .*bool" {} \; | while read file; do
      echo "  Potential bool issue in: $file"
    done || true
  '';
})
