# Example custom package
{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "example-package";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-package";
    rev = "v${version}";
    sha256 = "0000000000000000000000000000000000000000000000000000";
    # Replace with actual hash
  };

  buildInputs = [
    # Add dependencies here
  ];

  meta = with lib; {
    description = "An example package";
    homepage = "https://github.com/example/example-package";
    license = licenses.mit;
    maintainers = with maintainers; [ tim ];
    platforms = platforms.all;
  };
}
