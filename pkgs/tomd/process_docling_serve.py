#!/usr/bin/env python3
"""
Docling-based document processor for tomd using docling-serve.
This version uses docling-serve to avoid the docling-parse build issue.

NOTE: This processor requires docling-serve to be available.
If docling-serve is not available, use --engine=marker instead.
"""

import sys
import os
import argparse
import subprocess
import time
import json
import httpx
from pathlib import Path
from typing import List, Dict, Any, Optional


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Process documents with Docling-serve")
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


def start_docling_server(port: int = 5010, verbose: bool = False) -> subprocess.Popen:
    """
    Start docling-serve in the background.
    Returns the process handle.
    """
    if verbose:
        print(f"Starting docling-serve on port {port}...")

    # Start the server
    process = subprocess.Popen(
        ["docling-serve", "--port", str(port)],
        stdout=subprocess.PIPE if not verbose else None,
        stderr=subprocess.PIPE if not verbose else None
    )

    # Wait for server to be ready
    client = httpx.Client(base_url=f"http://localhost:{port}")
    max_retries = 30
    for i in range(max_retries):
        try:
            response = client.get("/health")
            if response.status_code == 200:
                if verbose:
                    print(f"Docling server ready after {i+1} attempts")
                break
        except (httpx.ConnectError, httpx.ReadError):
            time.sleep(1)
            if i == max_retries - 1:
                process.terminate()
                raise RuntimeError("Failed to start docling-serve")

    client.close()
    return process


def process_with_docling_serve(doc_path: Path, output_path: Path,
                               port: int = 5010, verbose: bool = False) -> bool:
    """
    Process document using docling-serve API.
    """
    try:
        # Create API client
        client = httpx.Client(base_url=f"http://localhost:{port}", timeout=300.0)

        if verbose:
            print(f"Processing {doc_path} with docling-serve...")

        # Upload and convert the document
        with open(doc_path, 'rb') as f:
            files = {'file': (doc_path.name, f, 'application/pdf')}

            # Request markdown output
            response = client.post(
                "/convert",
                files=files,
                data={
                    'output_format': 'markdown',
                    'include_images': 'false',
                    'include_tables': 'true',
                    'chunking': 'false'
                }
            )

        if response.status_code != 200:
            print(f"Error from docling-serve: {response.status_code}", file=sys.stderr)
            print(response.text, file=sys.stderr)
            return False

        # Get the markdown content
        result = response.json()

        # Extract markdown from response
        # The exact format depends on docling-serve's response structure
        if isinstance(result, dict):
            # Try common response patterns
            markdown_content = (
                result.get('markdown') or
                result.get('content') or
                result.get('text') or
                str(result)
            )
        else:
            markdown_content = str(result)

        # Write output
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(markdown_content, encoding='utf-8')

        if verbose:
            print(f"Successfully wrote markdown to {output_path}")

        client.close()
        return True

    except Exception as e:
        print(f"Error processing document with docling-serve: {e}", file=sys.stderr)
        return False




def main():
    """Main processing function."""
    args = parse_arguments()

    input_path = Path(args.input_file)
    output_path = Path(args.output_file)

    if not input_path.exists():
        print(f"Error: Input file does not exist: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Check if docling-serve is available
    result = subprocess.run(
        ["which", "docling-serve"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print("ERROR: docling-serve is not available.", file=sys.stderr)
        print("Docling is currently blocked by build issues in nixpkgs.", file=sys.stderr)
        print("Please use --engine=marker instead for document conversion.", file=sys.stderr)
        sys.exit(1)

    # Try to use docling-serve
    server_process = None
    success = False

    try:
        # Start docling server
        server_process = start_docling_server(verbose=args.verbose)

        # Process with docling-serve
        success = process_with_docling_serve(
            input_path, output_path,
            verbose=args.verbose
        )

    except Exception as e:
        print(f"Error with docling-serve: {e}", file=sys.stderr)
        success = False

    finally:
        # Clean up server process
        if server_process:
            server_process.terminate()
            server_process.wait(timeout=5)

    if success:
        print(f"Successfully converted to: {output_path}")
        sys.exit(0)
    else:
        print("Conversion failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()