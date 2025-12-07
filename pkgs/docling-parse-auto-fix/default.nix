{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  # Fix for nlohmann_json 3.12 bool conversion issues
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "=== Applying nlohmann_json 3.12 compatibility fixes ==="

    # Fix the specific bool conversion issues in to_json.h
    echo "Fixing src/v2/qpdf/to_json.h..."
    if [ -f "src/v2/qpdf/to_json.h" ]; then
      # Line 165: Fix bool assignment
      # Change: result = val;
      # To: { nlohmann::json tmp; tmp = val; result = tmp; }
      sed -i '165s/result = val;/{ nlohmann::json tmp; tmp = val; result = tmp; }/' src/v2/qpdf/to_json.h

      echo "  Applied bool assignment fix at line 165"
    fi

    # Fix the specific bool push_back issues in page_cell.h
    echo "Fixing src/v2/pdf_resources/page_cell.h..."
    if [ -f "src/v2/pdf_resources/page_cell.h" ]; then
      # Line 188: Fix widget push_back (bool)
      sed -i '188s/cell.push_back(widget);/{ nlohmann::json tmp; tmp = widget; cell.push_back(tmp); }/' src/v2/pdf_resources/page_cell.h

      # Line 189: Fix left_to_right push_back (bool)
      sed -i '189s/cell.push_back(left_to_right);/{ nlohmann::json tmp; tmp = left_to_right; cell.push_back(tmp); }/' src/v2/pdf_resources/page_cell.h

      echo "  Applied bool push_back fixes at lines 188-189"
    fi

    # Verify the changes were applied
    echo "Verifying changes..."
    if grep -q "nlohmann::json tmp" src/v2/qpdf/to_json.h 2>/dev/null; then
      echo "  ✓ to_json.h fix applied successfully"
    else
      echo "  ⚠ Warning: to_json.h fix may not have been applied"
    fi

    if grep -q "nlohmann::json tmp.*widget" src/v2/pdf_resources/page_cell.h 2>/dev/null; then
      echo "  ✓ page_cell.h fixes applied successfully"
    else
      echo "  ⚠ Warning: page_cell.h fixes may not have been applied"
    fi

    echo "=== nlohmann_json compatibility fixes complete ==="
  '';
})
