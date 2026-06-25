#!/usr/bin/env nix
#!nix shell --ignore-environment .#cacert .#coreutils .#curl .#bash --command bash

# Pin-ahead vendored copy (nixcfg plan 046). Re-run to refresh manifest.json to
# a newer claude-code release than nixpkgs ships, e.g.:
#   ./update.sh            # -> bucket "latest"
#   ./update.sh 2.1.191    # -> a specific version
# Then `git add` and `nix build '.#...claude-code'` to verify.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

curl -fsSL "$BASE_URL/$VERSION/manifest.json" --output manifest.json
