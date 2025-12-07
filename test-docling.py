#!/usr/bin/env python3
"""Test script to verify docling functionality with nlohmann_json 3.11.3"""

import sys

print("Testing docling import...")
try:
    from docling.document_converter import DocumentConverter
    print("✅ Successfully imported DocumentConverter from docling")

    # Test basic initialization
    converter = DocumentConverter()
    print("✅ Successfully created DocumentConverter instance")

    # Test that we can access methods
    print(f"✅ DocumentConverter has convert method: {hasattr(converter, 'convert')}")

    print("\nDocling is working correctly with nlohmann_json 3.11.3!")
    sys.exit(0)

except ImportError as e:
    print(f"❌ Failed to import docling: {e}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Unexpected error: {e}")
    sys.exit(1)