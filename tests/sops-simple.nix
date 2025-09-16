# Simple SOPS-NiX Test
{ pkgs, lib }:

pkgs.runCommand "test-sops-simple" {
  buildInputs = with pkgs; [ sops age ];
} ''
  set -x  # Enable debugging
  echo "=== Simple SOPS Test ===" > $out
  
  # Generate test key
  export SOPS_AGE_KEY_FILE="$(mktemp -d)/age.key"
  echo "Key file: $SOPS_AGE_KEY_FILE" >> $out
  ${pkgs.age}/bin/age-keygen -o $SOPS_AGE_KEY_FILE 2>&1 || {
    echo "Failed to generate age key" >> $out
    exit 1
  }
  
  # Extract public key
  TEST_PUBKEY=$(grep -o 'age1[a-z0-9]*' $SOPS_AGE_KEY_FILE | head -1) || {
    echo "Failed to extract public key" >> $out
    exit 1
  }
  
  echo "Generated test age key: $TEST_PUBKEY" >> $out
  
  # Test sops is available
  if ${pkgs.sops}/bin/sops --version &>/dev/null; then
    echo "✓ SOPS is available" >> $out
  else
    echo "✗ SOPS not found" >> $out
    exit 1
  fi
  
  # Test age is available
  if ${pkgs.age}/bin/age --version &>/dev/null; then
    echo "✓ Age is available" >> $out
  else
    echo "✗ Age not found" >> $out
    exit 1
  fi
  
  echo "" >> $out
  echo "=== Test Completed ===" >> $out
''