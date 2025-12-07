{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  postPatch = (oldAttrs.postPatch or "") + ''
    # Fix incorrect bool-to-json assignments
    echo "Fixing bool to JSON compatibility issues..."

    # Fix bool assignment in src/v2/qpdf/to_json.h
    # Change direct bool assignment to create json boolean object
    # First create a temp json with the bool value, then assign
    sed -i '165s|result = val;|{ nlohmann::json tmp; tmp = val; result = tmp; }|' src/v2/qpdf/to_json.h

    # Fix bool push_back in src/v2/pdf_resources/page_cell.h
    # Create temporary json objects initialized with the bool value
    sed -i '188s|cell.push_back(widget);|{ nlohmann::json tmp = widget; cell.push_back(tmp); }|' src/v2/pdf_resources/page_cell.h
    sed -i '189s|cell.push_back(left_to_right);|{ nlohmann::json tmp = left_to_right; cell.push_back(tmp); }|' src/v2/pdf_resources/page_cell.h

    # Verify changes were made
    echo "Verifying changes..."
    grep -n "nlohmann::json tmp" src/v2/qpdf/to_json.h || echo "Warning: to_json.h fix may have failed"
    grep -n "nlohmann::json tmp" src/v2/pdf_resources/page_cell.h || echo "Warning: page_cell.h fixes may have failed"
  '';
})
