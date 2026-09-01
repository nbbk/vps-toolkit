#!/usr/bin/env bash

system_tools_menu() {
  while true; do
  ui_header "系统工具箱"
  cat <<'EOF'
系统工具箱
--------------------------------------------------------
1. 修改主机名        2. 修改登录密码       3. 查看端口
4. 开放端口          5. 关闭端口           6. 修改 SSH 端口
7. 查看 DNS          8. 设置 DNS           9. 用户列表
10. 创建 sudo 用户   11. 删除用户          12. 修改虚拟内存
13. 修改时区         14. BBR 管理          15. 系统更新
16. 系统清理         17. 服务状态          18. 定时任务
19. 系统日志         20. 安装 Fail2Ban     21. SSH 安全检查
22. 开放全部端口     23. 撤销全部端口开放  24. IPv4/IPv6 模式
0. 返回
--------------------------------------------------------
EOF
  local c; read -r -p "请选择: " c
  case "$c" in
    1) tools_hostname;; 2) change_password;; 3) firewall_status;; 4) firewall_open_ui;; 5) firewall_close_ui;; 6) change_ssh_port_ui;;
    7) cat /etc/resolv.conf;; 8) tools_dns;; 9) getent passwd | awk -F: '$3>=1000 || $1=="root" {print $1,$3,$6,$7}';;
    10) tools_add_user;; 11) tools_delete_user;; 12) swap_ui;; 13) tools_timezone;; 14) bbr_menu;; 15) system_update;; 16) system_clean;;
    17) tools_services;; 18) tools_cron;; 19) tools_logs;; 20) tools_fail2ban;; 21) ssh_security_check;; 22) firewall_open_all;; 23) firewall_restore_default;; 24) ip_family_menu;;
    0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

tools_hostname() { local n; read -r -p "新主机名: " n; [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || { die "主机名格式无效"; return; }; confirm "修改主机名为 $n？" && run hostnamectl set-hostname "$n"; }
tools_timezone() {
  command -v timedatectl >/dev/null || { die "系统不支持 timedatectl"; return; }
  cat <<'EOF'
1. Asia/Shanghai   2. Asia/Hong_Kong   3. Asia/Singapore
4. Asia/Tokyo      5. UTC              6. Europe/London
7. America/New_York  8. America/Los_Angeles  9. 自定义
0. 返回
EOF
  local c z; read -r -p "请选择时区 [1]: " c; c="${c:-1}"
  case "$c" in 1) z=Asia/Shanghai;;2) z=Asia/Hong_Kong;;3) z=Asia/Singapore;;4) z=Asia/Tokyo;;5) z=UTC;;6) z=Europe/London;;7) z=America/New_York;;8) z=America/Los_Angeles;;9) read -r -p "时区名称: " z;;*) return;;esac
  timedatectl list-timezones | grep -qx "$z" || { die "无效时区：$z"; return; }; run timedatectl set-timezone "$z" && ok "时区已修改为 $z"
}
tools_dns() { local values; read -r -p "DNS 地址，空格分隔 [1.1.1.1 8.8.8.8]: " values; values="${values:-1.1.1.1 8.8.8.8}"; confirm "写入 /etc/resolv.conf？网络管理器以后可能覆盖它" || return 0; cp -a /etc/resolv.conf "$BACKUP_DIR/resolv.conf.$(date +%s).bak"; : >/etc/resolv.conf; local x; for x in $values; do printf 'nameserver %s\n' "$x" >>/etc/resolv.conf; done; }
tools_add_user() { local u; read -r -p "新用户名: " u; [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { die "用户名格式无效"; return; }; id "$u" >/dev/null 2>&1 && { die "用户已存在"; return; }; run useradd -m -s /bin/bash "$u"; passwd "$u"; command -v usermod >/dev/null && run usermod -aG "$(getent group sudo >/dev/null && echo sudo || echo wheel)" "$u"; }
tools_delete_user() { local u; read -r -p "删除用户名: " u; [ "$u" != root ] || { die "禁止删除 root"; return; }; id "$u" >/dev/null 2>&1 || { die "用户不存在"; return; }; confirm "删除用户 $u（保留家目录）？" && run userdel "$u"; }
tools_services() { if command -v systemctl >/dev/null; then systemctl --no-pager --type=service --state=running; else rc-status 2>/dev/null || true; fi; }
tools_cron() { printf '当前用户任务:\n'; crontab -l 2>/dev/null || echo 无; printf '\n系统任务:\n'; ls -la /etc/cron.d /etc/cron.* 2>/dev/null || true; }
tools_logs() { if command -v journalctl >/dev/null; then journalctl -p warning -n 200 --no-pager; else tail -n 200 /var/log/messages 2>/dev/null || tail -n 200 /var/log/syslog 2>/dev/null; fi; }
tools_fail2ban() { case "$PKG_FAMILY" in apt) pkg_install fail2ban;; dnf|yum) pkg_install epel-release; pkg_install fail2ban;; apk) pkg_install fail2ban;; esac; command -v systemctl >/dev/null && run systemctl enable --now fail2ban || true; ok "Fail2Ban 已安装；请按实际 SSH 日志路径检查 jail 状态"; }

