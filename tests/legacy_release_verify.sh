#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import os
import sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

directory = sys.argv[1]
private = Ed25519PrivateKey.generate()
message = b'0123456789abcdef' * 4 + b'  source.tar.gz\n'
with open(os.path.join(directory, 'public.pem'), 'wb') as f:
    f.write(private.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo))
with open(os.path.join(directory, 'source.sha256'), 'wb') as f:
    f.write(message)
with open(os.path.join(directory, 'source.sha256.sig'), 'wb') as f:
    f.write(private.sign(message))
PY

if [[ "$(openssl pkeyutl -help 2>&1 || true)" == *-rawin* ]]; then
  echo 'This test requires legacy OpenSSL without pkeyutl -rawin' >&2
  exit 1
fi

for script in bootstrap.sh update.sh; do
  # Test the actual standalone verifier from both entry points.
  source <(sed -n '/^verify_release_signature() {/,/^}/p' "$ROOT/$script")
  verify_release_signature "$TMP/public.pem" "$TMP/source.sha256" "$TMP/source.sha256.sig"
  printf 'tampered\n' >> "$TMP/source.sha256"
  if verify_release_signature "$TMP/public.pem" "$TMP/source.sha256" "$TMP/source.sha256.sig"; then
    echo "$script accepted a modified checksum manifest" >&2
    exit 1
  fi
  sed -i '$d' "$TMP/source.sha256"
done
echo 'legacy-release-verify: PASS'
