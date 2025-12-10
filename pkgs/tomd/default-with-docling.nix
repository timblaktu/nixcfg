{ lib
, stdenv
, python3
, writeShellScriptBin
, makeWrapper
, qpdf
, systemd
, jq
, gawk
, coreutils
, poppler-utils  # For pdftotext to check if OCR is needed
, marker-pdf ? null  # Optional: marker-pdf package for OCR
, gcc
}:

let
  # Python environment with basic packages
  pythonEnv = python3.withPackages (ps: with ps; [
    # Common dependencies
    pillow
    pip
    setuptools
    wheel

    # PDF processing
    pdfplumber
    pypdfium2

    # File type detection
    filetype

    # For API client if docling-serve is available
    httpx
  ]);

  # Docling venv setup script (similar to marker-pdf approach)
  doclingVenvSetup = writeShellScriptBin "docling-venv-setup" ''
    #!${stdenv.shell}
    set -euo pipefail

    VENV_DIR="$HOME/.cache/tomd/docling-venv"

    # Create venv if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
      echo "Creating Docling virtual environment at $VENV_DIR..."
      mkdir -p "$(dirname "$VENV_DIR")"
      ${pythonEnv}/bin/python -m venv "$VENV_DIR"

      # Activate venv
      source "$VENV_DIR/bin/activate"

      # Upgrade pip
      pip install --upgrade pip setuptools wheel

      # Install docling without the problematic docling-parse
      # We'll use a specific version that works
      echo "Installing Docling (this may take a few minutes)..."
      pip install "docling>=2.0.0,<3.0.0" --no-deps

      # Install core dependencies that don't require docling-parse
      pip install \
        "docling-core>=2.0.0" \
        "docling-ibm-models>=3.0.0" \
        "pdfplumber" \
        "pypdfium2" \
        "pillow" \
        "numpy" \
        "pandas" \
        "beautifulsoup4" \
        "lxml" \
        "python-magic" \
        "filetype" \
        "httpx" \
        "pydantic>=2.0.0" \
        "click"

      echo "Docling venv setup complete!"
    fi

    # Return venv path
    echo "$VENV_DIR"
  '';

  # Main tomd wrapper script with Docling support
  tomdScript = writeShellScriptBin "tomd" ''
    #!${stdenv.shell}
    set -euo pipefail

    # Constants
    DEFAULT_CHUNK_SIZE=100
    DEFAULT_MEMORY_MAX="24G"
    DEFAULT_MEMORY_HIGH="20G"
    DEFAULT_BATCH_MULTIPLIER="0.5"
    DEFAULT_ENGINE="auto"  # auto-detect best engine

    # Variables
    INPUT_FILE=""
    OUTPUT_FILE=""
    ENGINE="$DEFAULT_ENGINE"
    CHUNK_SIZE="$DEFAULT_CHUNK_SIZE"
    MEMORY_MAX="$DEFAULT_MEMORY_MAX"
    MEMORY_HIGH="$DEFAULT_MEMORY_HIGH"
    BATCH_MULTIPLIER="$DEFAULT_BATCH_MULTIPLIER"
    SMART_CHUNKS=true
    NO_CHUNKS=false
    VERBOSE=false
    HELP=false

    # Help text
    show_help() {
      cat << EOF
    tomd - Universal Document to Markdown Converter

    Usage: tomd <input> <output> [OPTIONS]

    Convert various document formats to markdown with intelligent processing.

    ARGUMENTS:
      input                Input document (PDF, DOCX, PPTX, HTML, images)
      output               Output markdown file or directory

    OPTIONS:
      --engine=ENGINE      Processing engine: auto (default), docling, marker
                          auto: Intelligently selects best engine
                          docling: Structure extraction (DOCX/PPTX/HTML/clean PDFs)
                          marker: ML-based OCR (scanned PDFs, complex visuals)
      --chunk-size=N       Maximum pages per chunk (default: $DEFAULT_CHUNK_SIZE)
      --smart-chunks       Use document structure for chunking (default)
      --no-chunks          Process as single file (may use lots of memory)
      --memory-max=SIZE    Maximum memory limit (default: $DEFAULT_MEMORY_MAX)
      --memory-high=SIZE   High memory watermark (default: $DEFAULT_MEMORY_HIGH)
      --batch-multiplier=N GPU batch size multiplier (default: $DEFAULT_BATCH_MULTIPLIER)
      --verbose            Show detailed processing information
      --help               Show this help message

    SUPPORTED FORMATS:
      • PDF - Both native and scanned (auto-detects OCR needs)
      • DOCX - Microsoft Word documents (via Docling)
      • PPTX - Microsoft PowerPoint presentations (via Docling)
      • HTML - Web pages (via Docling)
      • Images - PNG, JPG, TIFF (via marker-pdf OCR)

    EXAMPLES:
      # Auto-detect best engine (recommended)
      tomd document.pdf document.md

      # Force Docling for structure extraction
      tomd presentation.pptx slides.md --engine=docling

      # Force marker-pdf for OCR
      tomd scanned.pdf output.md --engine=marker

      # Control memory usage for large files
      tomd large.pdf output.md --memory-max=16G --chunk-size=50

      # Process without chunking (small files)
      tomd small.pdf output.md --no-chunks

    NOTES:
      • Auto mode intelligently selects between Docling and marker-pdf
      • Docling excels at: DOCX/PPTX, clean PDFs, table extraction
      • Marker excels at: OCR, scanned documents, complex visuals
      • Smart chunking respects document structure when possible
      • Memory limits are enforced via systemd-run or ulimit (WSL)
      • GPU acceleration is used when available for marker-pdf

    EOF
    }

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case $1 in
        --help)
          show_help
          exit 0
          ;;
        --engine=*)
          ENGINE="''${1#*=}"
          ;;
        --chunk-size=*)
          CHUNK_SIZE="''${1#*=}"
          ;;
        --smart-chunks)
          SMART_CHUNKS=true
          NO_CHUNKS=false
          ;;
        --no-chunks)
          NO_CHUNKS=true
          SMART_CHUNKS=false
          ;;
        --memory-max=*)
          MEMORY_MAX="''${1#*=}"
          ;;
        --memory-high=*)
          MEMORY_HIGH="''${1#*=}"
          ;;
        --batch-multiplier=*)
          BATCH_MULTIPLIER="''${1#*=}"
          ;;
        --verbose)
          VERBOSE=true
          ;;
        -*)
          echo "Unknown option: $1" >&2
          echo "Use --help for usage information" >&2
          exit 1
          ;;
        *)
          if [[ -z "$INPUT_FILE" ]]; then
            INPUT_FILE="$1"
          elif [[ -z "$OUTPUT_FILE" ]]; then
            OUTPUT_FILE="$1"
          else
            echo "Too many arguments" >&2
            echo "Use --help for usage information" >&2
            exit 1
          fi
          ;;
      esac
      shift
    done

    # Validate arguments
    if [[ -z "$INPUT_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
      echo "Error: Both input and output files are required" >&2
      echo "Use --help for usage information" >&2
      exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then
      echo "Error: Input file does not exist: $INPUT_FILE" >&2
      exit 1
    fi

    # Detect file type
    detect_format() {
      local file="$1"
      local extension="''${file##*.}"
      extension="''${extension,,}" # Convert to lowercase

      case "$extension" in
        pdf)
          echo "pdf"
          ;;
        docx|doc)
          echo "docx"
          ;;
        pptx|ppt)
          echo "pptx"
          ;;
        html|htm)
          echo "html"
          ;;
        png|jpg|jpeg|tiff|tif)
          echo "image"
          ;;
        *)
          # Try to detect by file content
          if file --mime-type "$file" | grep -q "application/pdf"; then
            echo "pdf"
          elif file --mime-type "$file" | grep -q "application/vnd.openxmlformats-officedocument.wordprocessingml"; then
            echo "docx"
          elif file --mime-type "$file" | grep -q "application/vnd.openxmlformats-officedocument.presentationml"; then
            echo "pptx"
          elif file --mime-type "$file" | grep -q "text/html"; then
            echo "html"
          elif file --mime-type "$file" | grep -q "image/"; then
            echo "image"
          else
            echo "unknown"
          fi
          ;;
      esac
    }

    # Check if PDF needs OCR
    needs_ocr() {
      local pdf_file="$1"

      # Try to extract text from first few pages
      local text_output=$(${poppler-utils}/bin/pdftotext -l 3 "$pdf_file" - 2>/dev/null | head -1000)

      # If very little text extracted, likely needs OCR
      if [[ -z "$text_output" ]] || [[ $(echo "$text_output" | wc -w) -lt 50 ]]; then
        return 0  # true - needs OCR
      else
        return 1  # false - has extractable text
      fi
    }

    # Determine processing engine
    determine_engine() {
      local file="$1"
      local format="$2"
      local engine="$3"

      # If engine is explicitly specified and not auto, use it
      if [[ "$engine" != "auto" ]]; then
        echo "$engine"
        return
      fi

      # Auto-detection logic
      case "$format" in
        docx|pptx|html)
          # These formats work best with Docling
          echo "docling"
          ;;
        image)
          # Images need OCR
          echo "marker"
          ;;
        pdf)
          # Check if PDF needs OCR
          if needs_ocr "$file"; then
            [[ "$VERBOSE" == "true" ]] && echo "PDF appears to be scanned, using marker for OCR" >&2
            echo "marker"
          else
            [[ "$VERBOSE" == "true" ]] && echo "PDF has extractable text, using docling for structure" >&2
            echo "docling"
          fi
          ;;
        *)
          # Default to docling for unknown formats
          echo "docling"
          ;;
      esac
    }

    # Check if running in WSL
    is_wsl() {
      if uname -r | grep -qi microsoft; then
        return 0
      else
        return 1
      fi
    }

    # Apply memory limits
    apply_memory_limit() {
      local cmd="$1"
      shift

      if is_wsl; then
        # WSL: Use ulimit for memory limiting
        local memory_limit_kb=$(( ''${MEMORY_MAX%G} * 1024 * 1024 ))
        [[ "$VERBOSE" == "true" ]] && echo "Using ulimit for WSL memory limiting: $MEMORY_MAX"
        (
          ulimit -v "$memory_limit_kb"
          $cmd "$@"
        )
      else
        # Native Linux: Use systemd-run
        [[ "$VERBOSE" == "true" ]] && echo "Using systemd-run for memory limiting: $MEMORY_MAX"
        systemd-run --user --scope \
          -p MemoryMax="$MEMORY_MAX" \
          -p MemoryHigh="$MEMORY_HIGH" \
          $cmd "$@"
      fi
    }

    # Setup Docling venv if needed
    setup_docling_venv() {
      if [[ ! -d "$HOME/.cache/tomd/docling-venv" ]]; then
        echo "First-time setup: Installing Docling (this may take a few minutes)..."
        ${doclingVenvSetup}/bin/docling-venv-setup
      fi
      echo "$HOME/.cache/tomd/docling-venv"
    }

    # Main processing
    FORMAT=$(detect_format "$INPUT_FILE")
    if [[ "$FORMAT" == "unknown" ]]; then
      echo "Error: Unable to detect file format for: $INPUT_FILE" >&2
      exit 1
    fi

    ENGINE=$(determine_engine "$INPUT_FILE" "$FORMAT" "$ENGINE")

    [[ "$VERBOSE" == "true" ]] && cat << EOF
    Processing Configuration:
    ------------------------
    Input: $INPUT_FILE
    Output: $OUTPUT_FILE
    Format: $FORMAT
    Engine: $ENGINE
    Memory Max: $MEMORY_MAX
    Memory High: $MEMORY_HIGH
    Chunk Size: $CHUNK_SIZE
    Smart Chunks: $SMART_CHUNKS
    No Chunks: $NO_CHUNKS
    EOF

    # Create output directory if needed
    OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
    [[ ! -d "$OUTPUT_DIR" ]] && mkdir -p "$OUTPUT_DIR"

    # Route to appropriate processor
    case "$ENGINE" in
      docling)
        [[ "$VERBOSE" == "true" ]] && echo "Processing with Docling engine..."

        # Setup Docling venv
        DOCLING_VENV=$(setup_docling_venv)

        # Use Docling from venv
        apply_memory_limit "$DOCLING_VENV/bin/python" ${./process_docling_venv.py} \
          "$INPUT_FILE" "$OUTPUT_FILE" \
          --chunk-size "$CHUNK_SIZE" \
          --smart-chunks "$SMART_CHUNKS" \
          --no-chunks "$NO_CHUNKS" \
          --verbose "$VERBOSE"
        ;;
      marker)
        [[ "$VERBOSE" == "true" ]] && echo "Processing with Marker engine (OCR)..."

        # Check if large PDF and suggest auto-chunking
        FILE_SIZE_MB=$(stat -c%s "$INPUT_FILE" 2>/dev/null | awk '{print int($1/1024/1024)}')
        if [[ "$FILE_SIZE_MB" -gt 50 ]] && [[ "$NO_CHUNKS" != "true" ]]; then
          AUTO_CHUNK_FLAG="--auto-chunk"
          [[ "$VERBOSE" == "true" ]] && echo "Large file detected (''${FILE_SIZE_MB}MB), enabling auto-chunking"
        else
          AUTO_CHUNK_FLAG=""
        fi

        apply_memory_limit ${pythonEnv}/bin/python ${./process_marker.py} \
          "$INPUT_FILE" "$OUTPUT_FILE" \
          --chunk-size "$CHUNK_SIZE" \
          --batch-multiplier "$BATCH_MULTIPLIER" \
          --memory-max "$MEMORY_MAX" \
          --memory-high "$MEMORY_HIGH" \
          $AUTO_CHUNK_FLAG \
          --verbose "$VERBOSE"
        ;;
      *)
        echo "Error: Unknown engine: $ENGINE" >&2
        exit 1
        ;;
    esac

    echo "Conversion complete: $OUTPUT_FILE"
  '';

