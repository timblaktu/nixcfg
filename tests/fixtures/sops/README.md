# SOPS Test Fixtures

**Purpose**: Pre-encrypted SOPS secrets for VM integration tests.

These files are used by `vm-sops-secrets` in `modules/flake-parts/vm-tests.nix`.
They exist as static fixtures (not generated at build time) to avoid IFD
(import from derivation), keeping `nix flake check --no-build` fast.

**WARNING**: The age key here is a **test-only** key. It has no access to
real secrets. Never use it outside of automated tests.

## Files

- `test-age-key.txt` - Age private key (test-only, no real secrets)
- `test-secrets.yaml` - SOPS-encrypted YAML containing test values

## Plaintext Values

The encrypted file contains:
```yaml
database_password: supersecret123
api_key: key-abc-def-789
tls_cert: |
    -----BEGIN CERTIFICATE-----
    dGVzdC1jZXJ0aWZpY2F0ZS1jb250ZW50
    -----END CERTIFICATE-----
```

## Regeneration

If you need to regenerate (e.g., after sops format changes):

```bash
cd /tmp
age-keygen -o test-age-key.txt
PUBKEY=$(grep -oP 'age1\w+' test-age-key.txt | head -1)

cat > .sops.yaml <<EOF
keys:
  - &testkey $PUBKEY
creation_rules:
  - path_regex: .*\.yaml$
    key_groups:
      - age:
          - *testkey
EOF

cat > secrets-plain.yaml <<'YAML'
database_password: supersecret123
api_key: key-abc-def-789
tls_cert: |
    -----BEGIN CERTIFICATE-----
    dGVzdC1jZXJ0aWZpY2F0ZS1jb250ZW50
    -----END CERTIFICATE-----
YAML

export SOPS_AGE_KEY_FILE=/tmp/test-age-key.txt
sops --config .sops.yaml --encrypt secrets-plain.yaml > test-secrets.yaml

cp test-age-key.txt test-secrets.yaml /path/to/nixcfg/tests/fixtures/sops/
```
