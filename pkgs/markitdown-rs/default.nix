{ lib
, rustPlatform
, pkg-config
, openssl
, fetchFromGitHub
}:

rustPlatform.buildRustPackage rec {
  pname = "markitdown";
  version = "0.1.10-unstable-2025-01-10";

  # Use upstream GitHub repository (latest commit with v0.1.10 + error handling improvements)
  src = fetchFromGitHub {
    owner = "uhobnil";
    repo = "markitdown-rs";
    rev = "a3c0bb27dbdcfb33b078b08bfc21524575a9a13c";
    hash = "sha256-3SSG+Yz6hSNyEc3JzFQBjctd+UuUAwT2+Z3xRj0I/X8=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
  ];

  meta = with lib; {
    description = "A Rust library to convert various document formats into markdown";
    homepage = "https://github.com/uhobnil/markitdown-rs";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "markitdown";
  };
}
