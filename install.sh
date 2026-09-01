#!/usr/bin/env bash
set -Eeuo pipefail
SRC="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 sudo bash install.sh" >&2; exit 1; }
install -d -m 0755 "$DEST" "$DEST/lib"
install -m 0755 "$SRC/vps-tool.sh" "$DEST/vps-tool.sh"
install -m 0755 "$SRC/uninstall.sh" "$DEST/uninstall.sh"
install -m 0755 "$SRC/update.sh" "$DEST/update.sh"
install -m 0644 "$SRC"/lib/*.sh "$DEST/lib/"
ln -sfn "$DEST/vps-tool.sh" /usr/local/bin/vps-tool
ln -sfn "$DEST/vps-tool.sh" /usr/local/bin/nb
if [ ! -e /usr/local/bin/n ] && [ ! -L /usr/local/bin/n ] && ! command -v n >/dev/null 2>&1; then
  ln -s "$DEST/vps-tool.sh" /usr/local/bin/n
  SHORTCUTS="nb、n"
else
  SHORTCUTS="nb（n 已被其他程序占用，未覆盖）"
fi
printf '安装完成。运行：sudo nb（完整命令：sudo vps-tool）\n快捷命令：%s\n' "$SHORTCUTS"
