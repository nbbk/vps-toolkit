#!/usr/bin/env bash

testsuite_menu() {
  while true; do
  ui_header "测试脚本合集"
  cat <<'EOF'
测试脚本合集
--------------------------------------------------------
IP及解锁：2 Region  3 yeahwu
网络线路：11 多目标路由(NextTrace) 12 MTR 13 SuperSpeed
           16 BackTrace 18 NetQuality 19 TCPQuality
硬件性能：21 YABS 22 Geekbench5
综合测试：31 Bench 32 ECS融合怪 33 NodeQuality
0 返回
--------------------------------------------------------
第三方测试会下载、显示来源和 SHA-256，并在 y/N 确认后运行。
EOF
  local c; read -r -p "请选择: " c
  case "$c" in
    2) testsuite_run region test-region;; 3) testsuite_run media test-media;;
    11) testsuite_run besttrace test-besttrace;; 12) testsuite_run mtr test-mtr;; 13) testsuite_run superspeed test-superspeed;;
    16) testsuite_run backtrace test-backtrace;; 18) testsuite_run netquality test-netquality;;
    19) testsuite_run tcpquality test-tcpquality;; 21) testsuite_run yabs test-yabs -i -5;; 22) testsuite_run gb5 test-gb5;;
    31) testsuite_run bench test-bench;; 32) testsuite_run ecs test-ecs;; 33) testsuite_run nodequality test-nodequality;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

testsuite_run() {
  local name="$1" source_id="$2" file status; shift 2
  if [ "$DRY_RUN" = 1 ]; then
    printf '[DRY-RUN] 第三方脚本 %s：不下载或执行脚本\n' "$name"
    return 0
  fi
  file="$(external_fetch_id "$source_id")" || return
  [ -s "$file" ] && bash -n "$file" || { die "第三方脚本为空或 Bash 语法无效：$name"; return 1; }
  sed -n '1,80p' "$file"
  confirm "运行第三方脚本 $name？可能安装依赖、持续较久并产生流量" || return 0
  if bash "$file" "$@"; then return 0; else status=$?; fi
  warn "第三方脚本 $name 返回非零退出码 $status；请查看上方输出，上游退出码不一定准确" >&2
  return "$status"
}
