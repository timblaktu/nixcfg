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
, gawk        # Arithmetic for batch size calculation
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

        # ========================================
        # MEMORY OPTIMIZATION CONFIGURATION
        # ========================================

        # PyTorch memory optimization for 8GB GPU
        # These settings actually reduce memory allocation, not just kill on excess
        export PYTORCH_ALLOC_CONF="max_split_size_mb:256,garbage_collection_threshold:0.6,expandable_segments:True"

        # Limit PyTorch threads to reduce CPU memory overhead
        export OMP_NUM_THREADS=4
        export MKL_NUM_THREADS=4

        # GPU VRAM configuration for 8GB RTX 2000 Ada
        export CUDA_VISIBLE_DEVICES=0
        export INFERENCE_RAM=7  # Leave 1GB for system overhead

        # ========================================
        # FORCE GPU USAGE - CRITICAL FOR PERFORMANCE
        # ========================================
        # Force PyTorch to use CUDA device (GPU) instead of CPU
        export TORCH_DEVICE=cuda
        export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:256"

        # Ensure Nix Python packages are discoverable
        export PYTHONPATH="${pythonEnv}/${python3.sitePackages}:''${PYTHONPATH:-}"

        # Add CUDA libs and stdenv C++ library for PyTorch
        # Include both WSL CUDA libs and Nix-provided libs if available
        export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${stdenv.cc.cc.lib}/lib:''${LD_LIBRARY_PATH:-}"

        # Additional CUDA environment variables for better detection
        export CUDA_HOME="/usr/lib/wsl"  # WSL CUDA home
        export CUDA_PATH="/usr/lib/wsl"

        # Default settings optimized for 8GB GPU + memory efficiency
        BATCH_MULTIPLIER="''${MARKER_BATCH_MULTIPLIER:-0.5}"  # Reduce batch size by default
        CHUNK_SIZE="''${MARKER_CHUNK_SIZE:-50}"  # Smaller chunks for 8GB GPU
        MEMORY_HIGH="''${MARKER_MEMORY_HIGH:-20G}"  # Soft limit for warnings
        MEMORY_MAX="''${MARKER_MEMORY_MAX:-24G}"  # Hard limit - needs headroom for model loading
        AUTO_CHUNK="''${MARKER_AUTO_CHUNK:-false}"


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
          echo "Memory optimization: batch_multiplier=$BATCH_MULTIPLIER (lower = less memory)"
          echo "PyTorch config: $PYTORCH_ALLOC_CONF"
          echo "GPU VRAM limit: $INFERENCE_RAM GB (of 8GB total)"

          # Show GPU status
          echo "GPU Configuration:"
          echo "  TORCH_DEVICE: $TORCH_DEVICE"
          echo "  CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
          echo "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

          # Quick GPU check
          "$VENV_DIR/bin/python" -c "
    import torch
    if torch.cuda.is_available():
        print(f'  ✓ GPU ACTIVE: {torch.cuda.get_device_name(0)}')
        print(f'  CUDA version: {torch.version.cuda}')
    else:
        print('  ⚠️ WARNING: GPU NOT DETECTED - Running on CPU (100x slower!)')
    " || true

          # Detect if running in WSL
          local is_wsl=false
          if uname -r | grep -qi microsoft; then
            is_wsl=true
          fi

          # Convert memory limit to KB for ulimit
          local memory_limit_kb
          case "$MEMORY_MAX" in
            *G)
              memory_limit_kb=$(( ''${MEMORY_MAX%G} * 1024 * 1024 ))
              ;;
            *M)
              memory_limit_kb=$(( ''${MEMORY_MAX%M} * 1024 ))
              ;;
            *)
              echo "ERROR: Invalid memory limit format: $MEMORY_MAX (use format like 20G or 20480M)"
              exit 1
              ;;
          esac

          # Calculate actual batch sizes based on multiplier
          # Default batch sizes in marker-pdf are model-dependent, but we can set them all
          local batch_args=()
          if [ "$BATCH_MULTIPLIER" != "1.0" ]; then
            # Apply multiplier to common batch size options
            # Default batch sizes vary but we'll scale them proportionally
            # Layout model typically uses batch_size=2, detection uses 2, recognition uses 8
            local layout_batch=$(${gawk}/bin/awk "BEGIN {v = int(2 * $BATCH_MULTIPLIER); print (v < 1) ? 1 : v}")
            local detection_batch=$(${gawk}/bin/awk "BEGIN {v = int(2 * $BATCH_MULTIPLIER); print (v < 1) ? 1 : v}")
            local recognition_batch=$(${gawk}/bin/awk "BEGIN {v = int(8 * $BATCH_MULTIPLIER); print (v < 1) ? 1 : v}")
            local ocr_error_batch=$(${gawk}/bin/awk "BEGIN {v = int(4 * $BATCH_MULTIPLIER); print (v < 1) ? 1 : v}")

            batch_args=(
              "--layout_batch_size" "$layout_batch"
              "--detection_batch_size" "$detection_batch"
              "--recognition_batch_size" "$recognition_batch"
              "--ocr_error_batch_size" "$ocr_error_batch"
            )

            echo "Batch sizes: layout=$layout_batch, detection=$detection_batch, recognition=$recognition_batch, ocr_error=$ocr_error_batch"
          fi

          if [ "$is_wsl" = true ]; then
            echo "WSL detected: Using ulimit for memory limiting (systemd-run doesn't enforce limits in WSL)"
            echo "Memory limit: $MEMORY_MAX (''${memory_limit_kb}KB virtual memory)"

            # Use ulimit -v for virtual memory limiting in WSL
            # Note: This is the only reliable method in WSL2 as cgroups v2 memory controller
            # is not properly enforced by the WSL2 kernel
            (
              ulimit -v "$memory_limit_kb"
              "$VENV_DIR/bin/marker_single" "$input_pdf" --output_dir "$output_dir" "''${batch_args[@]}" "''${extra_args[@]}"
            )
          else
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

            # Use systemd-run for memory limiting on native Linux
            ${systemd}/bin/systemd-run \
              --user \
              --scope \
              --quiet \
              -p MemoryHigh="$MEMORY_HIGH" \
              -p MemoryMax="$MEMORY_MAX" \
              "$VENV_DIR/bin/marker_single" "$input_pdf" --output_dir "$output_dir" "''${batch_args[@]}" "''${extra_args[@]}"
          fi
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
          if ! "$VENV_DIR/bin/python" -c "
    import marker, surya, torch
    import os
    print('✓ Imports successful')
    print(f'  PyTorch version: {torch.__version__}')
    print(f'  CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'  GPU device: {torch.cuda.get_device_name(0)}')
        print(f'  CUDA version: {torch.version.cuda}')
    print(f'  TORCH_DEVICE env: {os.environ.get(\"TORCH_DEVICE\", \"not set\")}')
    print(f'  Using device: {\"cuda\" if torch.cuda.is_available() else \"cpu\"}')
          "; then
            echo "ERROR: marker-pdf dependencies failed validation"
            rm -rf "$VENV_DIR"
            exit 1
          fi

          echo "✓ Installation complete and validated!"
        fi

        # If arguments provided, run marker commands
        if [ $# -gt 0 ]; then
          # Parse wrapper flags FIRST to set variables
          # We need to parse in the current shell, not a subshell
          wrapper_args=()
          remaining_args=()

          # Parse flags inline to avoid subshell issues
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --batch-multiplier|--batch_multiplier)
                BATCH_MULTIPLIER="$2"
                shift 2
                ;;
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
                # Not a wrapper flag, keep it
                remaining_args+=("$1")
                shift
                ;;
            esac
          done

          # Reset args to non-wrapper arguments
          set -- "''${remaining_args[@]}"

          # Show help if no commands remain after flag parsing
          if [ $# -eq 0 ]; then
            set -- help
          fi

          case "$1" in
            help|--help|-h)
              # Show help text
              cat <<'EOF'
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

      Memory Optimization Options:
        --batch-multiplier N      Batch size multiplier (default: 0.5, lower = less memory)
        --auto-chunk              Enable automatic chunking for large PDFs
        --chunk-size N            Pages per chunk (default: 50)
        --memory-high SIZE        Soft memory limit (default: 12G)
        --memory-max SIZE         Hard memory limit (default: 16G)

      Active Config:
        Batch multiplier: $BATCH_MULTIPLIER (controls actual memory usage)
        Chunk size: $CHUNK_SIZE pages
        Memory limits: $MEMORY_HIGH soft / $MEMORY_MAX hard
        GPU VRAM: $INFERENCE_RAM GB allocated (8GB total)
        PyTorch: GC at 60%, max_split 256MB
        VENV: $VENV_DIR
        CUDA: ${if cudaSupport then "enabled" else "disabled"}

      Memory Usage Control:
        The --batch-multiplier parameter DIRECTLY controls memory usage:
          1.0 = default (high memory, fast)
          0.5 = 50% memory (recommended for 8GB GPU)
          0.25 = 25% memory (conservative)
          0.1 = minimal memory (very slow)

      ⚠️  Your GPU has 8GB VRAM. Settings optimized for RTX 2000 Ada.
      ⚠️  WSL Note: Memory limits enforced via ulimit (systemd-run doesn't work in WSL2).

      Examples:
        # Conservative memory usage for large PDFs
        marker-pdf-env marker_single large.pdf output/ --batch-multiplier 0.25 --auto-chunk

        # Balanced performance/memory (default)
        marker-pdf-env marker_single document.pdf output/

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

              # Detect if running in WSL
              if uname -r | grep -qi microsoft; then
                # WSL detected - use ulimit for memory limiting
                # Convert memory limit to KB for ulimit
                memory_limit_kb=""
                case "$MEMORY_MAX" in
                  *G)
                    memory_limit_kb=$(( ''${MEMORY_MAX%G} * 1024 * 1024 ))
                    ;;
                  *M)
                    memory_limit_kb=$(( ''${MEMORY_MAX%M} * 1024 ))
                    ;;
                  *)
                    echo "ERROR: Invalid memory limit format: $MEMORY_MAX"
                    exit 1
                    ;;
                esac

                (
                  ulimit -v "$memory_limit_kb"
                  "$VENV_DIR/bin/$cmd" "$@"
                )
              else
                # Native Linux - use systemd-run
                ${systemd}/bin/systemd-run \
                  --user \
                  --scope \
                  --quiet \
                  -p MemoryHigh="$MEMORY_HIGH" \
                  -p MemoryMax="$MEMORY_MAX" \
                  "$VENV_DIR/bin/$cmd" "$@"
              fi
              ;;
          esac
        else
          # Show help
          cat <<'EOF'
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

      Memory Optimization Options:
        --batch-multiplier N      Batch size multiplier (default: 0.5, lower = less memory)
        --auto-chunk              Enable automatic chunking for large PDFs
        --chunk-size N            Pages per chunk (default: 50)
        --memory-high SIZE        Soft memory limit (default: 12G)
        --memory-max SIZE         Hard memory limit (default: 16G)

      Active Config:
        Batch multiplier: $BATCH_MULTIPLIER (controls actual memory usage)
        Chunk size: $CHUNK_SIZE pages
        Memory limits: $MEMORY_HIGH soft / $MEMORY_MAX hard
        GPU VRAM: $INFERENCE_RAM GB allocated (8GB total)
        PyTorch: GC at 60%, max_split 256MB
        VENV: $VENV_DIR
        CUDA: ${if cudaSupport then "enabled" else "disabled"}

      Memory Usage Control:
        The --batch-multiplier parameter DIRECTLY controls memory usage:
          1.0 = default (high memory, fast)
          0.5 = 50% memory (recommended for 8GB GPU)
          0.25 = 25% memory (conservative)
          0.1 = minimal memory (very slow)

      ⚠️  Your GPU has 8GB VRAM. Settings optimized for RTX 2000 Ada.
      ⚠️  WSL Note: Memory limits enforced via ulimit (systemd-run doesn't work in WSL2).

      Examples:
        # Conservative memory usage for large PDFs
        marker-pdf-env marker_single large.pdf output/ --batch-multiplier 0.25 --auto-chunk

        # Balanced performance/memory (default)
        marker-pdf-env marker_single document.pdf output/

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
