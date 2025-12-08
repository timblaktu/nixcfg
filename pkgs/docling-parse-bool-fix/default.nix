{ pkgs ? import <nixpkgs> { } }:

pkgs.python313Packages.docling-parse.overrideAttrs (oldAttrs: {
  # Fix nlohmann_json bool handling - direct assignment instead of parse
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "=== Applying nlohmann_json bool direct assignment fix ==="

    # Fix src/v2/qpdf/to_json.h line 167
    # Replace: result = nlohmann::json::parse(val ? "true" : "false");
    # With: result = nlohmann::json(val); // explicit constructor
    echo "Fixing src/v2/qpdf/to_json.h..."
    sed -i '167s|.*result = nlohmann::json::parse(val ? "true" : "false");|            result = nlohmann::json(val);|' src/v2/qpdf/to_json.h || true

    # Also check for the pattern at nearby lines (sometimes line numbers shift)
    sed -i 's|nlohmann::json::parse(val ? "true" : "false")|nlohmann::json(val)|g' src/v2/qpdf/to_json.h || true

    # Show what we changed
    echo "Changed lines in to_json.h:"
    grep -n "result = nlohmann::json" src/v2/qpdf/to_json.h || true

    echo "=== Bool direct assignment fix complete ==="
  '';
})
