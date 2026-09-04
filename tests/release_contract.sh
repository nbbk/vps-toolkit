#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
bash "$ROOT/scripts/build_release.sh" "$TMP" >/dev/null
version="$(sed -nE 's/^VERSION="([0-9.]+)"$/\1/p' "$ROOT/vps-tool.sh" | head -n1)"
archive="$TMP/vps-toolkit-v${version}.tar.gz"; checksum="$archive.sha256"
[ -s "$archive" ] && [ -s "$checksum" ]
(cd "$TMP" && sha256sum -c "$(basename "$checksum")")
tar -tzf "$archive" | grep 'vps-toolkit/vps-tool.sh' >/dev/null
tar -tzf "$archive" | grep 'vps-toolkit/config/extensions.tsv' >/dev/null
tar -tzf "$archive" | grep 'vps-toolkit/config/release-signing-public.pem' >/dev/null
if git -c "safe.directory=$ROOT" -C "$ROOT" rev-parse --verify 'v2.2.0^{commit}' >/dev/null 2>&1; then
  tagged_out="$TMP/tagged"
  VMT_RELEASE_TAG=v2.2.0 VMT_RELEASE_REF=v2.2.0 bash "$ROOT/scripts/build_release.sh" "$tagged_out" >/dev/null
  tar -xOf "$tagged_out/vps-toolkit-v2.2.0.tar.gz" vps-toolkit/install.sh | head -n 2 | grep -q '^set -Eeuo pipefail$'
fi

command -v openssl >/dev/null 2>&1 || { echo 'openssl is required for release contract tests' >&2; exit 1; }
test_key="$TMP/test-release-key.pem"; test_public="$TMP/test-release-public.pem"; signature="$checksum.sig"
openssl genpkey -algorithm Ed25519 -out "$test_key" >/dev/null 2>&1
openssl pkey -in "$test_key" -pubout -out "$test_public" >/dev/null 2>&1
openssl pkeyutl -sign -rawin -inkey "$test_key" -in "$checksum" -out "$signature"
openssl pkeyutl -verify -pubin -inkey "$test_public" -rawin -in "$checksum" -sigfile "$signature" >/dev/null
cp "$checksum" "$TMP/tampered.sha256"; printf '#tampered\n' >> "$TMP/tampered.sha256"
if openssl pkeyutl -verify -pubin -inkey "$test_public" -rawin -in "$TMP/tampered.sha256" -sigfile "$signature" >/dev/null 2>&1; then
  echo 'tampered checksum manifest unexpectedly passed signature verification' >&2
  exit 1
fi
grep -q 'pkeyutl -verify' "$ROOT/bootstrap.sh"
grep -q 'pkeyutl -verify' "$ROOT/update.sh"
echo 'release-contract: PASS'
