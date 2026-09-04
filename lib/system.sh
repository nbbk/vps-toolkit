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
    apt) run apt-get update && run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || return 1 ;;
    dnf|yum) run "$PKG_FAMILY" upgrade -y || return 1 ;;
    apk) run apk update && run apk upgrade || return 1 ;;
  esac
  [ -f /var/run/reboot-required ] && warn "系统提示需要重启" || ok "系统更新完成"
}

system_clean() {
  confirm "将清理软件包缓存、孤立包及 14 天前的日志，继续？" || return 0
  case "$PKG_FAMILY" in
    apt) run env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y && run apt-get clean || return 1 ;;
    dnf|yum) run "$PKG_FAMILY" autoremove -y && run "$PKG_FAMILY" clean all || return 1 ;;
    apk) run rm -rf /var/cache/apk/* || return 1 ;;
  esac
  command -v journalctl >/dev/null && run journalctl --vacuum-time=14d || true
  ok "清理完成"
}

bbr_status() {
  local current_cc current_qdisc
  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  printf '内核: %s\n可用拥塞算法: %s\n当前拥塞算法: %s\n默认队列算法: %s\n当前组合: %s + %s\n' "$(uname -r)" \
    "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)" \
    "$current_cc" "$current_qdisc" "$current_cc" "$current_qdisc"
  lsmod 2>/dev/null | grep -q '^tcp_bbr' && ok "tcp_bbr 模块已加载" || warn "tcp_bbr 模块未加载或内置于内核"
}

BBR_PROFILE_FILE=/etc/sysctl.d/99-vps-toolkit-zz-congestion.conf

bbr_profile_apply() {
  local congestion="${1:-}" qdisc="${2:-}" label="${3:-${1:-} + ${2:-}}"
  local file="$BBR_PROFILE_FILE" tmp backup_id current_cc current_qdisc actual_cc actual_qdisc
  [[ "$congestion" =~ ^[a-z0-9_]+$ ]] || { die "拥塞算法名称无效"; return 1; }
  case "$qdisc" in fq|fq_codel) ;; *) die "队列算法仅允许 fq 或 fq_codel"; return 1;; esac
  current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  risk_preview "切换 TCP 算法组合" "${current_cc} + ${current_qdisc} → ${congestion} + ${qdisc}"$'\n'"配置：$file" "回滚方式：配置备份中心或 nb undo latest" || return 0
  if plan_only; then printf '[DRY-RUN] 将验证内核支持并应用 %s + %s；不会修改现有网卡的自定义 tc 规则。\n' "$congestion" "$qdisc"; return 0; fi
  [ "$congestion" != bbr ] || modprobe tcp_bbr 2>/dev/null || true
  modprobe "sch_${qdisc}" 2>/dev/null || true
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | tr ' ' '\n' | grep -Fxq "$congestion" || { die "当前内核不支持拥塞算法：$congestion"; return 1; }
  transaction_begin bbr || return
  backup_id="$(managed_backup_file bbr "$file")" || { transaction_finish failed; return 1; }
  tmp="$(mktemp)"
  printf '# Managed by vps-toolkit: %s\nnet.core.default_qdisc=%s\nnet.ipv4.tcp_congestion_control=%s\n' "$label" "$qdisc" "$congestion" >"$tmp"
  if ! run install -m 0644 "$tmp" "$file" || ! run sysctl --system; then
    rm -f -- "$tmp"; managed_backup_restore_force "$backup_id" || true; sysctl --system >/dev/null 2>&1 || true
    transaction_finish rolled-back; die "算法组合应用失败，已恢复原配置"; return 1
  fi
  rm -f -- "$tmp"
  actual_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  actual_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  if [ "$actual_cc" = "$congestion" ] && [ "$actual_qdisc" = "$qdisc" ]; then
    transaction_note "congestion=$congestion qdisc=$qdisc"
    transaction_finish success; ok "算法组合已启用：${congestion} + ${qdisc}"
  else
    managed_backup_restore_force "$backup_id" || true; sysctl --system >/dev/null 2>&1 || true
    transaction_finish rolled-back; die "算法组合未完整生效（实际：${actual_cc:-unknown} + ${actual_qdisc:-unknown}），已恢复原配置"; return 1
  fi
}

bbr_enable() { bbr_profile_apply bbr fq "原生 BBR + fq（节点推荐）"; }

bbr_custom_profile_ui() {
  local qdisc="$1" congestion available
  [ "$DRY_RUN" = 1 ] && available="bbr cubic reno" || available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  printf '内核当前可用拥塞算法：%s\n' "${available:-无法读取}"
  read -r -p "请输入拥塞算法名称: " congestion
  [[ "$congestion" =~ ^[a-z0-9_]+$ ]] || { die "算法名称无效"; return; }
  if [ "$DRY_RUN" != 1 ]; then
    printf '%s\n' "$available" | tr ' ' '\n' | grep -Fxq "$congestion" || { die "该算法不在内核可用列表中"; return; }
  fi
  bbr_profile_apply "$congestion" "$qdisc" "自定义 ${congestion} + ${qdisc}"
}

bbr_profile_menu() {
  while true; do
    clear_screen; bbr_status
    cat <<'EOF'

拥塞控制 + 队列算法组合
--------------------------------------------------------
1. BBR + fq（节点推荐）       2. BBR + fq_codel（可选）
3. CUBIC + fq_codel（兼容）  4. CUBIC + fq（吞吐兼容）
5. 自定义拥塞算法 + fq        6. 自定义拥塞算法 + fq_codel
0. 返回
--------------------------------------------------------
说明：BBRv3 内核启用后仍选择 BBR + fq；算法名同为 bbr。
EOF
    local c; read -r -p "请选择: " c
    case "$c" in
      1) bbr_profile_apply bbr fq "原生 BBR + fq（节点推荐）";;
      2) bbr_profile_apply bbr fq_codel "原生 BBR + fq_codel";;
      3) bbr_profile_apply cubic fq_codel "CUBIC + fq_codel（兼容）";;
      4) bbr_profile_apply cubic fq "CUBIC + fq";;
      5) bbr_custom_profile_ui fq;; 6) bbr_custom_profile_ui fq_codel;;
      0) break;; *) warn "无效选择";;
    esac
    submenu_pause
  done
}

bbr_disable() {
  local profile_backup legacy_backup actual_cc actual_qdisc
  confirm "将撤销本工具写入的算法组合配置（不卸载内核），继续？" || return 0
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 删除 %s 和旧版 BBR 配置并重新加载 sysctl\n' "$BBR_PROFILE_FILE"; plan_only; return 0; fi
  transaction_begin bbr || return
  profile_backup="$(managed_backup_file bbr "$BBR_PROFILE_FILE")" || { transaction_finish failed; return 1; }
  legacy_backup="$(managed_backup_file bbr /etc/sysctl.d/99-vps-toolkit-bbr.conf)" || { transaction_finish failed; return 1; }
  run rm -f "$BBR_PROFILE_FILE" /etc/sysctl.d/99-vps-toolkit-bbr.conf || { transaction_finish failed; return 1; }
  if ! run sysctl --system; then
    managed_backup_restore_force "$legacy_backup" || true; managed_backup_restore_force "$profile_backup" || true; sysctl --system >/dev/null 2>&1 || true
    transaction_finish rolled-back; die "撤销失败，已恢复原配置"; return 1
  fi
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
  actual_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  actual_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  transaction_finish success; ok "算法组合配置已撤销；当前：${actual_cc} + ${actual_qdisc}"
  if grep -Eq '^[[:space:]]*net\.(core\.default_qdisc|ipv4\.tcp_congestion_control)[[:space:]]*=' /etc/sysctl.d/99-vps-toolkit-network.conf 2>/dev/null; then
    warn "检测到旧版网络参数配置仍指定算法；如需完全撤销，请先重新执行 6 迁移配置，或选择 7 撤销网络优化"
  fi
}

bbr_menu() {
  while true; do
  clear_screen; bbr_status
  cat <<'EOF'

BBR 管理
--------------------------------------------------------
1. 拥塞/队列算法组合          2. 撤销算法组合配置
3. 安装 XanMod BBRv3 内核     4. 更新 XanMod BBRv3 内核
5. 卸载 XanMod BBRv3 内核     6. 网络参数优化
7. 撤销网络参数优化           8. 查看详细状态
0. 返回
--------------------------------------------------------
说明：节点优先选择 BBR + fq；BBRv3 内核管理仅支持 x86_64 Debian 12+/Ubuntu 24.04+。
EOF
  read -r -p "请选择: " c
  case "$c" in
    1) bbr_profile_menu;; 2) bbr_disable;; 3) xanmod_install install;; 4) xanmod_install update;;
    5) xanmod_uninstall;; 6) network_tune_enable;; 7) network_tune_disable;; 8) bbr_detailed_status;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

xanmod_supported() {
  [ "$(uname -m)" = x86_64 ] || { die "XanMod BBRv3 受控安装仅支持 x86_64"; return 1; }
  [ "$PKG_FAMILY" = apt ] || { die "仅支持 Debian/Ubuntu 的 APT 系统"; return 1; }
  case "${OS_CODENAME:-}" in bookworm|trixie|forky|sid|noble|plucky|questing|resolute) return 0;; esac
  die "XanMod 官方源不支持当前发行版代号：${OS_CODENAME:-unknown}"; return 1
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
  printf 'deb [signed-by=%s] https://deb.xanmod.org %s main\n' "$key" "$OS_CODENAME" >"$list"; run apt-get update
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
  bbr_enable || { warn "XanMod 已处理，但 BBR + fq 尚未启用；请重启进入新内核后在算法组合菜单重试"; return 1; }
  ok "XanMod 处理完成：$pkg。请确认控制台救援可用后手动重启"
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
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 写入保守网络参数 /etc/sysctl.d/99-vps-toolkit-network.conf\n'; plan_only; return 0; fi
  local target=/etc/sysctl.d/99-vps-toolkit-network.conf tmp backup_id
  transaction_begin network || return
  backup_id="$(managed_backup_file network "$target")" || { transaction_finish failed; return 1; }
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOF'
# Managed by vps-toolkit. Conservative VPS network tuning.
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
  if ! run install -m 0644 "$tmp" "$target" || ! run sysctl --system; then
    rm -f -- "$tmp"; managed_backup_restore_force "$backup_id" || true; sysctl --system >/dev/null 2>&1 || true
    transaction_finish rolled-back; die "网络参数应用失败，已恢复原配置"; return
  fi
  rm -f -- "$tmp"; transaction_finish success; ok "网络参数优化已应用；当前拥塞/队列算法组合保持不变"
}

network_tune_disable() {
  local backup_id
  confirm "撤销本工具的网络参数优化？" || return 0
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 删除 /etc/sysctl.d/99-vps-toolkit-network.conf 并重新加载 sysctl\n'; plan_only; return 0; fi
  transaction_begin network || return
  backup_id="$(managed_backup_file network /etc/sysctl.d/99-vps-toolkit-network.conf)" || { transaction_finish failed; return 1; }
  run rm -f /etc/sysctl.d/99-vps-toolkit-network.conf || { transaction_finish failed; return 1; }
  if ! run sysctl --system; then managed_backup_restore_force "$backup_id" || true; sysctl --system >/dev/null 2>&1 || true; transaction_finish rolled-back; die "撤销失败，已恢复原配置"; return; fi
  transaction_finish success; ok "网络参数优化已撤销"
}

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

swap_file_size_mb() {
  [ -f /swapfile ] || { echo 0; return; }
  local bytes; bytes="$(stat -c %s /swapfile 2>/dev/null || echo 0)"
  echo $(( (bytes + 1048575) / 1048576 ))
}

swap_build_file() {
  local target="$1" size="$2"
  rm -f -- "$target"
  if command -v fallocate >/dev/null; then run fallocate -l "${size}M" "$target" || return 1
  else run dd if=/dev/zero of="$target" bs=1M count="$size" status=progress || return 1; fi
  run chmod 600 "$target" && run mkswap "$target"
}

swap_restore_state() {
  local size="$1" active="$2"
  swapoff /swapfile 2>/dev/null || true; rm -f -- /swapfile
  if [ "$size" -gt 0 ]; then
    swap_build_file /swapfile "$size" || return 1
    if [ "$active" = 1 ]; then run swapon /swapfile || return 1; fi
  fi
}

swap_set() {
  local size="$1" file=/swapfile temp old_size old_active=0 backup_id
  [ -e "$file" ] && [ ! -f "$file" ] && die "$file 不是普通文件"
  if swapon --noheadings --show=NAME 2>/dev/null | grep -qxv "$file"; then
    die "检测到其他 Swap；为避免误删，请先人工处理"
    return
  fi
  risk_preview "修改 Swap" "重建 $file 为 ${size}MB，并更新 /etc/fstab" "当前 /etc/fstab 会进入配置备份中心" || return 0
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 创建 %sMB /swapfile，权限 0600，并更新 /etc/fstab\n' "$size"; plan_only; return 0; fi
  transaction_begin swap || return
  backup_id="$(managed_backup_file swap /etc/fstab)" || { transaction_finish failed; return 1; }
  old_size="$(swap_file_size_mb)"; swapon --noheadings --show=NAME 2>/dev/null | grep -qx "$file" && old_active=1 || true
  transaction_note "swap_undo=$old_size|$old_active"
  temp="/swapfile.vps-toolkit-new.$$"
  if ! swap_build_file "$temp" "$size"; then rm -f -- "$temp"; transaction_finish failed; die "新 Swap 文件创建失败，原 Swap 未改动"; return; fi
  if [ "$old_active" = 1 ] && ! swapoff "$file"; then rm -f -- "$temp"; transaction_finish failed; die "无法停用旧 Swap，原文件未改动"; return; fi
  if ! rm -f -- "$file" || ! mv -- "$temp" "$file" || ! run swapon "$file"; then
    rm -f -- "$temp"; swap_restore_state "$old_size" "$old_active" || true; managed_backup_restore_force "$backup_id" || true
    transaction_finish rolled-back; die "启用新 Swap 失败，已尝试恢复原状态"; return
  fi
  if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab && ! printf '/swapfile none swap sw 0 0\n' >>/etc/fstab; then
    swap_restore_state "$old_size" "$old_active" || true; managed_backup_restore_force "$backup_id" || true
    transaction_finish rolled-back; die "更新 /etc/fstab 失败，已尝试恢复原状态"; return
  fi
  transaction_finish success; ok "Swap 已设置为 ${size}MB"
}

swap_remove() {
  local old_size old_active=0 backup_id
  risk_preview "删除 Swap" "停用并删除 /swapfile，修改 /etc/fstab" "当前 /etc/fstab 会进入配置备份中心" || return 0
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] swapoff 并删除 /swapfile，移除 fstab 条目\n'; plan_only; return 0; fi
  transaction_begin swap || return
  backup_id="$(managed_backup_file swap /etc/fstab)" || { transaction_finish failed; return 1; }
  old_size="$(swap_file_size_mb)"; swapon --noheadings --show=NAME 2>/dev/null | grep -qx /swapfile && old_active=1 || true
  transaction_note "swap_undo=$old_size|$old_active"
  if [ "$old_active" = 1 ] && ! swapoff /swapfile; then transaction_finish failed; die "无法停用 /swapfile"; return; fi
  if ! sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab || ! run rm -f /swapfile; then
    managed_backup_restore_force "$backup_id" || true; swap_restore_state "$old_size" "$old_active" || true
    transaction_finish rolled-back; die "删除 Swap 失败，已尝试恢复原状态"; return
  fi
  transaction_finish success; ok "本工具的 Swap 已移除"
}
