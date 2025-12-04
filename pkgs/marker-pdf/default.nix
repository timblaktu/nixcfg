# marker-pdf package
# PDF to Markdown converter with GPU acceleration via PyTorch
#
# This uses a Python environment with pip to install marker-pdf and its
# complex dependency tree (surya-ocr, pdftext, etc.) which aren't in nixpkgs.
#
# For WSL2 CUDA support, ensure wslCuda.enable = true in your NixOS config.
#
{ lib
, stdenv
, python3
, writeShellScriptBin
, makeWrapper
, fetchFromGitHub
, qpdf        # PDF splitting and TOC extraction
, systemd     # Memory limiting via systemd-run
, jq          # JSON parsing for qpdf output
  # CUDA support
, cudaSupport ? true
, cudaPackages ? { }
}:

let
  # Core packages that will be visible to venv via PYTHONPATH
  # Note: torch is NOT pre-installed - pip will install the correct version
  # with CUDA support as specified in marker-pdf's dependencies
  pythonPackages = with python3.pkgs; [
    pip
    virtualenv
    # Pre-install some common dependencies that have Nix packages
    pillow
    pydantic
    pydantic-settings
    click
    tqdm
    requests
    regex
    ftfy
  ];

  # Build environment that makes packages discoverable
  pythonEnv = python3.buildEnv.override {
    extraLibs = pythonPackages;
    ignoreCollisions = true;
  };

  # Version of marker-pdf to install
  version = "1.10.1";

