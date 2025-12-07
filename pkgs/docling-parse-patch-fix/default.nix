{ pkgs ? import <nixpkgs> { } }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  pname = "docling-parse-patch-fix";
  version = "4.5.0-patched";

  # Apply our comprehensive bool conversion fixes via postPatch
  postPatch = (oldAttrs.postPatch or "") + ''
        echo "=== Applying comprehensive nlohmann_json bool compatibility fixes ==="

        # Fix src/v2/qpdf/to_json.h line 165
        echo "Fixing src/v2/qpdf/to_json.h..."
        sed -i '162,166c\
            else if(obj.isBool())\
              {\
                bool val = obj.getBoolValue();\
                // Fix for nlohmann_json 3.12: use parse to convert bool\
                nlohmann::json tmp;\
                if (val)\
                  tmp = nlohmann::json::parse("true");\
                else\
                  tmp = nlohmann::json::parse("false");\
                result = tmp;\
              }' src/v2/qpdf/to_json.h

        # Fix src/v2/pdf_resources/page_cell.h lines 188-189
        echo "Fixing src/v2/pdf_resources/page_cell.h..."
        sed -i '188,189c\
          // Fix for nlohmann_json 3.12: use parse to convert bool\
          {\
            nlohmann::json tmp;\
            if (widget)\
              tmp = nlohmann::json::parse("true");\
            else\
              tmp = nlohmann::json::parse("false");\
            cell.push_back(tmp); // 19\
          }\
          {\
            nlohmann::json tmp;\
            if (left_to_right)\
              tmp = nlohmann::json::parse("true");\
            else\
              tmp = nlohmann::json::parse("false");\
            cell.push_back(tmp); // 20\
          }' src/v2/pdf_resources/page_cell.h

        # Fix src/v2/pdf_sanitators/cells.h lines 126-127
        echo "Fixing src/v2/pdf_sanitators/cells.h..."
        sed -i '126,127c\
    	  // Fix for nlohmann_json 3.12: use parse to convert bool\
    	  {\
    	    nlohmann::json tmp;\
    	    if (cell.widget)\
    	      tmp = nlohmann::json::parse("true");\
    	    else\
    	      tmp = nlohmann::json::parse("false");\
    	    item["widget"] = tmp;\
    	  }\
    	  {\
    	    nlohmann::json tmp;\
    	    if (cell.left_to_right)\
    	      tmp = nlohmann::json::parse("true");\
    	    else\
    	      tmp = nlohmann::json::parse("false");\
    	    item["left_to_right"] = tmp;\
    	  }' src/v2/pdf_sanitators/cells.h

        echo "=== Comprehensive nlohmann_json compatibility fixes applied ==="
  '';

  meta = oldAttrs.meta // {
    description = oldAttrs.meta.description + " (with comprehensive nlohmann_json 3.12 compatibility fixes)";
  };
})
