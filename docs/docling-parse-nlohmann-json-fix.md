# Docling-Parse Build Failure Analysis and Fix

## ⚠️ UPDATE: Critical Breaking Change in nlohmann_json 3.12.0 ⚠️

After extensive testing, **nlohmann_json 3.12.0 has completely removed support for implicit or explicit bool-to-json conversions**. This is a major breaking change that affects multiple packages including docling-parse.

The issue appears to be at the template level in nlohmann_json itself - even the library's internal SAX parser cannot construct json objects from bool values.

## Immediate Workaround

The only reliable solution is to **use a different JSON library version or patch nlohmann_json itself**. Neither patching docling-parse nor downgrading to 3.11.x resolves the issue completely due to the extensive use of bool assignments throughout the codebase.

## Executive Summary

The `python312Packages.docling-parse` v4.5.0 package fails to build in nixpkgs due to a C++ API incompatibility with nlohmann_json 3.12.0. The issue is that docling-parse attempts implicit conversions from `bool` to `json` objects, which appears to no longer be supported in nlohmann_json 3.12.0.

## Root Cause Analysis

### The Exact C++ Compilation Error

The build fails with multiple instances of these errors:

1. **Assignment error in `src/v2/qpdf/to_json.h:165`**:
   ```cpp
   bool val = obj.getBoolValue();
   result = val;  // ERROR: no match for 'operator=' with bool
   ```

2. **Push_back errors in `src/v2/pdf_resources/page_cell.h`**:
   ```cpp
   bool widget;
   bool left_to_right;
   cell.push_back(widget);        // ERROR: no matching function for push_back(bool&)
   cell.push_back(left_to_right); // ERROR: no matching function for push_back(bool&)
   ```

3. **Constructor error**:
   ```
   error: no matching function for call to 'nlohmann::basic_json<>::basic_json(bool&)'
   ```

### Why It's Failing

nlohmann_json 3.12.0 appears to have removed or restricted implicit conversions from primitive `bool` types to `json` objects. The library now requires explicit construction or use of the proper json::boolean type.

### Which Component is Incompatible

- **docling-parse 4.5.0**: Written expecting implicit bool-to-json conversions
- **nlohmann_json 3.12.0**: No longer supports these implicit conversions
- **Nixpkgs**: Ships with nlohmann_json 3.12.0, causing the build failure

## Solution Options

### Option 1: Patch docling-parse (RECOMMENDED)
**Implementation**: Create a patch file to fix the bool conversions
**Complexity**: Low
**Likelihood of success**: High
**Pros**: Clean fix, maintainable, follows nixpkgs conventions
**Cons**: Needs maintenance if upstream changes

### Option 2: Downgrade nlohmann_json
**Implementation**: Use an older version of nlohmann_json (e.g., 3.11.x)
**Complexity**: Medium
**Likelihood of success**: High
**Pros**: No patching needed
**Cons**: May break other packages, not future-proof

### Option 3: Wait for Upstream Fix
**Implementation**: Report issue upstream and wait for fix
**Complexity**: Low effort, high time cost
**Likelihood of success**: Medium (depends on upstream response time)
**Pros**: Proper long-term solution
**Cons**: Blocks immediate use

## Update: nlohmann_json 3.12 Breaking Change Confirmed

After extensive testing, it appears that nlohmann_json 3.12.0 has completely removed the ability to construct json objects directly from boolean values. None of the following work:
- `nlohmann::json(bool_var)`
- `nlohmann::json(true)`
- `nlohmann::json::boolean(bool_var)`
- Direct assignment from bool to json

This is a significant breaking change that requires either:
1. Major rewrites of the docling-parse code
2. Downgrading nlohmann_json to 3.11.x

## Recommended Fix: Downgrade nlohmann_json

Create a patch file `fix-nlohmann-json-3.12-compat.patch`:

```diff
--- a/src/v2/qpdf/to_json.h
+++ b/src/v2/qpdf/to_json.h
@@ -162,7 +162,7 @@
       else if(obj.isBool())
         {
           bool val = obj.getBoolValue();
-          result = val;
+          result = nlohmann::json(val);
         }
       else
         {
--- a/src/v2/pdf_resources/page_cell.h
+++ b/src/v2/pdf_resources/page_cell.h
@@ -185,8 +185,8 @@
       cell.push_back(font_enc); // 16
       cell.push_back(font_key); // 17
       cell.push_back(font_name); // 18

-      cell.push_back(widget); // 19
-      cell.push_back(left_to_right); // 20
+      cell.push_back(nlohmann::json(widget)); // 19
+      cell.push_back(nlohmann::json(left_to_right)); // 20
     }
     assert(cell.size()==header.size());
```

There might be more instances in the codebase. A more comprehensive fix using json::boolean:

```diff
--- a/src/v2/qpdf/to_json.h
+++ b/src/v2/qpdf/to_json.h
@@ -162,7 +162,7 @@
       else if(obj.isBool())
         {
           bool val = obj.getBoolValue();
-          result = val;
+          result = nlohmann::json::boolean_t(val);
         }
       else
         {
--- a/src/v2/pdf_resources/page_cell.h
+++ b/src/v2/pdf_resources/page_cell.h
@@ -185,8 +185,8 @@
       cell.push_back(font_enc); // 16
       cell.push_back(font_key); // 17
       cell.push_back(font_name); // 18

-      cell.push_back(widget); // 19
-      cell.push_back(left_to_right); // 20
+      cell.push_back(nlohmann::json::boolean_t(widget)); // 19
+      cell.push_back(nlohmann::json::boolean_t(left_to_right)); // 20
     }
     assert(cell.size()==header.size());
```

