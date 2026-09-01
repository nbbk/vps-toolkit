#!/usr/bin/env bash

testsuite_menu() {
  while true; do
  ui_header "测试脚本合集"
  cat <<'EOF'
测试脚本合集
--------------------------------------------------------
IP及解锁：1 ChatGPT  2 Region  3 yeahwu
网络线路：11 BestTrace 12 MTR 13 SuperSpeed 14 NextTrace
           16 BackTrace 18 NetQuality 19 TCPQuality
硬件性能：21 YABS 22 Geekbench5
综合测试：31 Bench 32 ECS融合怪 33 NodeQuality
0 返回
--------------------------------------------------------
第三方测试会下载、显示来源和 SHA-256，并在 y/N 确认后运行。
EOF
  local c; read -r -p "请选择: " c
  case "$c" in
    1) testsuite_run chatgpt test-chatgpt;; 2) testsuite_run region test-region;; 3) testsuite_run media test-media;;
    11) testsuite_run besttrace test-besttrace;; 12) testsuite_run mtr test-mtr;; 13) testsuite_run superspeed test-superspeed;;
    14) testsuite_run nexttrace test-nexttrace;; 16) testsuite_run backtrace test-backtrace;; 18) testsuite_run netquality test-netquality;;
    19) testsuite_run tcpquality test-tcpquality;; 21) testsuite_run yabs test-yabs -i -5;; 22) testsuite_run gb5 test-gb5;;
    31) testsuite_run bench test-bench;; 32) testsuite_run ecs test-ecs;; 33) testsuite_run nodequality test-nodequality;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

testsuite_run() {
  local name="$1" source_id="$2" file; shift 2
  file="$(external_fetch_id "$source_id")" || return
  confirm "运行第三方测试 $name？测试可能持续较久并产生流量" || return 0
  chmod 700 "$file"; bash "$file" "$@"
}
