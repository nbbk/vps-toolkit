#!/usr/bin/env bash

detect_virtualization() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then systemd-detect-virt 2>/dev/null || echo none
  elif [ -r /proc/1/cgroup ]; then awk -F/ '/docker|lxc|kubepods/{print $NF; found=1; exit} END{if(!found)print "unknown"}' /proc/1/cgroup
  else echo unknown; fi
}

detect_firewall_backend() {
  if command -v ufw >/dev/null 2>&1; then echo ufw
  elif command -v firewall-cmd >/dev/null 2>&1; then echo firewalld
  elif command -v nft >/dev/null 2>&1; then echo nftables
  else echo none; fi
}

detect_init_system() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then echo systemd
  elif command -v rc-service >/dev/null 2>&1; then echo openrc
  else echo unknown; fi
}

detect_cloud() {
  if [ -r /sys/class/dmi/id/sys_vendor ] && grep -qi oracle /sys/class/dmi/id/sys_vendor; then echo OCI
  elif [ -r /sys/class/dmi/id/product_name ] && grep -qi 'amazon\|ec2' /sys/class/dmi/id/product_name; then echo AWS
  elif [ -r /sys/class/dmi/id/sys_vendor ] && grep -qi microsoft /sys/class/dmi/id/sys_vendor; then echo Azure
  else echo unknown; fi
}

connectivity_state() {
  local family="$1" target
  [ "$family" = 4 ] && target=1.1.1.1 || target=2606:4700:4700::1111
  if command -v ping >/dev/null 2>&1 && ping "-$family" -c 1 -W 2 "$target" >/dev/null 2>&1; then echo available; else echo unavailable; fi
}

compatibility_report() {
  detect_os || return
  local ssh_mode=service
  ssh_socket_activation_active 2>/dev/null && ssh_mode=socket
  ui_header "系统兼容性诊断"
  printf '%-20s %s\n' \
    "工具版本" "$TOOL_VERSION" \
    "系统" "$OS_PRETTY" \
    "架构" "$(uname -m)" \
    "内核" "$(uname -r)" \
    "包管理器" "$PKG_FAMILY" \
    "初始化系统" "$(detect_init_system)" \
    "虚拟化" "$(detect_virtualization)" \
    "云平台" "$(detect_cloud)" \
    "防火墙" "$(detect_firewall_backend)" \
    "SSH 启动方式" "$ssh_mode" \
    "SSH 端口" "$(current_ssh_ports | paste -sd, -)" \
    "IPv4 连通" "$(connectivity_state 4)" \
    "IPv6 连通" "$(connectivity_state 6)" \
    "Docker" "$(command -v docker >/dev/null 2>&1 && docker --version 2>/dev/null || echo not-installed)" \
    "拥塞控制" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)" \
    "队列算法" "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  printf '\n功能可用性：\n'
  compatibility_item "软件包管理" "[[ $PKG_FAMILY =~ ^(apt|dnf|yum|apk)$ ]]"
  compatibility_item "SSH 管理" "command -v sshd >/dev/null"
  compatibility_item "防火墙自动管理" "[[ $(detect_firewall_backend) != none ]]"
  compatibility_item "Docker 管理" "[[ $PKG_FAMILY != apk ]]"
  compatibility_item "XanMod 内核" "[[ $PKG_FAMILY = apt && $(uname -m) = x86_64 ]]"
  compatibility_item "后台工作区" "command -v tmux >/dev/null"
}

compatibility_item() {
  local name="$1" check="$2"
  if eval "$check"; then printf '  %b●%b %s\n' "$C_GREEN" "$C_RESET" "$name"; else printf '  %b○%b %s（当前环境不可用）\n' "$C_YELLOW" "$C_RESET" "$name"; fi
}

diagnostic_report_create() {
  local out="${1:-$STATE_DIR/reports/diagnostic-$(date +%Y%m%d-%H%M%S).txt}"
  mkdir -p "$(dirname "$out")"
  {
    echo "VPS Toolkit diagnostic report"
    echo "generated=$(date -Is)"
    echo "version=$TOOL_VERSION"
    compatibility_report
    echo; echo "== disks =="; df -hT 2>/dev/null || true
    echo; echo "== memory =="; free -h 2>/dev/null || true
    echo; echo "== listening ports =="; ss -lntup 2>/dev/null || true
    echo; echo "== failed services =="; systemctl --failed --no-pager 2>/dev/null || true
    echo; echo "== recent toolkit errors =="; grep ' ERROR\|\[ERROR\]' "$LOG_FILE" 2>/dev/null | tail -n 30 || true
  } >"$out"
  chmod 600 "$out"
  ok "诊断报告已生成：$out（不包含密码和 SSH 私钥）"
}

diagnostics_menu() {
  while true; do
    ui_header "诊断中心"
    cat <<'EOF'
1. 系统兼容性诊断
2. 生成诊断报告
3. 查看最近错误
0. 返回
EOF
    local c; read -r -p "请选择: " c
    case "$c" in 1) compatibility_report;; 2) diagnostic_report_create "";; 3) grep ' ERROR\|\[ERROR\]' "$LOG_FILE" 2>/dev/null | tail -n 50 || true;; 0) break;; *) warn "无效选择";; esac
    submenu_pause
  done
}
