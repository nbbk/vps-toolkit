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
    1) testsuite_run chatgpt https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh;;
    2) testsuite_run region https://check.unlock.media;;
    3) testsuite_run media https://github.com/yeahwu/check/raw/main/check.sh;;
    11) testsuite_run besttrace https://git.io/besttrace;;
    12) testsuite_run mtr https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh;;
    13) testsuite_run superspeed https://git.io/superspeed_uxh;;
    14) testsuite_run nexttrace https://nxtrace.org/nt;;
    16) testsuite_run backtrace https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh;;
    18) testsuite_run netquality https://Net.Check.Place;;
    19) testsuite_run tcpquality https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh;;
    21) testsuite_run yabs https://yabs.sh -i -5;;
    22) testsuite_run gb5 https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh;;
    31) testsuite_run bench https://bench.sh;;
    32) testsuite_run ecs https://github.com/spiritLHLS/ecs/raw/main/ecs.sh;;
    33) testsuite_run nodequality https://run.NodeQuality.com;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

testsuite_run() {
  local name="$1" url="$2" file; shift 2
  file="$(external_fetch "$url" "test-${name}.sh")" || return
  confirm "运行第三方测试 $name？测试可能持续较久并产生流量" || return 0
  chmod 700 "$file"; bash "$file" "$@"
}
