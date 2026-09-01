#!/usr/bin/env bash

system_info() {
  clear_screen
  say "${C_CYAN}系统信息${C_RESET}"
  printf '系统: %s\n内核: %s\n架构: %s\n主机名: %s\n运行时间: %s\n' \
    "$OS_PRETTY" "$(uname -r)" "$(uname -m)" "$(hostname)" "$(uptime -p 2>/dev/null || uptime)"
  printf '\nCPU:\n'; command -v lscpu >/dev/null && lscpu | sed -nE '/^(Model name|CPU\(s\)|Architecture):/p' || true
  printf '\n内存/Swap:\n'; free -h 2>/dev/null || true
  printf '\n磁盘:\n'; df -hT -x tmpfs -x devtmpfs 2>/dev/null || df -h
  printf '\nIP 地址:\n'; ip -brief address 2>/dev/null || hostname -I || true
  printf '\n监听端口:\n'; ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || true
}

system_update() {
  confirm "将更新全部系统软件包，继续？" || return 0
  case "$PKG_FAMILY" in
    apt) run apt-get update; run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
    dnf|yum) run "$PKG_FAMILY" upgrade -y ;;
    apk) run apk update; run apk upgrade ;;
  esac
  [ -f /var/run/reboot-required ] && warn "系统提示需要重启" || ok "系统更新完成"
}

system_clean() {
  confirm "将清理软件包缓存、孤立包及 14 天前的日志，继续？" || return 0
  case "$PKG_FAMILY" in
    apt) run env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y; run apt-get clean ;;
    dnf|yum) run "$PKG_FAMILY" autoremove -y; run "$PKG_FAMILY" clean all ;;
    apk) run rm -rf /var/cache/apk/* ;;
  esac
  command -v journalctl >/dev/null && run journalctl --vacuum-time=14d || true
  ok "清理完成"
}

bbr_status() {
  printf '内核: %s\n可用算法: %s\n当前算法: %s\n队列算法: %s\n' "$(uname -r)" \
    "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)" \
    "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)" \
    "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  lsmod 2>/dev/null | grep -q '^tcp_bbr' && ok "tcp_bbr 模块已加载" || warn "tcp_bbr 模块未加载或内置于内核"
}

bbr_enable() {
  modprobe tcp_bbr 2>/dev/null || true
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr || { die "当前内核不支持 BBR；本工具不会替换第三方内核"; return; }
  local file=/etc/sysctl.d/99-vps-toolkit-bbr.conf tmp
  tmp="$(mktemp)"; printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >"$tmp"
  run install -m 0644 "$tmp" "$file"; rm -f "$tmp"; run sysctl --system
  [ "$(sysctl -n net.ipv4.tcp_congestion_control)" = bbr ] && ok "BBR 已启用" || die "BBR 未能生效"
}

bbr_disable() {
  confirm "将撤销本工具写入的 BBR 配置（不卸载内核），继续？" || return 0
  run rm -f /etc/sysctl.d/99-vps-toolkit-bbr.conf
  run sysctl -w net.ipv4.tcp_congestion_control=cubic || true
  run sysctl --system
}

bbr_menu() {
  bbr_status
  printf '\n1. 启用内核原生 BBR\n2. 撤销本工具配置\n0. 返回\n'
  read -r -p "请选择: " c
  case "$c" in 1) bbr_enable;; 2) bbr_disable;; esac
}

swap_ui() {
  swapon --show 2>/dev/null || true; free -h || true
  read -r -p "新 Swap 大小（MB，输入 0 表示停用并删除本工具的 swapfile）: " size
  if [ "$size" = 0 ]; then swap_remove; return; fi
  valid_size_mb "$size" || { die "请输入 128-262144 MB"; return; }
  swap_set "$size"
}

swap_set() {
  local size="$1" file=/swapfile
  [ -e "$file" ] && [ ! -f "$file" ] && die "$file 不是普通文件"
  if swapon --noheadings --show=NAME 2>/dev/null | grep -qxv "$file"; then
    die "检测到其他 Swap；为避免误删，请先人工处理"
    return
  fi
  confirm "将把 $file 设置为 ${size}MB，继续？" || return 0
  swapoff "$file" 2>/dev/null || true
  [ -f "$file" ] && cp -a "$file" "$BACKUP_DIR/swapfile.$(date +%s).bak" || true
  run rm -f "$file"
  if command -v fallocate >/dev/null; then run fallocate -l "${size}M" "$file"; else run dd if=/dev/zero of="$file" bs=1M count="$size" status=progress; fi
  run chmod 600 "$file"; run mkswap "$file"; run swapon "$file"
  grep -qE '^/swapfile[[:space:]]' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >>/etc/fstab
  ok "Swap 已设置为 ${size}MB"
}

swap_remove() {
  confirm "确认停用并删除 /swapfile？" || return 0
  swapoff /swapfile 2>/dev/null || true
  sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab
  run rm -f /swapfile
  ok "本工具的 Swap 已移除"
}
