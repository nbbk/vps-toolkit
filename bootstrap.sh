#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VMT_GITHUB_REPO:-nbbk/vps-toolkit}"
REF="${VMT_VERSION:-}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用 root 运行，例如：curl ... | sudo bash" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装" >&2; exit 1; }
if ! command -v openssl >/dev/null 2>&1; then
  echo "正在从系统软件源安装 Release 验签依赖 openssl..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y openssl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y openssl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y openssl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache openssl
  else
    echo "无法自动安装 openssl，请先通过系统软件源安装后重试" >&2
    exit 1
  fi
fi
command -v openssl >/dev/null 2>&1 || { echo "openssl 安装失败，无法验证 Release 签名" >&2; exit 1; }

verify_release_signature() {
  local public_key="$1" checksum="$2" signature="$3" error_log="$TMP/verify-error.log"
  if [[ "$(openssl pkeyutl -help 2>&1 || true)" == *-rawin* ]]; then
    if openssl pkeyutl -verify -pubin -inkey "$public_key" -rawin -in "$checksum" -sigfile "$signature" >"$error_log" 2>&1; then
      return 0
    fi
    echo "OpenSSL 验签失败：$(cat "$error_log")" >&2
    return 1
  fi
  echo "当前 $(openssl version) 不支持 pkeyutl -rawin，使用 Python Ed25519 验签" >&2
  local python_bin="/usr/bin/python3"
  [ -x "$python_bin" ] || python_bin="$(command -v python3 || true)"
  if [ -z "$python_bin" ] || ! "$python_bin" -c 'import cryptography' >/dev/null 2>&1; then
    echo "缺少兼容验签依赖，正在从系统软件源安装 python3-cryptography..." >&2
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python3-cryptography
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y python3-cryptography
    elif command -v yum >/dev/null 2>&1; then
      yum install -y python3-cryptography
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache py3-cryptography
    else
      echo "无法自动安装 python3-cryptography，安装已安全停止" >&2
      return 1
    fi || return 1
  fi
  [ -x /usr/bin/python3 ] && python_bin=/usr/bin/python3
  "$python_bin" - "$public_key" "$checksum" "$signature" <<'PY'
import sys
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

with open(sys.argv[1], 'rb') as f:
    key = serialization.load_pem_public_key(f.read(), backend=default_backend())
if not isinstance(key, Ed25519PublicKey):
    raise SystemExit('Release 公钥不是 Ed25519')
with open(sys.argv[2], 'rb') as f:
    message = f.read()
with open(sys.argv[3], 'rb') as f:
    signature = f.read()
try:
    key.verify(signature, message)
except Exception as exc:
    raise SystemExit('Release Ed25519 签名不匹配：' + str(exc))
PY
}

cat >"$TMP/release-signing-public.pem" <<'RELEASE_PUBLIC_KEY'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAjHjZxf3LAYs4yjubFeka+Do3XEjt/H+7OLNsdhQx5mU=
-----END PUBLIC KEY-----
RELEASE_PUBLIC_KEY

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
curl --fail --location --proto '=https' --tlsv1.2 "${URL}.sha256.sig" -o "$TMP/source.sha256.sig"
if ! verify_release_signature "$TMP/release-signing-public.pem" "$TMP/source.sha256" "$TMP/source.sha256.sig"; then
  echo "Release Ed25519 签名校验失败，安装已安全停止" >&2
  exit 1
fi
echo "Release Ed25519 签名校验通过"
EXPECTED="$(awk 'NF{print $1;exit}' "$TMP/source.sha256")"; ACTUAL="$(sha256sum "$TMP/source.tar.gz" | awk '{print $1}')"
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ && "${EXPECTED,,}" = "$ACTUAL" ]] || { echo "Release SHA-256 校验失败" >&2; exit 1; }
echo "Release SHA-256 校验通过"
tar -xzf "$TMP/source.tar.gz" -C "$TMP"
SOURCE_DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/install.sh" ]; then echo "下载包结构异常" >&2; exit 1; fi
bash "$SOURCE_DIR/install.sh"
