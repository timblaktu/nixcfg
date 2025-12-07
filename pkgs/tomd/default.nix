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
}:

let
  # Python environment with required packages
  pythonEnv = python3.withPackages (ps: with ps; [
    # Common dependencies
    pymupdf
    pymupdf4llm
    pillow

    # PDF processing
    pdfplumber
    pypdfium2

    # File type detection
    filetype

    # For API client if docling-serve is available
    httpx

    # Note: Docling will be added once build issues are fixed
    # Note: marker-pdf integration pending
  ]);

  # Main tomd wrapper script
  tomdScript = writeShellScriptBin "tomd" ''
    #!${stdenv.shell}
    set -euo pipefail

    # Constants
    DEFAULT_CHUNK_SIZE=100
    DEFAULT_MEMORY_MAX="24G"
    DEFAULT_MEMORY_HIGH="20G"
    DEFAULT_BATCH_MULTIPLIER="0.5"
    DEFAULT_ENGINE="auto"

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
      --chunk-size=N       Maximum pages per chunk (default: $DEFAULT_CHUNK_SIZE)
      --smart-chunks       Use document structure for chunking (default)
      --no-chunks          Process as single file (may use lots of memory)
      --memory-max=SIZE    Maximum memory limit (default: $DEFAULT_MEMORY_MAX)
      --memory-high=SIZE   High memory watermark (default: $DEFAULT_MEMORY_HIGH)
      --batch-multiplier=N GPU batch size multiplier (default: $DEFAULT_BATCH_MULTIPLIER)
      --verbose            Show detailed processing information
      --help               Show this help message

    SUPPORTED FORMATS:
      • PDF - Both native and scanned
      • DOCX - Microsoft Word documents
      • PPTX - Microsoft PowerPoint presentations
      • HTML - Web pages
      • Images - PNG, JPG, TIFF (with OCR)

    EXAMPLES:
      # Simple conversion
      tomd document.pdf document.md

      # Force specific engine
      tomd scanned.pdf output.md --engine=marker

      # Control memory usage
      tomd large.pdf output.md --memory-max=16G --chunk-size=50

      # Process without chunking
      tomd small.pdf output.md --no-chunks

    NOTES:
      • The tool automatically detects the best engine for each document
      • Smart chunking respects document structure (chapters, sections)
      • Memory limits are enforced via systemd-run or ulimit (WSL)
      • GPU acceleration is used when available

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

    # Determine processing engine
    determine_engine() {
      local file="$1"
      local format="$2"
      local engine="$3"

      # If engine is explicitly specified, use it
      if [[ "$engine" != "auto" ]]; then
        echo "$engine"
        return
      fi

      # Auto-select based on format
      case "$format" in
        docx|pptx|html)
          echo "docling"
          ;;
        image)
          echo "marker"  # Images need OCR
          ;;
        pdf)
          # For PDFs, we need to analyze if OCR is needed
          # For now, default to docling as it's faster
          echo "docling"
          ;;
        *)
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
        # Try docling-serve first, fallback to regular docling
        if command -v docling-serve &> /dev/null; then
          apply_memory_limit ${pythonEnv}/bin/python ${./process_docling_serve.py} \
            "$INPUT_FILE" "$OUTPUT_FILE" \
            --chunk-size "$CHUNK_SIZE" \
            --smart-chunks "$SMART_CHUNKS" \
            --no-chunks "$NO_CHUNKS" \
            --verbose "$VERBOSE"
        else
          apply_memory_limit ${pythonEnv}/bin/python ${./process_docling.py} \
            "$INPUT_FILE" "$OUTPUT_FILE" \
            --chunk-size "$CHUNK_SIZE" \
            --smart-chunks "$SMART_CHUNKS" \
            --no-chunks "$NO_CHUNKS" \
            --verbose "$VERBOSE"
        fi
        ;;
      marker)
        [[ "$VERBOSE" == "true" ]] && echo "Processing with Marker engine (OCR)..."
        apply_memory_limit ${pythonEnv}/bin/python ${./process_marker.py} \
          "$INPUT_FILE" "$OUTPUT_FILE" \
          --chunk-size "$CHUNK_SIZE" \
          --batch-multiplier "$BATCH_MULTIPLIER" \
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
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pythonEnv
    qpdf
    systemd
    jq
    gawk
    coreutils
  ];

  installPhase = ''
    mkdir -p $out/bin

    # Install the main wrapper script
    cp ${tomdScript}/bin/tomd $out/bin/
    chmod +x $out/bin/tomd

    # Copy Python processing scripts
    cp ${./process_docling.py} $out/bin/process_docling.py
    cp ${./process_docling_serve.py} $out/bin/process_docling_serve.py
    cp ${./process_marker.py} $out/bin/process_marker.py

    # Wrap with PATH
    wrapProgram $out/bin/tomd \
      --prefix PATH : ${lib.makeBinPath [ qpdf systemd jq gawk coreutils pythonEnv ]}
  '';

  meta = with lib; {
    description = "Universal document to markdown converter";
    longDescription = ''
      tomd is a comprehensive document-to-markdown converter that intelligently
      processes various document formats including PDF, DOCX, PPTX, HTML, and images.
      It uses Docling for document structure analysis and marker-pdf for OCR tasks.
    '';
    homepage = "https://github.com/timblaktu/nixcfg";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
  };
}
