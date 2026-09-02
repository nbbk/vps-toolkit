#!/usr/bin/env bash
set -Euo pipefail

VERSION="2.3.0"
TOOL_VERSION="$VERSION"
SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED_PATH="$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null || true)"
  [ -n "$RESOLVED_PATH" ] && SCRIPT_PATH="$RESOLVED_PATH"
fi
BASE_DIR="$(CDPATH='' cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
export VMT_BASE_DIR="$BASE_DIR"

for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do
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

if [ "$#" -gt 0 ]; then
  case "${1:-}" in help|--help|-h|version|--version|-v) cli_dispatch "$@"; exit $?;; esac
  require_root
  detect_os
  cli_dispatch "$@"
  exit $?
fi

main_menu() {
  require_root
  detect_os
  while true; do
    clear_screen
    cat <<EOF
${C_CYAN}VPS 私人管理工具 v${TOOL_VERSION}${C_RESET}  ${OS_PRETTY:-unknown}
安全默认：无遥测｜不保存密码｜高风险操作先备份/校验
$(dashboard_summary)
--------------------------------------------------------
 1. 系统信息              2. 系统更新
 3. 系统清理              4. 开放端口
 5. 关闭端口              6. 查看端口/防火墙
 7. BBR 管理              8. 修改虚拟内存
 9. Docker 管理          10. 修改登录密码
11. 修改 SSH 端口        12. SSH 安全检查
13. 扩展中心            14. 查看操作日志
15. 检查并更新本工具      16. 卸载本工具
17. 系统工具箱            18. 配置备份中心
19. 开放全部端口          20. 撤销全部端口开放
21. 兼容性诊断/报告       22. 安全体检
23. 基础工具
24. 后台工作区
25. 系统状态基线          26. 搜索功能
 0. 退出
--------------------------------------------------------
EOF
    read -r -p "请选择: " choice
    action_start "menu:$choice"
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
      13) extensions_menu ;;
      14) less "$LOG_FILE" 2>/dev/null || true ;;
      15) exec bash "$BASE_DIR/update.sh" ;;
      16) bash "$BASE_DIR/uninstall.sh"; exit 0 ;;
      17) system_tools_menu ;;
      18) backup_center_menu ;;
      19) firewall_open_all ;;
      20) firewall_restore_default ;;
      21) diagnostics_menu ;;
      22) security_audit ;;
      23) basics_menu ;;
      24) workspace_menu ;;
      25) baseline_menu ;;
      26) feature_search ;;
      0) exit 0 ;;
      *) warn "无效选择" ;;
    esac
    pause
  done
}

main_menu "$@"
