#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VMT_GITHUB_REPO:-nbbk/vps-toolkit}"
CHANNEL="${VMT_UPDATE_CHANNEL:-stable}"
REF="${VMT_VERSION_REF:-main}"
DEST="${VMT_INSTALL_DIR:-/opt/vps-toolkit}"
STATE_DIR="${VMT_STATE_DIR:-/var/lib/vps-toolkit}"
TMP="$(mktemp -d)"
BACKUP="$STATE_DIR/update-backups/vps-toolkit-$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}.tar.gz"
UPDATE_LOCK_DIR="${VMT_LOCK_DIR:-/run/lock}"
UPDATE_LOCK_OWNER=""
UPDATE_LOCK_FALLBACK=""
update_lock_release() {
  if [ -n "${UPDATE_LOCK_FD:-}" ]; then flock -u "$UPDATE_LOCK_FD" 2>/dev/null || true; exec {UPDATE_LOCK_FD}>&-; unset UPDATE_LOCK_FD; fi
  [ -z "$UPDATE_LOCK_OWNER" ] || rm -f -- "$UPDATE_LOCK_OWNER"
  [ -z "$UPDATE_LOCK_FALLBACK" ] || rmdir "$UPDATE_LOCK_FALLBACK" 2>/dev/null || true
  UPDATE_LOCK_OWNER=""; UPDATE_LOCK_FALLBACK=""
}
cleanup() {
  rm -rf -- "$TMP"
  update_lock_release
}
trap cleanup EXIT

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "请使用：sudo nb --update" >&2; exit 1; }
case "$DEST" in /|/opt|/usr|/usr/local|/var|"") echo "拒绝使用不安全的安装目录：$DEST" >&2; exit 1;; esac
case "$DEST" in /*) ;; *) echo "安装目录必须是绝对路径" >&2; exit 1;; esac
command -v tar >/dev/null 2>&1 || { echo "缺少 tar，请先安装" >&2; exit 1; }

mkdir -p "$UPDATE_LOCK_DIR"
if command -v flock >/dev/null 2>&1; then
  exec {UPDATE_LOCK_FD}>"$UPDATE_LOCK_DIR/vps-toolkit.lock"
  flock -n "$UPDATE_LOCK_FD" || { echo "另一项工具修改或更新正在执行" >&2; exit 1; }
  UPDATE_LOCK_OWNER="$UPDATE_LOCK_DIR/vps-toolkit.lock.owner"
else
  fallback_candidate="$UPDATE_LOCK_DIR/vps-toolkit.lock.d"
  owner_candidate="$fallback_candidate/owner"
  if ! mkdir "$fallback_candidate" 2>/dev/null; then
    lock_pid="$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "$owner_candidate" 2>/dev/null)"
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then echo "另一项工具修改或更新正在执行" >&2; exit 1; fi
    rm -f -- "$owner_candidate"; rmdir "$fallback_candidate" 2>/dev/null || { echo "无法清理遗留更新锁" >&2; exit 1; }
    mkdir "$fallback_candidate"
  fi
  UPDATE_LOCK_FALLBACK="$fallback_candidate"; UPDATE_LOCK_OWNER="$owner_candidate"
fi
printf 'pid=%s action=update started=%s\n' "$$" "$(date -Is)" >"$UPDATE_LOCK_OWNER"

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
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

with open(sys.argv[1], 'rb') as f:
    key = serialization.load_pem_public_key(f.read())
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

version_from_script() {
  sed -nE 's/^VERSION="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$1" | head -n 1
}

version_lt() {
  local IFS=. i left right
  local -a a b
  read -r -a a <<<"$1"; read -r -a b <<<"$2"
  for i in 0 1 2; do
    left=$((10#${a[$i]})); right=$((10#${b[$i]}))
    [ "$left" -lt "$right" ] && return 0
    [ "$left" -gt "$right" ] && return 1
  done
  return 1
}

rollback_update() {
  local backup rollback_version answer restore_stage restore_dir prepared current_hold pre_rollback
  backup="$(find "$STATE_DIR/update-backups" -maxdepth 1 -type f -name 'vps-toolkit-*.tar.gz' -print 2>/dev/null | sort -r | head -n1)"
  [ -f "$backup" ] || { echo "没有可用的版本备份" >&2; exit 1; }
  rollback_version="$(tar -xOf "$backup" "$(basename "$DEST")/vps-tool.sh" 2>/dev/null | sed -nE 's/^VERSION="([0-9.]+)"$/\1/p' | head -n1)"
  [ -n "$rollback_version" ] || { echo "备份结构或版本号无效" >&2; exit 1; }
  printf '当前安装：%s\n准备恢复：%s\n备份文件：%s\n' "${current:-unknown}" "$rollback_version" "$backup"
  if [ "${VMT_ASSUME_YES:-0}" = 1 ]; then answer=y; else read -r -p "确认回滚？[y/N]: " answer; fi
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }
  restore_stage="$TMP/rollback"; mkdir -p "$restore_stage"
  tar -xzf "$backup" -C "$restore_stage" || { echo "回滚包解压失败，当前版本未改动" >&2; exit 1; }
  restore_dir="$restore_stage/$(basename "$DEST")"
  [ "$(version_from_script "$restore_dir/vps-tool.sh")" = "$rollback_version" ] || { echo "回滚包验证失败，当前版本未改动" >&2; exit 1; }
  prepared="${DEST}.rollback-new.$$"
  [ ! -e "$prepared" ] || { echo "临时回滚目录已存在：$prepared" >&2; exit 1; }
  cp -a -- "$restore_dir" "$prepared" || { rm -rf -- "$prepared"; echo "准备回滚目录失败，当前版本未改动" >&2; exit 1; }
  [ "$(version_from_script "$prepared/vps-tool.sh")" = "$rollback_version" ] || { rm -rf -- "$prepared"; echo "准备回滚目录验证失败，当前版本未改动" >&2; exit 1; }
  mkdir -p "$STATE_DIR/update-backups"
  pre_rollback="$STATE_DIR/update-backups/pre-rollback-$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}.tar.gz"
  [ ! -d "$DEST" ] || tar -czf "$pre_rollback" -C "$(dirname "$DEST")" "$(basename "$DEST")"
  current_hold="${DEST}.rollback-current.$$"
  [ ! -e "$current_hold" ] || { echo "临时回滚目录已存在：$current_hold" >&2; exit 1; }
  [ ! -d "$DEST" ] || mv -- "$DEST" "$current_hold"
  if ! mv -- "$prepared" "$DEST"; then
    rm -rf -- "$prepared"
    if [ -d "$current_hold" ] && ! mv -- "$current_hold" "$DEST"; then echo "切换与自动恢复均失败；当前版本备份：$pre_rollback" >&2; exit 1; fi
    echo "切换回滚版本失败，已恢复当前版本" >&2; exit 1
  fi
  [ ! -d "$current_hold" ] || rm -rf -- "$current_hold"
  [ "$(version_from_script "$DEST/vps-tool.sh")" = "$rollback_version" ] || { echo "回滚后验证失败；当前版本备份：$pre_rollback" >&2; exit 1; }
  printf '回滚成功：%s\n' "$rollback_version"; wait_before_launch; launch_installed; exit 0
}

launch_installed() {
  [ "${VMT_NO_LAUNCH:-0}" = 1 ] && return 0
  update_lock_release
  exec bash "$DEST/vps-tool.sh"
}

wait_before_launch() {
  if [ -t 0 ] && [ -t 1 ] && [ "${VMT_NO_LAUNCH:-0}" != 1 ]; then
    printf '\n'
    read -r -p "按回车进入新版本..." _update_continue || true
  fi
}

current="unknown"
[ -f "$DEST/vps-tool.sh" ] && current="$(version_from_script "$DEST/vps-tool.sh")"
current="${current:-unknown}"
if [ "${VMT_DRY_RUN:-0}" = 1 ]; then
  if [ "${1:-}" = --rollback ]; then printf '[DRY-RUN] 将选择最近一次更新备份并恢复到 %s；不会修改系统。\n' "$DEST"
  else printf '[DRY-RUN] 将检查更新、校验正式版资产、备份 %s、安装并验证版本；不会修改系统。\n' "$DEST"; fi
  exit 0
fi
if [ "${1:-}" = --rollback ]; then rollback_update; fi
if [ -n "${VMT_UPDATE_ARCHIVE:-}" ]; then
  url="local-test-archive"; REF="local"
else
  command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装" >&2; exit 1; }
  if [ "$CHANNEL" = stable ]; then
    release_tag="$(curl -fsSL --proto '=https' --tlsv1.2 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
    [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "无法取得有效正式版本；稳定通道已安全停止，不会回退 main" >&2; exit 1; }
    asset_name="vps-toolkit-${release_tag}.tar.gz"; url="https://github.com/${REPO}/releases/download/${release_tag}/${asset_name}"; checksum_url="${url}.sha256"; signature_url="${checksum_url}.sig"; REF="$release_tag"
  elif [ "$CHANNEL" = testing ]; then url="https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"
  else echo "更新通道只能是 stable 或 testing" >&2; exit 1; fi
fi

printf '[1/5] 正在检查更新：%s (%s)\n' "$REPO" "$REF"
if [ -n "${VMT_UPDATE_ARCHIVE:-}" ]; then
  [ -f "$VMT_UPDATE_ARCHIVE" ] || { echo "测试更新包不存在" >&2; exit 1; }
  cp "$VMT_UPDATE_ARCHIVE" "$TMP/source.tar.gz"
else
  curl --fail --location --proto '=https' --tlsv1.2 "$url" -o "$TMP/source.tar.gz"
  if [ "$CHANNEL" = stable ]; then
    command -v openssl >/dev/null 2>&1 || { echo "稳定版验签需要 openssl，请先安装后重试" >&2; exit 1; }
    release_public_key="$DEST/config/release-signing-public.pem"
    [ -s "$release_public_key" ] || { echo "缺少已安装的 Release 验签公钥：$release_public_key" >&2; exit 1; }
    curl --fail --location --proto '=https' --tlsv1.2 "$checksum_url" -o "$TMP/source.sha256"
    curl --fail --location --proto '=https' --tlsv1.2 "$signature_url" -o "$TMP/source.sha256.sig"
    if ! verify_release_signature "$release_public_key" "$TMP/source.sha256" "$TMP/source.sha256.sig"; then
      echo "Release Ed25519 签名校验失败，拒绝安装" >&2
      exit 1
    fi
    printf 'Release Ed25519 签名校验通过。\n'
    expected_sha="$(awk 'NF{print $1;exit}' "$TMP/source.sha256")"; actual_sha="$(sha256sum "$TMP/source.tar.gz" | awk '{print $1}')"
    [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ && "${expected_sha,,}" = "$actual_sha" ]] || { echo "Release SHA-256 校验失败，拒绝安装" >&2; exit 1; }
    printf 'Release SHA-256 校验通过。\n'
  fi
fi
printf '[2/5] 下载包 SHA-256: '; sha256sum "$TMP/source.tar.gz"
tar -xzf "$TMP/source.tar.gz" -C "$TMP"
source_dir="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

required=(vps-tool.sh install.sh uninstall.sh update.sh bootstrap.sh config/sources.tsv config/extensions.tsv config/release-signing-public.pem lib/core.sh lib/system.sh lib/firewall.sh lib/ssh.sh lib/docker.sh lib/oracle.sh lib/tools.sh lib/reinstall.sh lib/testsuite.sh lib/web.sh lib/basics.sh lib/workspace.sh lib/backup.sh lib/diagnostics.sh lib/security.sh lib/extensions.sh lib/baseline.sh lib/cli.sh)
for file in "${required[@]}"; do
  [ -f "$source_dir/$file" ] || { echo "更新包缺少文件：$file" >&2; exit 1; }
done

for file in "$source_dir"/*.sh "$source_dir"/lib/*.sh "$source_dir"/tests/*.sh; do
  [ -f "$file" ] && bash -n "$file"
done
printf '[3/5] 文件结构与 Shell 语法检查通过\n'

latest="$(version_from_script "$source_dir/vps-tool.sh")"
[ -n "$latest" ] || { echo "无法识别远程版本" >&2; exit 1; }
printf '当前版本：%s\n远程版本：%s\n' "$current" "$latest"

if [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version_lt "$latest" "$current" && [ "${VMT_ALLOW_DOWNGRADE:-0}" != 1 ]; then
  echo "检测到降级 $current -> $latest，已拒绝。需要时请使用 nb update rollback。" >&2; exit 1
fi

if [ "$current" = "$latest" ] && [ "${VMT_FORCE_UPDATE:-0}" != 1 ]; then
  printf '已经是最新版本。\n'
  printf '已安装版本：%s\n' "$current"
  wait_before_launch
  launch_installed
  exit 0
fi

if [ "${VMT_ASSUME_YES:-0}" = 1 ]; then answer=y; else read -r -p "确认升级到 $latest？[y/N]: " answer; fi
[[ "$answer" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

mkdir -p "$(dirname "$BACKUP")"
printf '[4/5] 正在备份并安装\n'
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

printf '\n--------------------------------------------------------\n'
printf '[5/5] 更新完成\n'
printf '旧版本：%s\n' "$current"
printf '新版本：%s\n' "$installed"
[ -f "$BACKUP" ] && printf '备份位置：%s\n' "$BACKUP"
printf '安装目录：%s\n' "$DEST"
printf '验证结果：版本号和脚本语法检查通过\n'
printf '%s\n' '--------------------------------------------------------'
if [ "${VMT_NO_LAUNCH:-0}" != 1 ]; then
  wait_before_launch
  launch_installed
fi