in
stdenv.mkDerivation rec {
  pname = "tomd";
  version = "0.2.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
    qpdf
    systemd
    jq
    gawk
    coreutils
    poppler-utils
    gcc # For building docling dependencies
  ] ++ lib.optionals (marker-pdf != null) [ marker-pdf ];

  installPhase = ''
        mkdir -p $out/bin

        # Install the main wrapper script
        cp ${tomdScript}/bin/tomd $out/bin/
        chmod +x $out/bin/tomd

        # Install Docling venv setup script
        cp ${doclingVenvSetup}/bin/docling-venv-setup $out/bin/
        chmod +x $out/bin/docling-venv-setup

        # Copy Python processing scripts
        cp ${./process_docling.py} $out/bin/process_docling.py
        cp ${./process_docling_serve.py} $out/bin/process_docling_serve.py
        cp ${./process_marker.py} $out/bin/process_marker.py

        # Create a new script for venv-based Docling processing
        cat > $out/bin/process_docling_venv.py << 'PYTHON_EOF'
    #!/usr/bin/env python3
    """
    Docling-based document processor for tomd using venv installation.
    This version uses pip-installed Docling to avoid nixpkgs build issues.
    """

    import sys
    import os
    import argparse
    from pathlib import Path
    from typing import List, Dict, Any, Optional
    import json

    # Try importing simplified Docling components
    try:
        # Basic imports that should work without docling-parse
        from docling_core.types import Document
        from pdfplumber import PDF
        import pypdfium2
        HAS_BASIC_DOCLING = True
    except ImportError:
        HAS_BASIC_DOCLING = False

    def parse_arguments():
        """Parse command line arguments."""
        parser = argparse.ArgumentParser(description="Process documents with Docling (venv)")
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

    def process_with_basic_extraction(doc_path: Path, output_path: Path, verbose: bool = False) -> bool:
        """
        Process document using basic PDF extraction libraries.
        This is a fallback when full Docling isn't available.
        """
        try:
            if verbose:
                print(f"Processing {doc_path} with basic extraction...")

            markdown_lines = []

            # Detect file type
            file_ext = doc_path.suffix.lower()

            if file_ext == '.pdf':
                # Use pdfplumber for PDF extraction
                with PDF.open(str(doc_path)) as pdf:
                    for i, page in enumerate(pdf.pages, 1):
                        if verbose and i % 10 == 0:
                            print(f"  Processing page {i}/{len(pdf.pages)}")

                        # Extract text
                        text = page.extract_text()
                        if text:
                            markdown_lines.append(f"## Page {i}\n")
                            markdown_lines.append(text)
                            markdown_lines.append("\n---\n")

                        # Extract tables
                        tables = page.extract_tables()
                        for table in tables:
                            if table:
                                markdown_lines.append("\n### Table\n")
                                # Convert table to markdown
                                for row in table:
                                    row_str = "| " + " | ".join(str(cell or "") for cell in row) + " |"
                                    markdown_lines.append(row_str)
                                markdown_lines.append("\n")

            elif file_ext in ['.docx', '.pptx', '.html']:
                # For these formats, we need full Docling
                # Fall back to marker-pdf if available
                print(f"Warning: {file_ext} files require full Docling installation.", file=sys.stderr)
                print("Consider using --engine=marker for OCR-based extraction.", file=sys.stderr)
                return False

            # Write output
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text("\n".join(markdown_lines), encoding='utf-8')

            if verbose:
                print(f"Successfully wrote markdown to {output_path}")

            return True

        except Exception as e:
            print(f"Error processing document: {e}", file=sys.stderr)
            return False

    def main():
        """Main processing function."""
        args = parse_arguments()

        input_path = Path(args.input_file)
        output_path = Path(args.output_file)

        if not input_path.exists():
            print(f"Error: Input file does not exist: {input_path}", file=sys.stderr)
            sys.exit(1)

        # Try full Docling first
        try:
            from docling.document_converter import DocumentConverter

            if args.verbose:
                print("Using full Docling installation...")

            # Create converter
            converter = DocumentConverter()

            # Convert document
            result = converter.convert(str(input_path))

            # Export to markdown
            markdown_content = result.document.export_to_markdown()

            # Write output
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(markdown_content, encoding='utf-8')

            print(f"Successfully converted to: {output_path}")
            sys.exit(0)

        except ImportError:
            if args.verbose:
                print("Full Docling not available, using basic extraction...")
        except Exception as e:
            print(f"Docling processing failed: {e}", file=sys.stderr)
            if args.verbose:
                print("Falling back to basic extraction...")

        # Fall back to basic extraction
        success = process_with_basic_extraction(input_path, output_path, args.verbose)

        if success:
            print(f"Successfully converted to: {output_path}")
            sys.exit(0)
        else:
            print("Conversion failed", file=sys.stderr)
            sys.exit(1)

    if __name__ == "__main__":
        main()
    PYTHON_EOF
        chmod +x $out/bin/process_docling_venv.py

        # Wrap with PATH
        wrapProgram $out/bin/tomd \
          --prefix PATH : ${lib.makeBinPath ([
            qpdf systemd jq gawk coreutils pythonEnv poppler-utils gcc
            doclingVenvSetup
          ] ++ lib.optionals (marker-pdf != null) [ marker-pdf ])}
  '';

  meta = with lib; {
    description = "Universal document to markdown converter";
    longDescription = ''
      tomd is a comprehensive document-to-markdown converter that intelligently
      processes various document formats including PDF, DOCX, PPTX, HTML, and images.

      It uses a dual-engine approach:
      - Docling for structure extraction and clean document processing
      - marker-pdf for ML-based OCR and complex visual analysis

      The tool automatically selects the best engine based on document type
      and content, providing optimal results for any input format.
    '';
    homepage = "https://github.com/timblaktu/nixcfg";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
  };
}
