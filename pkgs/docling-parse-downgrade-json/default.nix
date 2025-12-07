{ pkgs ? import <nixpkgs> { } }:

let
  # Use nlohmann_json 3.11.x which supports bool conversions
  nlohmann_json_3_11 = pkgs.nlohmann_json.overrideAttrs (oldAttrs: rec {
    version = "3.11.3";
    src = pkgs.fetchFromGitHub {
      owner = "nlohmann";
      repo = "json";
      rev = "v${version}";
      hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
    };
  });
in

pkgs.python312Packages.docling-parse.overrideAttrs (oldAttrs: {
  # Replace nlohmann_json with 3.11.x version
  nativeBuildInputs = (builtins.filter (x: (x.pname or "") != "nlohmann_json") (oldAttrs.nativeBuildInputs or [ ]))
    ++ [ nlohmann_json_3_11 ];

  buildInputs = (builtins.filter (x: (x.pname or "") != "nlohmann_json") (oldAttrs.buildInputs or [ ]))
    ++ [ nlohmann_json_3_11 ];

  # Add a note about why we're using an older version
  postPatch = (oldAttrs.postPatch or "") + ''
    echo "Using nlohmann_json 3.11.3 for bool conversion compatibility"
  '';
})