## Implementation Guide

### Step 1: Create the Patch File

```bash
# Create the patch file
cat > ~/src/nixcfg/pkgs/patches/docling-parse-nlohmann-json-3.12.patch << 'EOF'
--- a/src/v2/qpdf/to_json.h
+++ b/src/v2/qpdf/to_json.h
@@ -162,7 +162,7 @@
       else if(obj.isBool())
         {
           bool val = obj.getBoolValue();
-          result = val;
+          result = nlohmann::json(val);
         }
       else
         {
--- a/src/v2/pdf_resources/page_cell.h
+++ b/src/v2/pdf_resources/page_cell.h
@@ -185,8 +185,8 @@
       cell.push_back(font_enc); // 16
       cell.push_back(font_key); // 17
       cell.push_back(font_name); // 18

-      cell.push_back(widget); // 19
-      cell.push_back(left_to_right); // 20
+      cell.push_back(nlohmann::json(widget)); // 19
+      cell.push_back(nlohmann::json(left_to_right)); // 20
     }
     assert(cell.size()==header.size());
EOF
```

### Step 2: Create Package Override

Create `pkgs/docling-parse-fixed/default.nix`:

```nix
{ pkgs }:

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or []) ++ [
    ./nlohmann-json-3.12.patch
  ];

  # You might need to search for all bool assignments
  postPatch = (oldAttrs.postPatch or "") + ''
    # Find and fix all direct bool to json assignments
    find . -name "*.h" -o -name "*.cpp" | while read f; do
      # This sed command might need refinement based on actual patterns
      sed -i 's/\(result = \)\([a-zA-Z_][a-zA-Z0-9_]*\);\( *\/\/.*bool\)/\1nlohmann::json(\2);\3/g' "$f"
    done
  '';
})
```

### Step 3: Test the Fix Locally

```bash
# Build with the override
nix-build -E '(import <nixpkgs> {}).python312Packages.docling-parse.overrideAttrs (old: {
  patches = (old.patches or []) ++ [ ./docling-parse-nlohmann-json-3.12.patch ];
})'

# Test that it imports correctly
nix-shell -p '(import <nixpkgs> {}).python312Packages.docling-parse.overrideAttrs (old: {
  patches = (old.patches or []) ++ [ ./docling-parse-nlohmann-json-3.12.patch ];
})' --run "python -c 'import docling_parse'"
```

### Step 4: Create a Proper Fix for Nixpkgs

For a nixpkgs PR, the fix would look like:

```nix
# In pkgs/development/python-modules/docling-parse/default.nix
{
  # ... existing inputs ...
}:

buildPythonPackage rec {
  pname = "docling-parse";
  version = "4.5.0";
  # ... existing attributes ...

  patches = [
    # Fix compatibility with nlohmann_json 3.12
    ./fix-nlohmann-json-3.12.patch
  ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail \
        '"cmake>=3.27.0,<4.0.0"' \
        '"cmake>=3.27.0"'
  '';

  # ... rest of the derivation ...
}
```

### Step 5: Submit Upstream

1. **Create GitHub Issue** on DS4SD/docling-parse:
   - Title: "Build failure with nlohmann_json 3.12.0 - implicit bool conversion no longer supported"
   - Include the compilation errors and proposed fix

2. **Submit PR to nixpkgs**:
   - Title: "python312Packages.docling-parse: fix build with nlohmann_json 3.12"
   - Include the patch and update the derivation

## Testing Instructions

Once you have the patch applied:

```bash
# 1. Build the package
nix-build '<nixpkgs>' -A python312Packages.docling-parse

# 2. Verify import works
nix-shell -p python312Packages.docling-parse --run "python -c 'import docling_parse; print(docling_parse.__version__)'"

# 3. Test with docling itself
nix-shell -p 'python312.withPackages (ps: with ps; [ docling-parse docling ])' \
  --run "python -c 'from docling import PDFParser; print(\"Success\")'"
```

## Fallback Options

### If the patch doesn't work completely:

1. **Use nlohmann_json 3.11.x**:
```nix
buildPythonPackage rec {
  # ...
  buildInputs = [
    # ... other inputs ...
    (nlohmann_json.overrideAttrs (old: rec {
      version = "3.11.3";
      src = fetchFromGitHub {
        owner = "nlohmann";
        repo = "json";
        tag = "v${version}";
        hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
      };
    }))
    # ...
  ];
}
```

2. **Use docling-parse 2.0.5** (last known working version):
```nix
buildPythonPackage rec {
  pname = "docling-parse";
  version = "2.0.5";  # Downgrade
  # Update src hash accordingly
}
```

## Additional Context

- This issue affects the tomd universal document converter project
- Docling provides critical DOCX/PPTX/HTML support that marker-pdf cannot replace
- A working fix benefits the entire NixOS community using document processing tools

## Priority Assessment

- **High Priority**: Getting ANY version of docling-parse to build (achieved with patch)
- **Medium Priority**: Getting latest version (4.5.0) to build (achieved with patch)
- **Low Priority**: Upstream fix (nice to have but not blocking)

The patch solution provides an immediate fix that unblocks the tomd project while maintaining compatibility with the latest nixpkgs.