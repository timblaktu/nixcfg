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
  # Core packages that will be visible to venv via PYTHONPATH
  pythonPackages = with python3.pkgs; [
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
  ] ++ lib.optionals cudaSupport [
    torch-bin
    torchvision-bin
  ] ++ lib.optionals (!cudaSupport) [
    torch
    torchvision
  ];

  # Build environment that makes packages discoverable
  pythonEnv = python3.buildEnv.override {
    extraLibs = pythonPackages;
    ignoreCollisions = true;
  };

  # Version of marker-pdf to install
  version = "1.6.0";

in
writeShellScriptBin "marker-pdf-env" ''
    #!${stdenv.shell}
    # marker-pdf environment launcher
    # This creates/activates a venv with marker-pdf installed

    set -euo pipefail

    VENV_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/marker-pdf-venv"

    # Ensure Nix Python packages are discoverable
    export PYTHONPATH="${pythonEnv}/${python3.sitePackages}:''${PYTHONPATH:-}"
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:''${LD_LIBRARY_PATH:-}"

    # Create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
      echo "Creating marker-pdf virtual environment..."
      ${pythonEnv}/bin/python -m venv "$VENV_DIR" --system-site-packages

      # Install marker-pdf and its dependencies
      echo "Installing marker-pdf ${version}..."
      "$VENV_DIR/bin/pip" install --upgrade pip

      # Verify torch is available
      if "$VENV_DIR/bin/python" -c "import torch; print(f'✓ PyTorch {torch.__version__} with CUDA: {torch.cuda.is_available()}')" 2>/dev/null; then
        echo "✓ Using Nix-provided PyTorch"
      else
        echo "⚠ Warning: PyTorch not found, pip will install it"
      fi

      # Install marker-pdf with compatible versions (surya-ocr 0.13 has config issues)
      "$VENV_DIR/bin/pip" install "marker-pdf==${version}" "surya-ocr>=0.12.0,<0.13" "transformers>=4.45.2,<4.50"

      echo "Installation complete!"
    fi

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