ip_family_status() {
  local mode=双栈
  [ -f /etc/sysctl.d/99-vps-toolkit-ipv4-only.conf ] && mode="仅 IPv4"
  command -v nft >/dev/null 2>&1 && nft list table inet vps_toolkit_family >/dev/null 2>&1 && mode="仅 IPv6"
  printf '当前模式：%s\n' "$mode"
  grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null && printf '连接优先级：IPv4 优先\n' || true
  grep -q '^precedence ::/0  100' /etc/gai.conf 2>/dev/null && printf '连接优先级：IPv6 优先\n' || true
  printf 'IPv4 地址：\n'; ip -4 -brief address show scope global 2>/dev/null || true
  printf 'IPv6 地址：\n'; ip -6 -brief address show scope global 2>/dev/null || true
}

ip_family_menu() {
  while true; do
    ui_header "IPv4 / IPv6 模式"
    ip_family_status; ui_line
    printf '  1. IPv4 优先（保留双栈）\n  2. IPv6 优先（保留双栈）\n  3. 仅使用 IPv4\n  4. 仅使用 IPv6（高风险）\n  5. 恢复系统双栈默认\n  0. 返回\n'
    local c; read -r -p "请选择: " c
    case "$c" in 1) ip_family_prefer 4;;2) ip_family_prefer 6;;3) ip_family_only4;;4) ip_family_only6;;5) ip_family_dual;;0) break;;*) warn "无效选择";;esac
    submenu_pause
  done
}

ip_family_clear_preference() {
  [ -f /etc/gai.conf ] || touch /etc/gai.conf
  sed -i '/# BEGIN VPS-TOOLKIT IP FAMILY/,/# END VPS-TOOLKIT IP FAMILY/d' /etc/gai.conf
}

ip_family_prefer() {
  local family="$1"; ip_family_remove_only_modes; ip_family_clear_preference
  if [ "$family" = 4 ]; then
    cat >>/etc/gai.conf <<'EOF'
# BEGIN VPS-TOOLKIT IP FAMILY
precedence ::ffff:0:0/96  100
# END VPS-TOOLKIT IP FAMILY
EOF
    ok "已设置 IPv4 优先，IPv6 仍可使用"
  else
    cat >>/etc/gai.conf <<'EOF'
# BEGIN VPS-TOOLKIT IP FAMILY
precedence ::/0  100
# END VPS-TOOLKIT IP FAMILY
EOF
    ok "已设置 IPv6 优先，IPv4 仍可使用"
  fi
}

ip_family_remove_only_modes() {
  rm -f /etc/sysctl.d/99-vps-toolkit-ipv4-only.conf
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  if command -v nft >/dev/null 2>&1; then nft delete table inet vps_toolkit_family >/dev/null 2>&1 || true; fi
  if command -v systemctl >/dev/null 2>&1; then systemctl disable --now vps-toolkit-ipv6-only.service >/dev/null 2>&1 || true; rm -f /etc/systemd/system/vps-toolkit-ipv6-only.service; systemctl daemon-reload; fi
  rm -f /etc/vps-toolkit-ipv6-only.nft
}

ip_family_only4() {
  warn "仅 IPv4 会关闭全部 IPv6 地址和连接。"
  confirm "确认切换为仅 IPv4？" || return 0; ip_family_remove_only_modes; ip_family_clear_preference
  cat >/etc/sysctl.d/99-vps-toolkit-ipv4-only.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF
  run sysctl --system; ok "已切换为仅 IPv4"
}

ip_family_only6_preflight() {
  command -v nft >/dev/null 2>&1 || { die "仅 IPv6 模式需要 nftables"; return 1; }
  ip -6 address show scope global | grep -q 'inet6' || { die "没有全局 IPv6 地址"; return 1; }
  ip -6 route show default | grep -q '^default' || { die "没有 IPv6 默认路由"; return 1; }
  ping -6 -c 2 -W 3 2606:4700:4700::1111 >/dev/null 2>&1 || { die "IPv6 连通性测试失败"; return 1; }
  if [ -n "${SSH_CONNECTION:-}" ]; then
    local client; client="${SSH_CONNECTION%% *}"
    [[ "$client" == *:* ]] || { die "当前 SSH 会话使用 IPv4；切换后会失联，拒绝执行。请通过 IPv6 SSH 或云串口操作"; return 1; }
  fi
}

ip_family_only6() {
  ip_family_only6_preflight || return
  warn "仅 IPv6 会阻断除 loopback 外的全部 IPv4 入站和出站流量。"
  confirm "确认切换为仅 IPv6？" || return 0; ip_family_remove_only_modes; ip_family_clear_preference
  cat >/etc/vps-toolkit-ipv6-only.nft <<'EOF'
table inet vps_toolkit_family {
  chain input { type filter hook input priority -300; policy accept; iifname "lo" accept; meta nfproto ipv4 drop; }
  chain output { type filter hook output priority -300; policy accept; oifname "lo" accept; meta nfproto ipv4 drop; }
}
EOF
  run nft -f /etc/vps-toolkit-ipv6-only.nft || return
  if command -v systemctl >/dev/null 2>&1; then
    cat >/etc/systemd/system/vps-toolkit-ipv6-only.service <<'EOF'
[Unit]
Description=VPS Toolkit IPv6-only firewall
After=network-pre.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/vps-toolkit-ipv6-only.nft
ExecStop=/usr/sbin/nft delete table inet vps_toolkit_family
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable vps-toolkit-ipv6-only.service
  else warn "当前系统非 systemd，IPv6-only 规则重启后需要重新启用"; fi
  ok "已切换为仅 IPv6"
}

ip_family_dual() { ip_family_remove_only_modes; ip_family_clear_preference; run sysctl --system; ok "已恢复双栈与系统默认连接优先级"; }
