#!/usr/bin/env bash

C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
STATE_DIR="${VMT_STATE_DIR:-/var/lib/vps-toolkit}"
BACKUP_DIR="${VMT_BACKUP_DIR:-$STATE_DIR/backups}"
LOG_FILE="${VMT_LOG_FILE:-/var/log/vps-toolkit.log}"
DRY_RUN="${VMT_DRY_RUN:-0}"
CURRENT_ACTION="startup"
LOCK_DIR="${VMT_LOCK_DIR:-/run/lock}"

say() { printf '%b\n' "$*"; }
ok() { say "${C_GREEN}[OK]${C_RESET} $*"; }
warn() { say "${C_YELLOW}[提示]${C_RESET} $*"; }
die() { say "${C_RED}[错误]${C_RESET} $*" >&2; return 1; }
pause() { read -r -p "按回车继续..." _ || true; }
clear_screen() { if [ -t 1 ]; then clear; fi; }
ui_line() { printf '%b\n' "${C_CYAN}--------------------------------------------------------${C_RESET}"; }
ui_header() { clear_screen; ui_line; printf '%b\n' "${C_CYAN}  $*${C_RESET}"; ui_line; }
ui_item() { printf '  %b%-3s%b %s\n' "$C_CYAN" "$1" "$C_RESET" "$2"; }
ui_status() { if "$@" >/dev/null 2>&1; then printf '%b●%b' "$C_GREEN" "$C_RESET"; else printf '%b○%b' "$C_YELLOW" "$C_RESET"; fi; }
progress_step() { printf '%b[%s/%s]%b %s\n' "$C_CYAN" "$1" "$2" "$C_RESET" "$3"; }
on_error() {
  log ERROR "action=$CURRENT_ACTION line=$1 status=$2"
  say "${C_RED}操作失败｜功能：$CURRENT_ACTION｜行：$1｜状态：$2${C_RESET}" >&2
  say "日志：$LOG_FILE；可运行 sudo nb report 导出诊断报告" >&2
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "请使用 root 运行：sudo bash $VMT_BASE_DIR/vps-tool.sh"
    exit 1
  fi
  mkdir -p "$STATE_DIR" "$BACKUP_DIR"
  touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
}

