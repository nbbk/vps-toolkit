#!/usr/bin/env bash
set -Eeuo pipefail
SRC="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 sudo bash install.sh" >&2; exit 1; }
install -d -m 0755 "$DEST" "$DEST/lib"
install -m 0755 "$SRC/vps-tool.sh" "$DEST/vps-tool.sh"
install -m 0755 "$SRC/uninstall.sh" "$DEST/uninstall.sh"
install -m 0644 "$SRC"/lib/*.sh "$DEST/lib/"
ln -sfn "$DEST/vps-tool.sh" /usr/local/bin/vps-tool
printf '安装完成。运行：sudo vps-tool\n'
