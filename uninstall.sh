#!/usr/bin/env bash
set -Eeuo pipefail

DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
STATE_DIR="${VMT_STATE_DIR:-/var/lib/vps-toolkit}"
LOG_FILE="${VMT_LOG_FILE:-/var/log/vps-toolkit.log}"
BIN_DIR="${VMT_BIN_DIR:-/usr/local/bin}"

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 sudo vps-tool --uninstall" >&2; exit 1; }
read -r -p "确认卸载 VPS 私人管理工具？[y/N]: " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

for shortcut in "$BIN_DIR/vps-tool" "$BIN_DIR/nb" "$BIN_DIR/n"; do
  if [ -L "$shortcut" ]; then
    target="$(readlink "$shortcut" 2>/dev/null || true)"
    [ "$target" = "$DEST/vps-tool.sh" ] && rm -f -- "$shortcut"
  fi
done
if [ -d "$DEST" ] && [ "$DEST" != / ] && [ "$DEST" != /opt ]; then rm -rf -- "$DEST"; fi

printf '程序文件已卸载。\n'
read -r -p "是否同时删除备份、外部下载和操作日志？[y/N]: " purge
if [[ "$purge" =~ ^[Yy]$ ]]; then
  if [ -d "$STATE_DIR" ] && [ "$STATE_DIR" != / ] && [ "$STATE_DIR" != /var ]; then rm -rf -- "$STATE_DIR"; fi
  rm -f -- "$LOG_FILE"
  printf '数据和日志已删除，无法恢复。系统配置修改不会被自动撤销。\n'
else
  printf '保留：%s 和 %s\n' "$STATE_DIR" "$LOG_FILE"
fi

printf '注意：防火墙、SSH、Swap、BBR、Docker 和系统软件包改动均予以保留。\n'
