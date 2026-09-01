#!/usr/bin/env bash

system_tools_menu() {
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
22. 开放全部端口     23. 撤销全部端口开放  0. 返回
--------------------------------------------------------
EOF
  local c; read -r -p "请选择: " c
  case "$c" in
    1) tools_hostname;; 2) change_password;; 3) firewall_status;; 4) firewall_open_ui;; 5) firewall_close_ui;; 6) change_ssh_port_ui;;
    7) cat /etc/resolv.conf;; 8) tools_dns;; 9) getent passwd | awk -F: '$3>=1000 || $1=="root" {print $1,$3,$6,$7}';;
    10) tools_add_user;; 11) tools_delete_user;; 12) swap_ui;; 13) tools_timezone;; 14) bbr_menu;; 15) system_update;; 16) system_clean;;
    17) tools_services;; 18) tools_cron;; 19) tools_logs;; 20) tools_fail2ban;; 21) ssh_security_check;; 22) firewall_open_all;; 23) firewall_restore_default;;
  esac
}

tools_hostname() { local n; read -r -p "新主机名: " n; [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || { die "主机名格式无效"; return; }; confirm "修改主机名为 $n？" && run hostnamectl set-hostname "$n"; }
tools_timezone() { command -v timedatectl >/dev/null || { die "系统不支持 timedatectl"; return; }; timedatectl list-timezones | grep -E 'Asia/(Shanghai|Hong_Kong|Tokyo|Singapore)|UTC' || true; local z; read -r -p "时区 [Asia/Shanghai]: " z; z="${z:-Asia/Shanghai}"; timedatectl list-timezones | grep -qx "$z" || { die "无效时区"; return; }; run timedatectl set-timezone "$z"; }
tools_dns() { local values; read -r -p "DNS 地址，空格分隔 [1.1.1.1 8.8.8.8]: " values; values="${values:-1.1.1.1 8.8.8.8}"; confirm "写入 /etc/resolv.conf？网络管理器以后可能覆盖它" || return 0; cp -a /etc/resolv.conf "$BACKUP_DIR/resolv.conf.$(date +%s).bak"; : >/etc/resolv.conf; local x; for x in $values; do printf 'nameserver %s\n' "$x" >>/etc/resolv.conf; done; }
tools_add_user() { local u; read -r -p "新用户名: " u; [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { die "用户名格式无效"; return; }; id "$u" >/dev/null 2>&1 && { die "用户已存在"; return; }; run useradd -m -s /bin/bash "$u"; passwd "$u"; command -v usermod >/dev/null && run usermod -aG "$(getent group sudo >/dev/null && echo sudo || echo wheel)" "$u"; }
tools_delete_user() { local u; read -r -p "删除用户名: " u; [ "$u" != root ] || { die "禁止删除 root"; return; }; id "$u" >/dev/null 2>&1 || { die "用户不存在"; return; }; confirm "删除用户 $u（保留家目录）？" && run userdel "$u"; }
tools_services() { if command -v systemctl >/dev/null; then systemctl --no-pager --type=service --state=running; else rc-status 2>/dev/null || true; fi; }
tools_cron() { printf '当前用户任务:\n'; crontab -l 2>/dev/null || echo 无; printf '\n系统任务:\n'; ls -la /etc/cron.d /etc/cron.* 2>/dev/null || true; }
tools_logs() { if command -v journalctl >/dev/null; then journalctl -p warning -n 200 --no-pager; else tail -n 200 /var/log/messages 2>/dev/null || tail -n 200 /var/log/syslog 2>/dev/null; fi; }
tools_fail2ban() { case "$PKG_FAMILY" in apt) pkg_install fail2ban;; dnf|yum) pkg_install epel-release; pkg_install fail2ban;; apk) pkg_install fail2ban;; esac; command -v systemctl >/dev/null && run systemctl enable --now fail2ban || true; ok "Fail2Ban 已安装；请按实际 SSH 日志路径检查 jail 状态"; }
