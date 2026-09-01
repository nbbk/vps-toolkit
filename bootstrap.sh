#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VMT_GITHUB_REPO:-nbbk/vps-toolkit}"
REF="${VMT_VERSION:-main}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 root 运行，例如：curl ... | sudo bash" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装" >&2; exit 1; }

URL="https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 "$URL" -o "$TMP/source.tar.gz"
tar -xzf "$TMP/source.tar.gz" -C "$TMP"
SOURCE_DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/install.sh" ]; then echo "下载包结构异常" >&2; exit 1; fi
bash "$SOURCE_DIR/install.sh"
