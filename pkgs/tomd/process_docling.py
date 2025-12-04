#!/usr/bin/env python3
"""
Docling-based document processor for tomd.
Handles document structure analysis and conversion to markdown.
"""

import sys
import os
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
import json

try:
    from docling.document_converter import DocumentConverter
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PipelineOptions
    HAS_DOCLING = True
except ImportError:
    HAS_DOCLING = False
    # Silently handle missing docling for now

# Use PyMuPDF as fallback
try:
    import pymupdf
    HAS_PYMUPDF = True
except ImportError:
    HAS_PYMUPDF = False


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Process documents with Docling")
    parser.add_argument("input_file", help="Input document path")
    parser.add_argument("output_file", help="Output markdown file path")
    parser.add_argument("--chunk-size", type=int, default=100,
                        help="Maximum pages per chunk")
    parser.add_argument("--smart-chunks", type=lambda x: x.lower() == 'true',
                        default=True, help="Use smart chunking based on structure")
    parser.add_argument("--no-chunks", type=lambda x: x.lower() == 'true',
                        default=False, help="Process without chunking")
    parser.add_argument("--verbose", type=lambda x: x.lower() == 'true',
                        default=False, help="Verbose output")
    return parser.parse_args()


def analyze_document_structure(doc_path: Path) -> Dict[str, Any]:
    """
    Analyze document structure using Docling.
    Returns metadata and structure information.
    """
    if not HAS_DOCLING:
        return {
            "format": "unknown",
            "pages": 1,
            "has_toc": False,
            "needs_ocr": False,
            "structure": []
        }

    try:
        # Configure Docling pipeline
        pipeline_options = PipelineOptions(
            do_ocr=False,  # Quick analysis first
            do_table_structure=True,
            include_images=False
        )

        # Create converter
        converter = DocumentConverter(
            pipeline_options=pipeline_options
        )

        # Convert document
        result = converter.convert(str(doc_path))

        # Extract structure information
        structure = {
            "format": result.input.format.value if hasattr(result.input, 'format') else "unknown",
            "pages": len(result.pages) if hasattr(result, 'pages') else 1,
            "has_toc": bool(result.document.toc) if hasattr(result.document, 'toc') else False,
            "needs_ocr": False,  # Will be determined by content analysis
            "structure": []
        }

        # Extract section boundaries
        if hasattr(result.document, 'sections'):
            for section in result.document.sections:
                structure["structure"].append({
                    "type": "section",
                    "title": section.title,
                    "level": section.level,
                    "page": section.page_number if hasattr(section, 'page_number') else None
                })

        return structure

    except Exception as e:
        print(f"Warning: Structure analysis failed: {e}", file=sys.stderr)
        return {
            "format": "unknown",
            "pages": 1,
            "has_toc": False,
            "needs_ocr": False,
            "structure": []
        }


def create_smart_chunks(doc_path: Path, structure: Dict[str, Any],
                       max_chunk_size: int) -> List[Dict[str, Any]]:
    """
    Create chunks based on document structure.
    Falls back to page-based chunking if no structure available.
    """
    chunks = []

    # If we have structure information, use it
    if structure.get("structure") and structure.get("has_toc"):
        current_chunk = {"start": 1, "end": 1, "title": "Introduction"}

        for element in structure["structure"]:
            if element.get("type") == "section" and element.get("page"):
                # Check if we need to start a new chunk
                chunk_size = element["page"] - current_chunk["start"]
                if chunk_size >= max_chunk_size:
                    current_chunk["end"] = element["page"] - 1
                    chunks.append(current_chunk)
                    current_chunk = {
                        "start": element["page"],
                        "end": element["page"],
                        "title": element.get("title", f"Section {len(chunks) + 1}")
                    }

        # Add the last chunk
        if current_chunk["start"] <= structure.get("pages", 1):
            current_chunk["end"] = structure.get("pages", 1)
            chunks.append(current_chunk)

    # Fall back to page-based chunking
    if not chunks:
        total_pages = structure.get("pages", 1)
        for i in range(0, total_pages, max_chunk_size):
            chunks.append({
                "start": i + 1,
                "end": min(i + max_chunk_size, total_pages),
                "title": f"Pages {i + 1}-{min(i + max_chunk_size, total_pages)}"
            })

    return chunks


