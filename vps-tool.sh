#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.3.1"
SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED_PATH="$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null || true)"
  [ -n "$RESOLVED_PATH" ] && SCRIPT_PATH="$RESOLVED_PATH"
fi
BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
export VMT_BASE_DIR="$BASE_DIR"

for module in core system firewall ssh docker oracle; do
  # shellcheck source=/dev/null
  source "$BASE_DIR/lib/$module.sh"
done

if [ "${1:-}" = "--uninstall" ]; then
  require_root
  exec bash "$BASE_DIR/uninstall.sh"
fi
if [ "${1:-}" = "--update" ]; then
  require_root
  exec bash "$BASE_DIR/update.sh"
fi

main_menu() {
  require_root
  detect_os
  while true; do
    clear_screen
    cat <<EOF
${C_CYAN}VPS 私人管理工具 v${VERSION}${C_RESET}  ${OS_PRETTY:-unknown}
安全默认：无遥测｜不保存密码｜高风险操作先备份/校验
--------------------------------------------------------
 1. 系统信息              2. 系统更新
 3. 系统清理              4. 开放端口
 5. 关闭端口              6. 查看端口/防火墙
 7. BBR 管理              8. 修改虚拟内存
 9. Docker 管理          10. 修改登录密码
11. 修改 SSH 端口        12. SSH 安全检查
13. 甲骨文云工具合集     14. 查看操作日志
15. 检查并更新本工具      16. 卸载本工具
 0. 退出
--------------------------------------------------------
EOF
    read -r -p "请选择: " choice
    case "$choice" in
      1) system_info ;;
      2) system_update ;;
      3) system_clean ;;
      4) firewall_open_ui ;;
      5) firewall_close_ui ;;
      6) firewall_status ;;
      7) bbr_menu ;;
      8) swap_ui ;;
      9) docker_menu ;;
      10) change_password ;;
      11) change_ssh_port_ui ;;
      12) ssh_security_check ;;
      13) oracle_menu ;;
      14) less "$LOG_FILE" 2>/dev/null || true ;;
      15) bash "$BASE_DIR/update.sh" ;;
      16) bash "$BASE_DIR/uninstall.sh"; exit 0 ;;
      0) exit 0 ;;
      *) warn "无效选择" ;;
    esac
    pause
  done
}

trap 'on_error "$LINENO" "$?"' ERR
main_menu "$@"
