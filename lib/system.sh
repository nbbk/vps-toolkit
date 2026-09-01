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
  clear_screen; bbr_status
  cat <<'EOF'

BBR 管理
--------------------------------------------------------
1. 启用当前内核原生 BBR       2. 撤销 BBR 配置
3. 安装 XanMod BBRv3 内核     4. 更新 XanMod BBRv3 内核
5. 卸载 XanMod BBRv3 内核     6. 网络参数优化
7. 撤销网络参数优化           8. 查看详细状态
0. 返回
--------------------------------------------------------
说明：BBRv3 内核管理仅支持 x86_64 Debian 12+/Ubuntu 24.04+。
EOF
  read -r -p "请选择: " c
  case "$c" in
    1) bbr_enable;; 2) bbr_disable;; 3) xanmod_install install;; 4) xanmod_install update;;
    5) xanmod_uninstall;; 6) network_tune_enable;; 7) network_tune_disable;; 8) bbr_detailed_status;;
  esac
}

xanmod_supported() {
  [ "$(uname -m)" = x86_64 ] || { die "XanMod BBRv3 受控安装仅支持 x86_64"; return 1; }
  [ "$PKG_FAMILY" = apt ] || { die "仅支持 Debian/Ubuntu 的 APT 系统"; return 1; }
  case "${VERSION_CODENAME:-}" in bookworm|trixie|forky|sid|noble|plucky|questing|resolute) return 0;; esac
  die "XanMod 官方源不支持当前发行版代号：${VERSION_CODENAME:-unknown}"; return 1
}

xanmod_installed() { dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep -q '^linux-.*xanmod'; }

xanmod_psabi_level() {
  local flags level=1 f; flags=" $(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2) "
  for f in cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; do [[ "$flags" = *" $f "* ]] || { echo 1; return; }; done; level=2
  for f in avx avx2 bmi1 bmi2 f16c fma movbe xsave; do [[ "$flags" = *" $f "* ]] || { echo "$level"; return; }; done
  echo 3
}

xanmod_add_repo() {
  pkg_install ca-certificates curl gnupg
  local key=/usr/share/keyrings/xanmod-archive-keyring.gpg list=/etc/apt/sources.list.d/xanmod-release.list tmp
  tmp="$(mktemp)"; run curl --fail --location --proto '=https' --tlsv1.2 https://dl.xanmod.org/archive.key -o "$tmp"
  gpg --batch --yes --dearmor -o "$key" "$tmp"; rm -f "$tmp"; chmod 644 "$key"
  printf 'deb [signed-by=%s] https://deb.xanmod.org %s main\n' "$key" "$VERSION_CODENAME" >"$list"; run apt-get update
}

xanmod_package() {
  local level prefix pkg; level="$(xanmod_psabi_level)"
  for prefix in linux-xanmod linux-xanmod-lts; do
    while [ "$level" -ge 1 ]; do pkg="${prefix}-x64v${level}"; apt-cache show "$pkg" >/dev/null 2>&1 && { echo "$pkg"; return; }; level=$((level - 1)); done
    level="$(xanmod_psabi_level)"
  done
  return 1
}

xanmod_install() {
  local action="$1" verb pkg; xanmod_supported || return
  [ "$action" != update ] || xanmod_installed || { die "尚未安装 XanMod"; return; }
  [ "$action" = install ] && verb=安装 || verb=更新
  confirm "将${verb}第三方 XanMod 内核；可能导致无法启动，请先做云盘快照。继续？" || return 0
  xanmod_add_repo || return; pkg="$(xanmod_package)" || { die "未找到适配 CPU 的 XanMod 软件包"; return; }
  if [ "$action" = update ]; then run apt-get install -y --only-upgrade "$pkg" || run apt-get install -y "$pkg"; else run apt-get install -y "$pkg"; fi
  bbr_enable; ok "XanMod 处理完成：$pkg。请确认控制台救援可用后手动重启"
}

xanmod_uninstall() {
  xanmod_installed || { warn "未安装 XanMod"; return; }
  printf '当前运行内核：%s\n' "$(uname -r)"; dpkg-query -W -f='${Package} ${Version}\n' 'linux-*xanmod*' 2>/dev/null || true
  confirm "将卸载 XanMod；必须确保发行版原生内核仍存在。继续？" || return 0
  dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | grep -qv xanmod || { die "未检测到备用原生内核，拒绝卸载"; return; }
  run apt-get purge -y 'linux-*xanmod*'; run apt-get autoremove -y; command -v update-grub >/dev/null && run update-grub || true
  rm -f /etc/apt/sources.list.d/xanmod-release.list /usr/share/keyrings/xanmod-archive-keyring.gpg; ok "XanMod 已卸载；请手动重启"
}

network_tune_enable() {
  cat >/etc/sysctl.d/99-vps-toolkit-network.conf <<'EOF'
# Managed by vps-toolkit. Conservative VPS network tuning.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_fin_timeout=15
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
EOF
  run sysctl --system; ok "网络参数优化已应用"
}

network_tune_disable() { confirm "撤销本工具的网络参数优化？" || return 0; rm -f /etc/sysctl.d/99-vps-toolkit-network.conf; run sysctl --system; }

bbr_detailed_status() {
  bbr_status; printf '\nXanMod 软件包:\n'; dpkg-query -W -f='${Package} ${Version}\n' 'linux-*xanmod*' 2>/dev/null || echo 未安装
  printf '\n相关 sysctl:\n'; sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_fastopen net.ipv4.tcp_mtu_probing 2>/dev/null || true
  [ -f /var/run/reboot-required ] && warn "系统需要重启" || true
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