def process_with_pymupdf_fallback(doc_path: Path, output_path: Path,
                                 verbose: bool = False) -> bool:
    """
    Process document using PyMuPDF as a fallback when Docling is not available.
    """
    if not HAS_PYMUPDF:
        print("Error: Neither Docling nor PyMuPDF is available", file=sys.stderr)
        return False

    try:
        if verbose:
            print(f"Processing {doc_path} with PyMuPDF (fallback)...")

        doc = pymupdf.open(str(doc_path))
        markdown_content = []

        for page_num, page in enumerate(doc, 1):
            if verbose:
                print(f"  Processing page {page_num}/{len(doc)}...")
            text = page.get_text()
            markdown_content.append(f"## Page {page_num}\n\n{text}\n")

        doc.close()

        # Write output
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text('\n'.join(markdown_content), encoding='utf-8')

        if verbose:
            print(f"Successfully wrote markdown to {output_path}")

        return True

    except Exception as e:
        print(f"Error processing document with PyMuPDF: {e}", file=sys.stderr)
        return False


def process_with_docling(doc_path: Path, output_path: Path,
                        verbose: bool = False) -> bool:
    """
    Process document using Docling and convert to markdown.
    """
    if not HAS_DOCLING:
        # Fall back to PyMuPDF
        if verbose:
            print("Docling not available, using PyMuPDF fallback...")
        return process_with_pymupdf_fallback(doc_path, output_path, verbose)

    try:
        if verbose:
            print(f"Processing {doc_path} with Docling...")

        # Configure pipeline for full processing
        pipeline_options = PipelineOptions(
            do_ocr=False,
            do_table_structure=True,
            include_images=True,
            generate_markdown=True
        )

        # Create converter
        converter = DocumentConverter(
            pipeline_options=pipeline_options
        )

        # Convert document
        if verbose:
            print("Converting document...")
        result = converter.convert(str(doc_path))

        # Export to markdown
        if verbose:
            print("Exporting to markdown...")
        markdown_content = result.document.export_to_markdown()

        # Write output
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(markdown_content, encoding='utf-8')

        if verbose:
            print(f"Successfully wrote markdown to {output_path}")

        return True

    except Exception as e:
        print(f"Error processing document: {e}", file=sys.stderr)
        return False


def process_chunk(doc_path: Path, output_path: Path, chunk: Dict[str, Any],
                 verbose: bool = False) -> bool:
    """
    Process a single chunk of the document.
    """
    # For now, we'll process the entire document
    # In a real implementation, we'd extract specific pages
    return process_with_docling(doc_path, output_path, verbose)


def main():
    """Main processing function."""
    args = parse_arguments()

    input_path = Path(args.input_file)
    output_path = Path(args.output_file)

    if not input_path.exists():
        print(f"Error: Input file does not exist: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Analyze document structure
    if args.verbose:
        print(f"Analyzing document structure...")
    structure = analyze_document_structure(input_path)

    if args.verbose:
        print(f"Document format: {structure['format']}")
        print(f"Pages: {structure['pages']}")
        print(f"Has TOC: {structure['has_toc']}")
        print(f"Structure elements: {len(structure['structure'])}")

    # Determine chunking strategy
    if args.no_chunks:
        # Process entire document at once
        if args.verbose:
            print("Processing entire document without chunking...")
        success = process_with_docling(input_path, output_path, args.verbose)

    elif args.smart_chunks and structure["pages"] > args.chunk_size:
        # Create smart chunks
        if args.verbose:
            print(f"Creating smart chunks (max size: {args.chunk_size} pages)...")
        chunks = create_smart_chunks(input_path, structure, args.chunk_size)

        if args.verbose:
            print(f"Created {len(chunks)} chunks")
            for i, chunk in enumerate(chunks, 1):
                print(f"  Chunk {i}: {chunk['title']} (pages {chunk['start']}-{chunk['end']})")

        # Process each chunk
        # For now, we'll just process the whole document
        # In a real implementation, we'd process each chunk separately
        success = process_with_docling(input_path, output_path, args.verbose)

    else:
        # Process as single file (document is small enough)
        if args.verbose:
            print("Document is small enough, processing as single file...")
        success = process_with_docling(input_path, output_path, args.verbose)

    if success:
        print(f"Successfully converted to: {output_path}")
        sys.exit(0)
    else:
        print("Conversion failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()