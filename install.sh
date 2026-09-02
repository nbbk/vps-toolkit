#!/usr/bin/env bash
set -Eeuo pipefail
SRC="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
BIN_DIR="${VMT_BIN_DIR:-/usr/local/bin}"
[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 sudo bash install.sh" >&2; exit 1; }
install -d -m 0755 "$DEST" "$DEST/lib" "$DEST/config" "$DEST/docs"
install -d -m 0755 "$BIN_DIR"
install -m 0755 "$SRC/vps-tool.sh" "$DEST/vps-tool.sh"
install -m 0755 "$SRC/uninstall.sh" "$DEST/uninstall.sh"
install -m 0755 "$SRC/update.sh" "$DEST/update.sh"
install -m 0644 "$SRC"/lib/*.sh "$DEST/lib/"
install -m 0644 "$SRC/config/sources.tsv" "$DEST/config/sources.tsv"
install -m 0644 "$SRC/config/extensions.tsv" "$DEST/config/extensions.tsv"
install -m 0644 "$SRC/config/release-signing-public.pem" "$DEST/config/release-signing-public.pem"
install -m 0644 "$SRC/CHANGELOG.md" "$SRC/README.md" "$DEST/"
install -m 0644 "$SRC/docs/FUNCTIONS.md" "$DEST/docs/FUNCTIONS.md"
ln -sfn "$DEST/vps-tool.sh" "$BIN_DIR/vps-tool"
ln -sfn "$DEST/vps-tool.sh" "$BIN_DIR/nb"
existing_n_target="$(readlink "$BIN_DIR/n" 2>/dev/null || true)"
if [ "$existing_n_target" = "$DEST/vps-tool.sh" ]; then
  ln -sfn "$DEST/vps-tool.sh" "$BIN_DIR/n"
  SHORTCUTS="nb、n"
elif [ ! -e "$BIN_DIR/n" ] && [ ! -L "$BIN_DIR/n" ] && ! command -v n >/dev/null 2>&1; then
  ln -s "$DEST/vps-tool.sh" "$BIN_DIR/n"
  SHORTCUTS="nb、n"
else
  SHORTCUTS="nb（n 已被其他程序占用，未覆盖）"
fi
printf '安装完成。运行：sudo nb（完整命令：sudo vps-tool）\n快捷命令：%s\n' "$SHORTCUTS"
