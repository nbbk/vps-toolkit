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
echo 'release-contract: PASS'