in
writeShellScriptBin "marker-pdf-env" ''
    #!${stdenv.shell}
    # marker-pdf environment launcher
    # This creates/activates a venv with marker-pdf installed

    set -euo pipefail

    VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/marker-pdf-venv"

    # Ensure Nix Python packages are discoverable
    export PYTHONPATH="${pythonEnv}/${python3.sitePackages}:''${PYTHONPATH:-}"
    # Add CUDA libs and stdenv C++ library for PyTorch
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"

    # Default chunking and memory settings
    CHUNK_SIZE=100
    MEMORY_HIGH="20G"
    MEMORY_MAX="24G"
    AUTO_CHUNK=false

    # Parse wrapper flags and return non-wrapper args
    parse_flags() {
      local passthrough_args=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --auto-chunk)
            AUTO_CHUNK=true
            shift
            ;;
          --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
          --memory-high)
            MEMORY_HIGH="$2"
            shift 2
            ;;
          --memory-max)
            MEMORY_MAX="$2"
            shift 2
            ;;
          *)
            # Not a wrapper flag, pass through
            passthrough_args+=("$1")
            shift
            ;;
        esac
      done
      # Return non-wrapper args
      printf '%s\n' "''${passthrough_args[@]}"
    }

    # Extract TOC from PDF and generate chunk boundaries
    extract_toc_chunks() {
      local input_pdf="$1"
      local chunk_size="$2"

      # Try to extract TOC using qpdf
      local toc_json
      if toc_json=$(${qpdf}/bin/qpdf "$input_pdf" --json --json-key=outlines 2>/dev/null); then
        # Parse TOC and create chapter-based chunks
        # For now, fall back to page-based chunking (TOC parsing is complex)
        # TODO: Implement full TOC parsing in future iteration
        return 1
      else
        return 1
      fi
    }

    # Split PDF into chunks
    chunk_pdf() {
      local input_pdf="$1"
      local chunk_dir="$2"
      local chunk_size="$3"

      echo "Chunking PDF: $input_pdf (chunk size: $chunk_size pages)"

      # Get total page count
      local total_pages
      total_pages=$(${qpdf}/bin/qpdf --show-npages "$input_pdf")
      echo "Total pages: $total_pages"

      if [ "$total_pages" -le "$chunk_size" ]; then
        echo "PDF has $total_pages pages, no chunking needed"
        echo "$input_pdf" > "$chunk_dir/chunks.list"
        return 0
      fi

      # Try TOC-based chunking first
      if extract_toc_chunks "$input_pdf" "$chunk_size"; then
        echo "Using TOC-based chunking"
        # TOC chunks already created
        return 0
      fi

      # Fallback: Fixed-size page chunking
      echo "Using fixed-size page chunking ($chunk_size pages per chunk)"

      local basename
      basename=$(basename "$input_pdf" .pdf)
      local chunk_num=1
      local start_page=1

      rm -f "$chunk_dir/chunks.list"

      while [ "$start_page" -le "$total_pages" ]; do
        local end_page=$((start_page + chunk_size - 1))
        if [ "$end_page" -gt "$total_pages" ]; then
          end_page=$total_pages
        fi

        local chunk_name=$(printf "%s-pages-%03d-%03d.pdf" "$basename" "$start_page" "$end_page")
        local chunk_path="$chunk_dir/$chunk_name"

        echo "Creating chunk: $chunk_name (pages $start_page-$end_page)"
        ${qpdf}/bin/qpdf "$input_pdf" --pages "$input_pdf" "$start_page-$end_page" -- "$chunk_path"

        echo "$chunk_path" >> "$chunk_dir/chunks.list"

        start_page=$((end_page + 1))
        chunk_num=$((chunk_num + 1))
      done

      echo "Created $((chunk_num - 1)) chunks"
    }

    # Process a single PDF file with memory limiting
    process_with_limits() {
      local input_pdf="$1"
      local output_dir="$2"
      shift 2
      local extra_args=("$@")

      echo "Processing: $input_pdf -> $output_dir"
      echo "Memory limits: MemoryHigh=$MEMORY_HIGH, MemoryMax=$MEMORY_MAX"

      # Check if systemd user session is available
      if ! ${systemd}/bin/systemctl --user status &>/dev/null; then
        echo "ERROR: systemd user session not available"
        echo ""
        echo "Memory limiting requires systemd user session. To enable it:"
        echo "  1. Ensure systemd is running"
        echo "  2. Start user session: systemctl --user start"
        echo "  3. Or enable lingering: loginctl enable-linger $USER"
        echo ""
        echo "Alternatively, if you don't need memory limits, you can:"
        echo "  - Run marker_single directly: ~/.local/share/marker-pdf-venv/bin/marker_single"
        exit 1
      fi

      # Use systemd-run for memory limiting
      # marker_single uses Click which expects --output_dir, not positional arg
      ${systemd}/bin/systemd-run \
        --user \
        --scope \
        --quiet \
        -p MemoryHigh="$MEMORY_HIGH" \
        -p MemoryMax="$MEMORY_MAX" \
        "$VENV_DIR/bin/marker_single" "$input_pdf" --output_dir "$output_dir" "''${extra_args[@]}"
    }

    # Process PDF with auto-chunking
    process_chunked() {
      local input_pdf="$1"
      local output_dir="$2"
      shift 2
      local extra_args=("$@")

      # Create temporary directory for chunks
      local chunk_dir
      chunk_dir=$(mktemp -d -t marker-chunks-XXXXXX)
      trap "rm -rf '$chunk_dir'" EXIT

      # Split PDF into chunks
      chunk_pdf "$input_pdf" "$chunk_dir" "$CHUNK_SIZE"

      # Process each chunk
      local chunk_num=1
      while IFS= read -r chunk_path; do
        echo ""
        echo "=== Processing chunk $chunk_num ==="

        local chunk_output="$chunk_dir/output-$chunk_num"
        mkdir -p "$chunk_output"

        process_with_limits "$chunk_path" "$chunk_output" "''${extra_args[@]}"

        chunk_num=$((chunk_num + 1))
      done < "$chunk_dir/chunks.list"

      # Merge markdown outputs
      echo ""
      echo "=== Merging chunk outputs ==="
      mkdir -p "$output_dir"

      local merged_md="$output_dir/$(basename "$input_pdf" .pdf).md"
      : > "$merged_md"  # Create empty file

      for ((i=1; i<chunk_num; i++)); do
        local chunk_output="$chunk_dir/output-$i"
        if [ -f "$chunk_output"/*.md ]; then
          cat "$chunk_output"/*.md >> "$merged_md"
          echo "" >> "$merged_md"  # Add blank line between chunks
        fi
      done

      echo "Merged output: $merged_md"

      # Copy any other output files
      find "$chunk_dir"/output-* -type f ! -name "*.md" -exec cp {} "$output_dir/" \;

      echo "✓ Chunked processing complete!"
    }

    # Create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
      echo "Creating marker-pdf virtual environment..."
      ${pythonEnv}/bin/python -m venv "$VENV_DIR" --system-site-packages

      # Install marker-pdf and its dependencies
      echo "Installing marker-pdf ${version}..."
      "$VENV_DIR/bin/pip" install --upgrade pip

      # Install marker-pdf (lets pyproject.toml specify all dependencies)
      "$VENV_DIR/bin/pip" install "marker-pdf==${version}"

      # Validate installation at build time (fail fast if broken)
      echo "Validating marker-pdf installation..."
      if ! "$VENV_DIR/bin/python" -c 'import marker, surya, torch; print("✓ Imports successful - torch:", torch.__version__, "CUDA:", torch.cuda.is_available())'; then
        echo "ERROR: marker-pdf dependencies failed validation"
        rm -rf "$VENV_DIR"
        exit 1
      fi

      echo "✓ Installation complete and validated!"
    fi

    # If arguments provided, run marker commands
    if [ $# -gt 0 ]; then
      # Parse wrapper flags and get remaining args
      mapfile -t remaining_args < <(parse_flags "$@")
      set -- "''${remaining_args[@]}"

      # Show help if no commands remain after flag parsing
      if [ $# -eq 0 ]; then
        set -- help
      fi

      case "$1" in
        help|--help|-h)
          # Show help text
          cat <<EOF
  marker-pdf-env: Marker PDF to Markdown converter with GPU support

  Commands:
    marker-pdf-env marker_single <input.pdf> <output_dir> [OPTIONS]
      Convert single PDF to Markdown

    marker-pdf-env marker <input_dir> <output_dir> [OPTIONS]
      Batch convert PDFs in directory

    marker-pdf-env shell
      Enter Python shell with marker-pdf available

    marker-pdf-env update
      Update marker-pdf to latest version

    marker-pdf-env python ...
      Run Python directly in marker-pdf environment

  Options:
    --auto-chunk              Enable automatic chunking for large PDFs
    --chunk-size N            Pages per chunk (default: 100)
    --memory-high SIZE        Soft memory limit (default: 20G)
    --memory-max SIZE         Hard memory limit (default: 24G)

  Active Config:
    Chunk size: $CHUNK_SIZE pages
    Memory limits: $MEMORY_HIGH soft / $MEMORY_MAX hard
    VENV: $VENV_DIR
    CUDA: ${if cudaSupport then "enabled" else "disabled"}

  ⚠️  Large PDFs may exhaust RAM due to upstream memory leaks. Use --auto-chunk for 500+ page PDFs.

  Recommended memory limits (28GB system):
    <100 pages:    --memory-high 8G  --memory-max 10G
    100-500 pages: --memory-high 16G --memory-max 20G
    500+ pages:    --memory-high 20G --memory-max 24G (use --auto-chunk)

  For GPU acceleration, ensure your NixOS config has:
    wslCuda.enable = true;
  EOF
          ;;
        shell)
          echo "Entering marker-pdf environment..."
          exec "$VENV_DIR/bin/python" -c "import marker; print(f'marker-pdf ready. Python: {marker.__file__}')" && \
          exec ${stdenv.shell}
          ;;
        update)
          echo "Updating marker-pdf..."
          "$VENV_DIR/bin/pip" install --upgrade "marker-pdf"
          ;;
        marker_single)
          # Parse remaining args for input/output
          shift  # Remove 'marker_single'

          # If --help requested, pass through to actual marker_single
          if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
            "$VENV_DIR/bin/marker_single" --help
            exit 0
          fi

          input_pdf=""
          output_dir=""
          extra_args=()

          while [[ $# -gt 0 ]]; do
            case "$1" in
              --output_dir)
                output_dir="$2"
                shift 2
                ;;
              *)
                if [ -z "$input_pdf" ]; then
                  input_pdf="$1"
                  shift
                elif [ -z "$output_dir" ]; then
                  output_dir="$1"
                  shift
                else
                  extra_args+=("$1")
                  shift
                fi
                ;;
            esac
          done

          if [ -z "$input_pdf" ] || [ -z "$output_dir" ]; then
            echo "Error: marker_single requires <input.pdf> and <output_dir> (or --output_dir)"
            echo "Usage: marker-pdf-env marker_single <input.pdf> <output_dir> [OPTIONS]"
            echo "   or: marker-pdf-env marker_single <input.pdf> --output_dir <dir> [OPTIONS]"
            exit 1
          fi

          if [ "$AUTO_CHUNK" = true ]; then
            process_chunked "$input_pdf" "$output_dir" "''${extra_args[@]}"
          else
            process_with_limits "$input_pdf" "$output_dir" "''${extra_args[@]}"
          fi
          ;;
        *)
          # Pass through to marker CLI with memory limits
          cmd="$1"
          shift
          ${systemd}/bin/systemd-run \
            --user \
            --scope \
            --quiet \
            -p MemoryHigh="$MEMORY_HIGH" \
            -p MemoryMax="$MEMORY_MAX" \
            "$VENV_DIR/bin/$cmd" "$@"
          ;;
      esac
    else
      # Show help
      cat <<EOF
  marker-pdf-env: Marker PDF to Markdown converter with GPU support

  Commands:
    marker-pdf-env marker_single <input.pdf> <output_dir> [OPTIONS]
      Convert single PDF to Markdown

    marker-pdf-env marker <input_dir> <output_dir> [OPTIONS]
      Batch convert PDFs in directory

    marker-pdf-env shell
      Enter Python shell with marker-pdf available

    marker-pdf-env update
      Update marker-pdf to latest version

    marker-pdf-env python ...
      Run Python directly in marker-pdf environment

  Options:
    --auto-chunk              Enable automatic chunking for large PDFs
    --chunk-size N            Pages per chunk (default: 100)
    --memory-high SIZE        Soft memory limit (default: 20G)
    --memory-max SIZE         Hard memory limit (default: 24G)

  Active Config:
    Chunk size: $CHUNK_SIZE pages
    Memory limits: $MEMORY_HIGH soft / $MEMORY_MAX hard
    VENV: $VENV_DIR
    CUDA: ${if cudaSupport then "enabled" else "disabled"}

  ⚠️  Large PDFs may exhaust RAM due to upstream memory leaks. Use --auto-chunk for 500+ page PDFs.

  Recommended memory limits (28GB system):
    <100 pages:    --memory-high 8G  --memory-max 10G
    100-500 pages: --memory-high 16G --memory-max 20G
    500+ pages:    --memory-high 20G --memory-max 24G (use --auto-chunk)

  For GPU acceleration, ensure your NixOS config has:
    wslCuda.enable = true;
  EOF
    fi
''

  // {
  meta = with lib; {
    description = "PDF to Markdown converter with ML-based OCR and GPU acceleration";
    homepage = "https://github.com/VikParuchuri/marker";
    license = licenses.gpl3Only;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
