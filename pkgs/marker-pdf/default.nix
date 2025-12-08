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
, runCommand
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

  # Create the script with substitutions
  markerScript = runCommand "marker-pdf-script"
    {
      src = ./marker-pdf-env.sh;
    } ''
    cp $src $out
    substituteInPlace $out \
      --replace "@qpdf@" "${qpdf}" \
      --replace "@systemd@" "${systemd}" \
      --replace "@gawk@" "${gawk}" \
      --replace "@pythonEnv@" "${pythonEnv}" \
      --replace "@pythonPath@" "${pythonEnv}/${python3.sitePackages}" \
      --replace "@stdenvLib@" "${stdenv.cc.cc.lib}/lib" \
      --replace "@shell@" "${stdenv.shell}" \
      --replace "@version@" "${version}" \
      --replace "@cudaSupport@" "${if cudaSupport then "enabled" else "disabled"}"
  '';

in
writeShellScriptBin "marker-pdf-env" (builtins.readFile markerScript) // {
  meta = with lib; {
    description = "PDF to Markdown converter with ML-based OCR and GPU acceleration";
    homepage = "https://github.com/VikParuchuri/marker";
    license = licenses.gpl3Only;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
