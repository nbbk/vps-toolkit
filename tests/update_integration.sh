#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
DEST="$TMP/install/vps-toolkit"
STATE="$TMP/state"
BIN="$TMP/bin"
ARCHIVE="$TMP/release.tar.gz"
mkdir -p "$DEST" "$STATE" "$BIN" "$TMP/release/vps-toolkit-main"

cp -a "$ROOT/." "$TMP/release/vps-toolkit-main/"
tar -czf "$ARCHIVE" -C "$TMP/release" vps-toolkit-main

cat >"$DEST/vps-tool.sh" <<'EOF'
#!/usr/bin/env bash
VERSION="0.0.1"
EOF
chmod 755 "$DEST/vps-tool.sh"

VMT_INSTALL_DIR="$DEST" VMT_STATE_DIR="$STATE" VMT_BIN_DIR="$BIN" VMT_UPDATE_ARCHIVE="$ARCHIVE" \
  VMT_ASSUME_YES=1 VMT_NO_LAUNCH=1 bash "$ROOT/update.sh"

expected="$(sed -nE 's/^VERSION="([0-9.]+)"$/\1/p' "$ROOT/vps-tool.sh" | head -n1)"
installed="$(sed -nE 's/^VERSION="([0-9.]+)"$/\1/p' "$DEST/vps-tool.sh" | head -n1)"
[ "$installed" = "$expected" ] || { echo "version mismatch: $installed != $expected" >&2; exit 1; }
[ -x "$DEST/update.sh" ] && [ -f "$DEST/lib/core.sh" ]
[ -L "$BIN/nb" ] && [ "$(readlink "$BIN/nb")" = "$DEST/vps-tool.sh" ]
[ -L "$BIN/n" ] && [ "$(readlink "$BIN/n")" = "$DEST/vps-tool.sh" ]

# A subsequent update must recognize its own n shortcut instead of reporting it as occupied.
install_output="$(VMT_INSTALL_DIR="$DEST" VMT_BIN_DIR="$BIN" bash "$ROOT/install.sh")"
printf '%s\n' "$install_output" | grep -q '快捷命令：nb、n'
find "$STATE/update-backups" -name '*.tar.gz' -print -quit | grep -q .
echo "update-integration: PASS ($installed)"
