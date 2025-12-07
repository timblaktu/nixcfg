{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  # Final fix for nlohmann_json bool conversion issues
  # The only way that works: create json object then set boolean value
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "=== Applying final nlohmann_json bool compatibility fixes ==="

    # The fundamental issue: nlohmann_json doesn't allow ANY direct bool construction
    # The ONLY working solution: create default json, then set boolean value

    # Fix src/v2/qpdf/to_json.h line 165
    echo "Fixing src/v2/qpdf/to_json.h..."
    sed -i '165c\            result = nlohmann::json(); result = nlohmann::json::boolean_t(val);' src/v2/qpdf/to_json.h 2>/dev/null || \
    sed -i '165c\            { nlohmann::json tmp; tmp = nlohmann::json::boolean_t(val); result = tmp; }' src/v2/qpdf/to_json.h 2>/dev/null || \
    sed -i '165s|result = val;|result = nlohmann::json(); result.clear(); if(val) result = nlohmann::json::parse("true"); else result = nlohmann::json::parse("false");|' src/v2/qpdf/to_json.h

    # Fix src/v2/pdf_resources/page_cell.h lines 188-189
    echo "Fixing src/v2/pdf_resources/page_cell.h..."
    sed -i '188c\      { nlohmann::json tmp; if(widget) tmp = nlohmann::json::parse("true"); else tmp = nlohmann::json::parse("false"); cell.push_back(tmp); } // 19' src/v2/pdf_resources/page_cell.h
    sed -i '189c\      { nlohmann::json tmp; if(left_to_right) tmp = nlohmann::json::parse("true"); else tmp = nlohmann::json::parse("false"); cell.push_back(tmp); } // 20' src/v2/pdf_resources/page_cell.h

    # Fix src/v2/pdf_sanitators/cells.h lines 126-127
    echo "Fixing src/v2/pdf_sanitators/cells.h..."
    sed -i '126c\          { nlohmann::json tmp; if(cell.widget) tmp = nlohmann::json::parse("true"); else tmp = nlohmann::json::parse("false"); item["widget"] = tmp; }' src/v2/pdf_sanitators/cells.h
    sed -i '127c\          { nlohmann::json tmp; if(cell.left_to_right) tmp = nlohmann::json::parse("true"); else tmp = nlohmann::json::parse("false"); item["left_to_right"] = tmp; }' src/v2/pdf_sanitators/cells.h

    echo "=== Final nlohmann_json compatibility fixes complete ==="
  '';
})
