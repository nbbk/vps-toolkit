#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VMT_GITHUB_REPO:-nbbk/vps-toolkit}"
REF="${VMT_VERSION_REF:-main}"
DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
STATE_DIR="${VMT_STATE_DIR:-/var/lib/vps-toolkit}"
TMP="$(mktemp -d)"
BACKUP="$STATE_DIR/update-backups/vps-toolkit-$(date +%Y%m%d-%H%M%S).tar.gz"
trap 'rm -rf -- "$TMP"' EXIT

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用：sudo nb --update" >&2; exit 1; }
case "$DEST" in /|/opt|/usr|/usr/local|/var|"") echo "拒绝使用不安全的安装目录：$DEST" >&2; exit 1;; esac
case "$DEST" in /*) ;; *) echo "安装目录必须是绝对路径" >&2; exit 1;; esac
command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "缺少 tar，请先安装" >&2; exit 1; }

version_from_script() {
  sed -nE 's/^VERSION="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$1" | head -n 1
}

current="unknown"
[ -f "$DEST/vps-tool.sh" ] && current="$(version_from_script "$DEST/vps-tool.sh")"
current="${current:-unknown}"
url="https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"

printf '正在检查更新：%s (%s)\n' "$REPO" "$REF"
curl --fail --location --proto '=https' --tlsv1.2 "$url" -o "$TMP/source.tar.gz"
printf '下载包 SHA-256: '; sha256sum "$TMP/source.tar.gz"
tar -xzf "$TMP/source.tar.gz" -C "$TMP"
source_dir="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

required=(vps-tool.sh install.sh uninstall.sh update.sh bootstrap.sh lib/core.sh lib/system.sh lib/firewall.sh lib/ssh.sh lib/docker.sh lib/oracle.sh)
for file in "${required[@]}"; do
  [ -f "$source_dir/$file" ] || { echo "更新包缺少文件：$file" >&2; exit 1; }
done

for file in "$source_dir"/*.sh "$source_dir"/lib/*.sh "$source_dir"/tests/*.sh; do
  [ -f "$file" ] && bash -n "$file"
done

latest="$(version_from_script "$source_dir/vps-tool.sh")"
[ -n "$latest" ] || { echo "无法识别远程版本" >&2; exit 1; }
printf '当前版本：%s\n远程版本：%s\n' "$current" "$latest"

if [ "$current" = "$latest" ] && [ "${VMT_FORCE_UPDATE:-0}" != 1 ]; then
  printf '已经是最新版本。\n'; exit 0
fi

read -r -p "确认升级到 $latest？输入 UPDATE 继续: " answer
[ "$answer" = UPDATE ] || { echo "已取消"; exit 0; }

mkdir -p "$(dirname "$BACKUP")"
if [ -d "$DEST" ]; then tar -czf "$BACKUP" -C "$(dirname "$DEST")" "$(basename "$DEST")"; fi

if ! VMT_INSTALL_DIR="$DEST" bash "$source_dir/install.sh"; then
  echo "安装失败，正在恢复旧版本..." >&2
  if [ -f "$BACKUP" ]; then
    rm -rf -- "$DEST"
    tar -xzf "$BACKUP" -C "$(dirname "$DEST")"
  fi
  exit 1
fi

installed="$(version_from_script "$DEST/vps-tool.sh")"
if [ "$installed" != "$latest" ] || ! bash -n "$DEST/vps-tool.sh"; then
  echo "升级后验证失败，正在恢复旧版本..." >&2
  rm -rf -- "$DEST"
  [ -f "$BACKUP" ] && tar -xzf "$BACKUP" -C "$(dirname "$DEST")"
  exit 1
fi

printf '升级成功：%s -> %s\n' "$current" "$latest"
[ -f "$BACKUP" ] && printf '旧版本备份：%s\n' "$BACKUP"
