{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  # Comprehensive fix for nlohmann_json bool conversion issues
  # Works with both 3.11.x and 3.12.x
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "=== Applying comprehensive nlohmann_json bool compatibility fixes ==="

    # The issue: nlohmann_json doesn't allow direct bool assignment or construction
    # Solution: Use the value_t::boolean type constructor

    # Fix 1: src/v2/qpdf/to_json.h line 165
    # Original: result = val; (where val is bool)
    # Fixed: result = nlohmann::json(nlohmann::json::value_t::boolean); result = val;
    echo "Fixing src/v2/qpdf/to_json.h..."
    if [ -f "src/v2/qpdf/to_json.h" ]; then
      # Create a json with boolean type, then set its value
      sed -i '165s|result = val;|result = nlohmann::json(val ? nlohmann::json::value_t::boolean : nlohmann::json::value_t::boolean); result.get<bool>() = val;|' src/v2/qpdf/to_json.h || \
      # Simpler approach: use ternary operator to create true/false json
      sed -i '165s|result = val;|result = val ? nlohmann::json(true) : nlohmann::json(false);|' src/v2/qpdf/to_json.h
    fi

    # Fix 2 & 3: src/v2/pdf_resources/page_cell.h lines 188-189
    echo "Fixing src/v2/pdf_resources/page_cell.h..."
    if [ -f "src/v2/pdf_resources/page_cell.h" ]; then
      # Line 188: widget (bool)
      sed -i '188s|cell.push_back(widget);|cell.push_back(widget ? nlohmann::json(true) : nlohmann::json(false));|' src/v2/pdf_resources/page_cell.h

      # Line 189: left_to_right (bool)
      sed -i '189s|cell.push_back(left_to_right);|cell.push_back(left_to_right ? nlohmann::json(true) : nlohmann::json(false));|' src/v2/pdf_resources/page_cell.h
    fi

    # Fix 4 & 5: src/v2/pdf_sanitators/cells.h lines 126-127
    echo "Fixing src/v2/pdf_sanitators/cells.h..."
    if [ -f "src/v2/pdf_sanitators/cells.h" ]; then
      # Line 126: widget assignment
      sed -i '126s|item\["widget"\] = cell.widget;|item["widget"] = cell.widget ? nlohmann::json(true) : nlohmann::json(false);|' src/v2/pdf_sanitators/cells.h

      # Line 127: left_to_right assignment
      sed -i '127s|item\["left_to_right"\] = cell.left_to_right;|item["left_to_right"] = cell.left_to_right ? nlohmann::json(true) : nlohmann::json(false);|' src/v2/pdf_sanitators/cells.h
    fi

    # Search for any other potential bool issues
    echo "Searching for additional bool conversion patterns..."
    find src -type f \( -name "*.h" -o -name "*.cpp" \) -exec grep -l "nlohmann::json.*bool\|json.*= .*bool" {} \; 2>/dev/null || true

    echo "=== nlohmann_json compatibility fixes complete ==="
  '';
})
