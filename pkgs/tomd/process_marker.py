#!/usr/bin/env python3
"""
Marker-based document processor for tomd.
Handles OCR and complex visual document processing.
"""

import sys
import os
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
import subprocess
import tempfile

# Check if marker is available
try:
    import marker
    HAS_MARKER = True
except ImportError:
    HAS_MARKER = False
    print("Warning: marker-pdf not available, OCR features will be limited", file=sys.stderr)


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Process documents with Marker (OCR)")
    parser.add_argument("input_file", help="Input document path")
    parser.add_argument("output_file", help="Output markdown file path")
    parser.add_argument("--chunk-size", type=int, default=100,
                        help="Maximum pages per chunk")
    parser.add_argument("--batch-multiplier", type=float, default=0.5,
                        help="GPU batch size multiplier")
    parser.add_argument("--verbose", type=lambda x: x.lower() == 'true',
                        default=False, help="Verbose output")
    return parser.parse_args()


def check_ocr_needed(doc_path: Path) -> bool:
    """
    Check if OCR is needed for the document.
    This is a simplified check - in production would be more sophisticated.
    """
    # For now, always return True for PDFs
    # In a real implementation, we'd check if the PDF has text layers
    return doc_path.suffix.lower() == '.pdf'


def process_with_marker(doc_path: Path, output_path: Path,
                       batch_multiplier: float = 0.5,
                       verbose: bool = False) -> bool:
    """
    Process document using marker-pdf for OCR.
    """
    try:
        if verbose:
            print(f"Processing {doc_path} with Marker (OCR)...")

        # Set environment variables for marker
        env = os.environ.copy()
        env['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'
        env['BATCH_MULTIPLIER'] = str(batch_multiplier)

        # Create temporary output directory
        with tempfile.TemporaryDirectory() as temp_dir:
            # Run marker_single command
            # Note: This assumes marker_single is available in PATH
            # In real implementation, we'd package marker-pdf properly
            cmd = [
                'marker_single',
                str(doc_path),
                str(temp_dir),
                '--batch_multiplier', str(batch_multiplier)
            ]

            if verbose:
                print(f"Running command: {' '.join(cmd)}")

            result = subprocess.run(
                cmd,
                env=env,
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                print(f"Marker processing failed: {result.stderr}", file=sys.stderr)
                return False

            # Find the output markdown file
            output_files = list(Path(temp_dir).glob('*.md'))
            if not output_files:
                print("Error: No markdown output from marker", file=sys.stderr)
                return False

            # Copy to final location
            output_path.parent.mkdir(parents=True, exist_ok=True)
            content = output_files[0].read_text(encoding='utf-8')
            output_path.write_text(content, encoding='utf-8')

            if verbose:
                print(f"Successfully wrote markdown to {output_path}")

            return True

    except subprocess.CalledProcessError as e:
        print(f"Error running marker: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error processing document: {e}", file=sys.stderr)
        return False


def process_in_chunks(doc_path: Path, output_path: Path,
                     chunk_size: int, batch_multiplier: float,
                     verbose: bool = False) -> bool:
    """
    Process document in chunks to manage memory usage.
    """
    # For now, this is a placeholder
    # In real implementation, would split PDF and process chunks
    return process_with_marker(doc_path, output_path, batch_multiplier, verbose)


def main():
    """Main processing function."""
    args = parse_arguments()

    input_path = Path(args.input_file)
    output_path = Path(args.output_file)

    if not input_path.exists():
        print(f"Error: Input file does not exist: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Check if marker is available
    if not HAS_MARKER:
        # Try to process anyway using subprocess
        if args.verbose:
            print("Marker module not available, trying subprocess...")

    # Check if OCR is needed
    needs_ocr = check_ocr_needed(input_path)
    if args.verbose:
        print(f"OCR needed: {needs_ocr}")

    # Process the document
    success = process_with_marker(
        input_path,
        output_path,
        args.batch_multiplier,
        args.verbose
    )

    if success:
        print(f"Successfully converted to: {output_path}")
        sys.exit(0)
    else:
        print("Conversion failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()