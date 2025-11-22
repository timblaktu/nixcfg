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
  # CUDA support
, cudaSupport ? true
, cudaPackages ? { }
}:

let
  # Use Python with CUDA-enabled PyTorch for GPU acceleration
  pythonEnv = python3.withPackages (ps: with ps; [
    pip
    virtualenv
    # Pre-install some dependencies that have Nix packages
    pillow
    pydantic
    pydantic-settings
    click
    tqdm
    requests
    regex
    ftfy
    # torch-bin includes CUDA support from pre-built wheels
  ] ++ lib.optionals cudaSupport [
    ps.torch-bin
    ps.torchvision-bin
  ] ++ lib.optionals (!cudaSupport) [
    ps.torch
    ps.torchvision
  ]);

  # Version of marker-pdf to install
  version = "1.6.0";

in
writeShellScriptBin "marker-pdf-env" ''
    #!${stdenv.shell}
    # marker-pdf environment launcher
    # This creates/activates a venv with marker-pdf installed

    set -euo pipefail

    VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/marker-pdf-venv"

    # Create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
      echo "Creating marker-pdf virtual environment..."
      ${pythonEnv}/bin/python -m venv "$VENV_DIR" --system-site-packages

      # Install marker-pdf and its dependencies
      echo "Installing marker-pdf ${version}..."
      "$VENV_DIR/bin/pip" install --upgrade pip
      "$VENV_DIR/bin/pip" install "marker-pdf==${version}"

      echo "Installation complete!"
    fi

    # Ensure WSL CUDA libraries are in path
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:''${LD_LIBRARY_PATH:-}"

    # If arguments provided, run marker commands directly
    if [ $# -gt 0 ]; then
      case "$1" in
        shell)
          echo "Entering marker-pdf environment..."
          exec "$VENV_DIR/bin/python" -c "import marker; print(f'marker-pdf ready. Python: {marker.__file__}')" && \
          exec ${stdenv.shell}
          ;;
        update)
          echo "Updating marker-pdf..."
          "$VENV_DIR/bin/pip" install --upgrade "marker-pdf"
          ;;
        *)
          # Pass through to marker CLI
          exec "$VENV_DIR/bin/$@"
          ;;
      esac
    else
      # Show help
      cat <<EOF
  marker-pdf-env: Marker PDF to Markdown converter with GPU support

  Commands:
    marker-pdf-env marker_single <input.pdf> <output_dir>  - Convert single PDF
    marker-pdf-env marker <input_dir> <output_dir>         - Batch convert PDFs
    marker-pdf-env shell                                   - Enter Python shell
    marker-pdf-env update                                  - Update marker-pdf
    marker-pdf-env python ...                              - Run Python directly

  Environment:
    VENV: $VENV_DIR
    CUDA: ${if cudaSupport then "enabled" else "disabled"}
    LD_LIBRARY_PATH includes: /usr/lib/wsl/lib

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
