#!/usr/bin/env python3
"""
Marker-based document processor for tomd.
Handles OCR and complex visual document processing.
Integrates with marker-pdf-env wrapper for memory management and chunking.
"""

import sys
import os
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
import subprocess
import tempfile
import shutil
import json
import re


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Process documents with Marker (OCR)")
    parser.add_argument("input_file", help="Input document path")
    parser.add_argument("output_file", help="Output markdown file path")
    parser.add_argument("--chunk-size", type=int, default=50,
                        help="Maximum pages per chunk (default: 50 for 8GB GPU)")
    parser.add_argument("--batch-multiplier", type=float, default=0.5,
                        help="GPU batch size multiplier (0.5 = less memory)")
    parser.add_argument("--memory-max", type=str, default="24G",
                        help="Maximum memory limit")
    parser.add_argument("--memory-high", type=str, default="20G",
                        help="High memory watermark")
    parser.add_argument("--auto-chunk", action='store_true',
                        help="Enable automatic chunking for large PDFs")
    parser.add_argument("--verbose", action='store_true',
                        help="Verbose output")
    return parser.parse_args()


def find_marker_pdf_env() -> Optional[str]:
    """Find marker-pdf-env command in PATH or common locations."""
    # Try to find marker-pdf-env in PATH
    result = shutil.which("marker-pdf-env")
    if result:
        return result

    # Try common Nix store locations
    try:
        # Look for marker-pdf-env in nix store
        result = subprocess.run(
            ["find", "/nix/store", "-maxdepth", "2", "-name", "marker-pdf-env", "-type", "f", "-executable"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            paths = result.stdout.strip().split('\n')
            # Return the most recent one
            return paths[0] if paths else None
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        pass

    return None


def check_ocr_needed(doc_path: Path) -> Tuple[bool, str]:
    """
    Check if OCR is needed for the document.
    Returns (needs_ocr, reason) tuple.
    """
    if doc_path.suffix.lower() not in ['.pdf']:
        return False, "Not a PDF file"

    # Check if PDF has text layers using qpdf or pdftotext
    try:
        # Try to extract text to see if PDF has text layer
        result = subprocess.run(
            ["pdftotext", "-l", "1", str(doc_path), "-"],
            capture_output=True, text=True, timeout=5
        )

        if result.returncode == 0:
            text = result.stdout.strip()
            if len(text) < 100:  # Very little text extracted
                return True, "PDF appears to be scanned or has minimal text"
            else:
                return False, "PDF has text layer"
        else:
            # If pdftotext fails, assume OCR is needed
            return True, "Unable to extract text, assuming scanned PDF"

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        # If we can't check, assume OCR might be needed
        return True, "Unable to determine if OCR needed, assuming yes"


def process_with_marker_pdf_env(doc_path: Path, output_path: Path,
                                batch_multiplier: float = 0.5,
                                chunk_size: int = 50,
                                memory_max: str = "24G",
                                memory_high: str = "20G",
                                auto_chunk: bool = False,
                                verbose: bool = False) -> bool:
    """
    Process document using marker-pdf-env wrapper for OCR.
    This uses the Nix-packaged marker-pdf with proper memory management.
    """
    try:
        # Find marker-pdf-env command
        marker_cmd = find_marker_pdf_env()
        if not marker_cmd:
            if verbose:
                print("Warning: marker-pdf-env not found in PATH", file=sys.stderr)
                print("Falling back to direct marker_single if available...", file=sys.stderr)
            marker_cmd = shutil.which("marker_single")
            if not marker_cmd:
                print("Error: Neither marker-pdf-env nor marker_single found", file=sys.stderr)
                return False

        if verbose:
            print(f"Processing {doc_path} with Marker (OCR)...")
            print(f"Using command: {marker_cmd}")
            print(f"Settings: batch_multiplier={batch_multiplier}, chunk_size={chunk_size}")
            if auto_chunk:
                print(f"Auto-chunking enabled with {chunk_size} pages per chunk")

        # Create temporary output directory
        with tempfile.TemporaryDirectory() as temp_dir:
            # Build command
            if "marker-pdf-env" in marker_cmd:
                # Use the wrapper with all its features
                cmd = [
                    marker_cmd,
                    'marker_single',
                    str(doc_path),
                    str(temp_dir),
                    '--batch-multiplier', str(batch_multiplier),
                    '--memory-max', memory_max,
                    '--memory-high', memory_high
                ]

                if auto_chunk:
                    cmd.extend(['--auto-chunk', '--chunk-size', str(chunk_size)])
            else:
                # Direct marker_single fallback
                cmd = [
                    marker_cmd,
                    str(doc_path),
                    '--output_dir', str(temp_dir),
                    '--batch_multiplier', str(batch_multiplier)
                ]

            if verbose:
                print(f"Running command: {' '.join(cmd)}")

            # Run the command with progress output if verbose
            if verbose:
                result = subprocess.run(cmd, text=True)
            else:
                result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                if not verbose:
                    print(f"Marker processing failed: {result.stderr}", file=sys.stderr)
                return False

            # Find the output markdown file
            output_files = list(Path(temp_dir).glob('*.md'))
            if not output_files:
                print("Error: No markdown output from marker", file=sys.stderr)
                return False

            # Copy to final location
            output_path.parent.mkdir(parents=True, exist_ok=True)

            # If multiple files (from chunking), concatenate them
            if len(output_files) > 1:
                if verbose:
                    print(f"Merging {len(output_files)} output files...")
                content = ""
                for md_file in sorted(output_files):
                    content += md_file.read_text(encoding='utf-8') + "\n\n"
            else:
                content = output_files[0].read_text(encoding='utf-8')

            output_path.write_text(content, encoding='utf-8')

            # Copy any images that were extracted
            image_files = list(Path(temp_dir).glob('*.png')) + \
                         list(Path(temp_dir).glob('*.jpg')) + \
                         list(Path(temp_dir).glob('*.jpeg'))

            if image_files and verbose:
                print(f"Found {len(image_files)} extracted images")
                for img in image_files:
                    dest = output_path.parent / img.name
                    shutil.copy2(img, dest)
                    if verbose:
                        print(f"  Copied {img.name} to output directory")

            if verbose:
                print(f"Successfully wrote markdown to {output_path}")

            return True

    except subprocess.CalledProcessError as e:
        print(f"Error running marker: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error processing document: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return False


def main():
    """Main processing function."""
    args = parse_arguments()

    input_path = Path(args.input_file)
    output_path = Path(args.output_file)

    if not input_path.exists():
        print(f"Error: Input file does not exist: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Check if OCR is needed
    needs_ocr, reason = check_ocr_needed(input_path)
    if args.verbose:
        print(f"OCR Analysis: {reason}")
        print(f"OCR needed: {needs_ocr}")

    # Check if we should use auto-chunking based on file size
    file_size_mb = input_path.stat().st_size / (1024 * 1024)
    if file_size_mb > 50 and not args.auto_chunk:
        if args.verbose:
            print(f"Note: Large file detected ({file_size_mb:.1f} MB). Consider using --auto-chunk")

    # Process the document
    success = process_with_marker_pdf_env(
        input_path,
        output_path,
        batch_multiplier=args.batch_multiplier,
        chunk_size=args.chunk_size,
        memory_max=args.memory_max,
        memory_high=args.memory_high,
        auto_chunk=args.auto_chunk,
        verbose=args.verbose
    )

    if success:
        print(f"Successfully converted to: {output_path}")
        sys.exit(0)
    else:
        print("Conversion failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()