log() { printf '%s [%s] [action=%s] %s\n' "$(date -Is)" "${1:-INFO}" "$CURRENT_ACTION" "${*:2}" >>"$LOG_FILE"; }
action_start() { CURRENT_ACTION="$1"; log INFO "start"; }
transaction_begin() {
  local module="$1" id
  operation_lock_acquire "$module" || return 1
  id="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}"; VMT_TRANSACTION_ID="$id"; VMT_TRANSACTION_FAILED=0
  mkdir -p "$STATE_DIR/transactions" || { operation_lock_release; VMT_TRANSACTION_ID=""; return 1; }
  if ! printf 'id=%s\nmodule=%s\nstarted=%s\nstatus=running\nversion=%s\n' "$id" "$module" "$(date -Is)" "$TOOL_VERSION" >"$STATE_DIR/transactions/$id"; then operation_lock_release; VMT_TRANSACTION_ID=""; return 1; fi
  chmod 600 "$STATE_DIR/transactions/$id" || { operation_lock_release; VMT_TRANSACTION_ID=""; return 1; }
  printf '%s\n' "$id" >>"$STATE_DIR/transaction-order" || { operation_lock_release; VMT_TRANSACTION_ID=""; return 1; }
  chmod 600 "$STATE_DIR/transaction-order"
  log INFO "transaction=$id begin module=$module"
}
transaction_note() {
  if [ -n "${VMT_TRANSACTION_ID:-}" ]; then
    printf '%s\n' "$*" >>"$STATE_DIR/transactions/$VMT_TRANSACTION_ID"
  fi
  return 0
}
transaction_finish() {
  local status="${1:-success}" file="$STATE_DIR/transactions/${VMT_TRANSACTION_ID:-none}"
  [ -f "$file" ] || return 0
  if [ "$status" = success ] && [ "${VMT_TRANSACTION_FAILED:-0}" = 1 ]; then status=failed; fi
  printf 'finished=%s\nfinal_status=%s\n' "$(date -Is)" "$status" >>"$file"
  log INFO "transaction=${VMT_TRANSACTION_ID:-none} finish status=$status"; VMT_TRANSACTION_ID=""; VMT_TRANSACTION_FAILED=0
  operation_lock_release
}
operation_lock_acquire() {
  local category="$1" lock_file owner_file owner_pid fallback_dir
  mkdir -p "$LOCK_DIR" || { die "无法创建操作锁目录：$LOCK_DIR"; return 1; }
  lock_file="$LOCK_DIR/vps-toolkit.lock"; owner_file="$lock_file.owner"
  if command -v flock >/dev/null 2>&1; then
    exec {VMT_LOCK_FD}>"$lock_file"
    if ! flock -n "$VMT_LOCK_FD"; then
      die "另一项修改正在执行：$(cat "$owner_file" 2>/dev/null || echo unknown)"; exec {VMT_LOCK_FD}>&-; unset VMT_LOCK_FD; return 1
    fi
  else
    fallback_dir="$LOCK_DIR/vps-toolkit.lock.d"; owner_file="$fallback_dir/owner"
    if ! mkdir "$fallback_dir" 2>/dev/null; then
      owner_pid="$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "$owner_file" 2>/dev/null)"
      if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then die "另一项修改正在执行：$(cat "$owner_file" 2>/dev/null || echo unknown)"; return 1; fi
      warn "清理上次异常退出遗留的操作锁"
      rm -f -- "$owner_file"; rmdir "$fallback_dir" 2>/dev/null || { die "无法清理遗留操作锁"; return 1; }
      mkdir "$fallback_dir" || return 1
    fi
    VMT_LOCK_FALLBACK_DIR="$fallback_dir"
  fi
  if ! printf 'pid=%s action=%s category=%s started=%s\n' "$$" "$CURRENT_ACTION" "$category" "$(date -Is)" >"$owner_file"; then operation_lock_release; die "无法写入操作锁"; return 1; fi
  VMT_LOCK_OWNER_FILE="$owner_file"
}
operation_lock_release() {
  if [ -n "${VMT_LOCK_FD:-}" ]; then flock -u "$VMT_LOCK_FD" 2>/dev/null || true; exec {VMT_LOCK_FD}>&-; unset VMT_LOCK_FD; fi
  [ -n "${VMT_LOCK_OWNER_FILE:-}" ] && rm -f -- "$VMT_LOCK_OWNER_FILE" || true
  if [ -n "${VMT_LOCK_FALLBACK_DIR:-}" ]; then rmdir "$VMT_LOCK_FALLBACK_DIR" 2>/dev/null || true; VMT_LOCK_FALLBACK_DIR=""; fi
  VMT_LOCK_OWNER_FILE=""
}
run() {
  local rc
  log CMD "$(printf '%q ' "$@")"
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] '; printf '%q ' "$@"; printf '\n'; return 0; fi
  "$@" 2>&1 | tee -a "$LOG_FILE"
  rc="${PIPESTATUS[0]}"
  if [ "$rc" -ne 0 ]; then
    log ERROR "命令状态 $rc: $(printf '%q ' "$@")"
    transaction_note "command_status=$rc command=$(printf '%q ' "$@")"
    VMT_TRANSACTION_FAILED=1
    return "$rc"
  fi
  return 0
}
submenu_pause() { printf '\n'; read -r -p "按回车返回当前菜单..." _ || true; }
confirm() {
  local prompt="${1:-确认继续？}" answer
  if [ "$DRY_RUN" = 1 ]; then printf '[预览模式] 自动确认：%s\n' "$prompt"; return 0; fi
  [ "${VMT_ASSUME_YES:-0}" = 1 ] && return 0
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
plan_only() {
  [ "$DRY_RUN" = 1 ] || return 1
  printf '%b[预览完成]%b 未修改系统。\n' "$C_GREEN" "$C_RESET"
  return 0
}
risk_preview() {
  local title="$1" changes="$2" rollback="$3"
  printf '\n%b[高风险操作] %s%b\n' "$C_YELLOW" "$title" "$C_RESET"
  printf '将要修改：%s\n%s\n' "$changes" "$rollback"
  confirm "确认继续？"
}
valid_port() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_size_mb() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 128 ] && [ "$1" -le 262144 ]; }

detect_os() {
  # /etc/os-release may define VERSION. Keep all standard fields local so it
  # cannot overwrite the toolkit version or other global configuration.
  # shellcheck disable=SC2034
  local NAME="" VERSION="" ID="" ID_LIKE="" PRETTY_NAME="" VERSION_ID="" \
    HOME_URL="" SUPPORT_URL="" BUG_REPORT_URL="" PRIVACY_POLICY_URL="" \
    VERSION_CODENAME="" UBUNTU_CODENAME="" LOGO="" ANSI_COLOR="" \
    CPE_NAME="" BUILD_ID="" VARIANT="" VARIANT_ID=""
  [ -r /etc/os-release ] || { die "无法识别系统"; return 1; }
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID,,}"; OS_LIKE="${ID_LIKE:-}"; OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
  # These globals are consumed by other sourced modules and CLI subprocesses.
  export OS_VERSION_ID="${VERSION_ID:-unknown}"
  export OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
  case "$OS_ID $OS_LIKE" in
    *debian*|*ubuntu*) PKG_FAMILY=apt ;;
    *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) command -v dnf >/dev/null && PKG_FAMILY=dnf || PKG_FAMILY=yum ;;
    *alpine*) PKG_FAMILY=apk ;;
    *) die "暂不支持：$OS_PRETTY" ;;
  esac
}

pkg_install() {
  case "$PKG_FAMILY" in
    apt) run apt-get update && run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
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
