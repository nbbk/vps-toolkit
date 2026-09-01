#!/usr/bin/env bash

C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_CYAN='\033[36m'; C_RESET='\033[0m'
STATE_DIR="${VMT_STATE_DIR:-/var/lib/vps-toolkit}"
BACKUP_DIR="${VMT_BACKUP_DIR:-$STATE_DIR/backups}"
LOG_FILE="${VMT_LOG_FILE:-/var/log/vps-toolkit.log}"
DRY_RUN="${VMT_DRY_RUN:-0}"

say() { printf '%b\n' "$*"; }
ok() { say "${C_GREEN}[OK]${C_RESET} $*"; }
warn() { say "${C_YELLOW}[提示]${C_RESET} $*"; }
die() { say "${C_RED}[错误]${C_RESET} $*" >&2; return 1; }
pause() { read -r -p "按回车继续..." _ || true; }
clear_screen() { [ -t 1 ] && clear || true; }
on_error() { say "${C_RED}操作失败（行 $1，状态 $2）。请查看日志：$LOG_FILE${C_RESET}" >&2; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "请使用 root 运行：sudo bash $VMT_BASE_DIR/vps-tool.sh"
    exit 1
  fi
  mkdir -p "$STATE_DIR" "$BACKUP_DIR"
  touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
}

log() { printf '%s [%s] %s\n' "$(date -Is)" "${1:-INFO}" "${*:2}" >>"$LOG_FILE"; }
run() {
  log CMD "$(printf '%q ' "$@")"
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] '; printf '%q ' "$@"; printf '\n'; return 0; fi
  "$@" 2>&1 | tee -a "$LOG_FILE"
}
confirm() {
  local prompt="${1:-确认继续？}" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
confirm_phrase() {
  local phrase="$1" prompt="$2" answer
  read -r -p "$prompt（输入 $phrase 确认）: " answer
  [ "$answer" = "$phrase" ]
}
valid_port() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_size_mb() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 128 ] && [ "$1" -le 262144 ]; }

detect_os() {
  [ -r /etc/os-release ] || die "无法识别系统"
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID,,}"; OS_LIKE="${ID_LIKE:-}"; OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
  case "$OS_ID $OS_LIKE" in
    *debian*|*ubuntu*) PKG_FAMILY=apt ;;
    *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) command -v dnf >/dev/null && PKG_FAMILY=dnf || PKG_FAMILY=yum ;;
    *alpine*) PKG_FAMILY=apk ;;
    *) die "暂不支持：$OS_PRETTY" ;;
  esac
}

pkg_install() {
  case "$PKG_FAMILY" in
    apt) run apt-get update; run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf|yum) run "$PKG_FAMILY" install -y "$@" ;;
    apk) run apk add "$@" ;;
  esac
}

service_restart() {
  local name
  for name in "$@"; do
    if command -v systemctl >/dev/null && systemctl list-unit-files "$name.service" >/dev/null 2>&1; then run systemctl restart "$name"; return; fi
    if command -v rc-service >/dev/null && rc-service "$name" status >/dev/null 2>&1; then run rc-service "$name" restart; return; fi
  done
  die "找不到服务：$*"
}
