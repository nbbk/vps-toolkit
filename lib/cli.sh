#!/usr/bin/env bash

cli_usage() {
  cat <<'EOF'
用法：nb <命令> [参数]
  info                         系统信息
  doctor                       兼容性诊断
  security                     安全体检（只读）
  report [路径]                生成诊断报告
  firewall status|open|close   防火墙状态或端口操作
  ssh status|port <端口>       SSH 状态或修改端口
  swap set <MB>                设置 Swap
  bbr status|enable            查看或启用原生 BBR
  docker status                Docker 状态
  backup list|restore|export   备份中心
  update [stable|testing]      更新工具
  version                      显示版本
EOF
}

cli_dispatch() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    info) system_info;; doctor) compatibility_report;; security) security_audit;; report) diagnostic_report_create "${1:-}";;
    version|--version|-v) echo "$TOOL_VERSION";; help|--help|-h) cli_usage;;
    firewall) case "${1:-}" in status) firewall_status;; open) valid_port "${2:-}" || die "端口无效"; firewall_apply open "$2" "${3:-tcp}";; close) valid_port "${2:-}" || die "端口无效"; firewall_apply close "$2" "${3:-tcp}";; *) cli_usage; return 2;; esac;;
    ssh) case "${1:-}" in status) current_ssh_ports;; port) valid_port "${2:-}" || die "端口无效"; change_ssh_port "$2";; *) cli_usage; return 2;; esac;;
    swap) [ "${1:-}" = set ] && valid_size_mb "${2:-}" || { cli_usage; return 2; }; swap_set "$2";;
    bbr) case "${1:-}" in status) bbr_status;; enable) bbr_enable;; *) cli_usage; return 2;; esac;;
    docker) [ "${1:-}" = status ] && docker_info_summary || { cli_usage; return 2; };;
    backup) case "${1:-}" in list) managed_backup_list;; restore) [ -n "${2:-}" ] || return 2; managed_backup_restore "$2";; export) managed_backup_export "${2:-}";; *) cli_usage; return 2;; esac;;
    update) VMT_UPDATE_CHANNEL="${1:-stable}" exec bash "$VMT_BASE_DIR/update.sh";;
    "") return 1;; *) die "未知命令：$cmd"; cli_usage; return 2;;
  esac
}
