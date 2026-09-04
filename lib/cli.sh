#!/usr/bin/env bash

cli_usage() {
  cat <<'EOF'
用法：nb [--dry-run] <命令> [参数]
  info                         系统信息
  doctor                       兼容性诊断
  security                     安全体检（只读）
  report [路径]                生成诊断报告
  firewall status|open|close|open-all|restore-all  防火墙操作
  ssh status|port <端口>       SSH 状态或修改端口
  swap set <MB>|remove         设置或删除 Swap
  bbr status|enable|disable    BBR 管理（enable = BBR + fq）
  bbr profile <组合>           bbr-fq|bbr-fq_codel|cubic-fq|cubic-fq_codel
  docker status                Docker 状态
  backup list|diff|restore|export|import  备份中心
  history                      操作历史
  undo [事务ID|latest]         撤销事务
  baseline create|check        系统状态基线
  extension list|enable|disable 扩展状态管理
  update stable|testing|rollback 更新工具
  version                      显示版本
EOF
}

cli_dispatch() {
  local cmd="${1:-}"; shift || true
  # DRY_RUN is consumed by functions in the other sourced modules.
  # shellcheck disable=SC2034
  if [ "$cmd" = --dry-run ]; then DRY_RUN=1; export VMT_DRY_RUN=1; cmd="${1:-}"; shift || true; fi
  case "$cmd" in
    info) system_info;; doctor) compatibility_report;; security) security_audit;; report) diagnostic_report_create "${1:-}";;
    version|--version|-v) echo "$TOOL_VERSION";; help|--help|-h) cli_usage;;
    firewall) case "${1:-}" in
      status) firewall_status;;
      open|close) [ -n "${2:-}" ] || { die "缺少端口"; return 2; }; firewall_apply "$1" "$2" "${3:-tcp}";;
      open-all) firewall_open_all;; restore-all) firewall_restore_default;;
      *) cli_usage; return 2;;
    esac;;
    ssh) case "${1:-}" in status) current_ssh_ports;; port) valid_port "${2:-}" || { die "端口无效"; return 2; }; change_ssh_port "$2";; *) cli_usage; return 2;; esac;;
    swap) case "${1:-}" in set) valid_size_mb "${2:-}" || { die "Swap 大小无效"; return 2; }; swap_set "$2";; remove) swap_remove;; *) cli_usage; return 2;; esac;;
    bbr) case "${1:-}" in
      status) bbr_status;; enable) bbr_enable;; disable) bbr_disable;;
      profile) case "${2:-}" in
        bbr-fq) bbr_profile_apply bbr fq "原生 BBR + fq（节点推荐）";;
        bbr-fq_codel) bbr_profile_apply bbr fq_codel "原生 BBR + fq_codel";;
        cubic-fq) bbr_profile_apply cubic fq "CUBIC + fq";;
        cubic-fq_codel) bbr_profile_apply cubic fq_codel "CUBIC + fq_codel（兼容）";;
        *) cli_usage; return 2;; esac;;
      *) cli_usage; return 2;; esac;;
    docker) if [ "${1:-}" = status ]; then docker_info_summary; else cli_usage; return 2; fi;;
    backup) case "${1:-}" in list) managed_backup_list;; diff) [ -n "${2:-}" ] || return 2; managed_backup_diff "$2";; restore) [ -n "${2:-}" ] || return 2; managed_backup_restore "$2";; export) managed_backup_export "${2:-}";; import) [ -n "${2:-}" ] || return 2; managed_backup_import "$2";; *) cli_usage; return 2;; esac;;
    history) transaction_history;; undo) transaction_undo "${1:-latest}";;
    baseline) case "${1:-}" in create) baseline_create;; check) baseline_check;; *) cli_usage; return 2;; esac;;
    extension) case "${1:-}" in list) extension_list;; enable|disable) [ -n "${2:-}" ] || return 2; extension_set "$2" "${1}d";; *) cli_usage; return 2;; esac;;
    update) if [ "${1:-stable}" = rollback ]; then exec bash "$VMT_BASE_DIR/update.sh" --rollback; else VMT_UPDATE_CHANNEL="${1:-stable}" exec bash "$VMT_BASE_DIR/update.sh"; fi;;
    "") return 1;; *) die "未知命令：$cmd"; cli_usage; return 2;;
  esac
}
