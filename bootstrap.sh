#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VMT_GITHUB_REPO:-nbbk/vps-toolkit}"
REF="${VMT_VERSION:-}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 root 运行，例如：curl ... | sudo bash" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装" >&2; exit 1; }

if [ -n "$REF" ]; then
  [[ "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VMT_VERSION 必须是 vX.Y.Z 正式版本" >&2; exit 1; }
else
  REF="$(curl -fsSL --proto '=https' --tlsv1.2 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
  [[ "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "无法取得有效正式版本，安装已安全停止" >&2; exit 1; }
fi
ASSET="vps-toolkit-${REF}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${REF}/${ASSET}"
printf '安装来源：%s (%s)\n' "$REPO" "$REF"
curl --fail --location --proto '=https' --tlsv1.2 "$URL" -o "$TMP/source.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 "${URL}.sha256" -o "$TMP/source.sha256"
EXPECTED="$(awk 'NF{print $1;exit}' "$TMP/source.sha256")"; ACTUAL="$(sha256sum "$TMP/source.tar.gz" | awk '{print $1}')"
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ && "${EXPECTED,,}" = "$ACTUAL" ]] || { echo "Release SHA-256 校验失败" >&2; exit 1; }
echo "Release SHA-256 校验通过"
tar -xzf "$TMP/source.tar.gz" -C "$TMP"
SOURCE_DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/install.sh" ]; then echo "下载包结构异常" >&2; exit 1; fi
bash "$SOURCE_DIR/install.sh"
