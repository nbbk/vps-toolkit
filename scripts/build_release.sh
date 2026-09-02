#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -nE 's/^VERSION="([0-9.]+)"$/\1/p' "$ROOT/vps-tool.sh" | head -n1)"
[ -n "$VERSION" ] || { echo "version not found" >&2; exit 1; }
EXPECTED_TAG="${VMT_RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
if [[ "$EXPECTED_TAG" = v* ]] && [ "$EXPECTED_TAG" != "v$VERSION" ]; then echo "release tag $EXPECTED_TAG does not match v$VERSION" >&2; exit 1; fi
OUT="${1:-$ROOT/dist}"; mkdir -p "$OUT"
NAME="vps-toolkit-v${VERSION}.tar.gz"
git -C "$ROOT" archive --format=tar.gz --prefix=vps-toolkit/ -o "$OUT/$NAME" HEAD
(cd "$OUT" && sha256sum "$NAME" >"$NAME.sha256")
printf '%s\n%s\n' "$OUT/$NAME" "$OUT/$NAME.sha256"
