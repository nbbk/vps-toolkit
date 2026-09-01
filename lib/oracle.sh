#!/usr/bin/env bash

oracle_menu() {
  clear_screen
  cat <<'EOF'
甲骨文云脚本合集
--------------------------------------------------------
1. 安装闲置实例保活容器       2. 卸载闲置实例保活容器
3. DD 重装系统               4. R 探长开机脚本
5. 开启 Root 密码登录        6. 关闭 Root 密码登录
7. IPv6 内置诊断/恢复         8. JHB IPv6 恢复脚本
9. 查看 OCI 元数据与网络      0. 返回
--------------------------------------------------------
高风险第三方脚本会先下载到本地、显示来源和 SHA-256，再确认执行。
EOF
  read -r -p "请选择: " c
  case "$c" in
    1) oracle_keepalive_install;; 2) oracle_keepalive_remove;; 3) oracle_reinstall;;
    4) oracle_r_helper;; 5) oracle_root_login_enable;; 6) oracle_root_login_disable;;
    7) oracle_ipv6_repair;; 8) oracle_jhb_ipv6;; 9) oracle_metadata;;
  esac
}

external_fetch() {
  local url="$1" name="$2" dir="$STATE_DIR/external" file
  mkdir -p "$dir"; chmod 700 "$dir"; file="$dir/$name"
  command -v curl >/dev/null 2>&1 || pkg_install curl
  run curl --fail --location --proto '=https' --tlsv1.2 -o "$file" "$url" >&2
  chmod 600 "$file"; printf '来源: %s\nSHA-256: ' "$url" >&2; sha256sum "$file" | tee -a "$LOG_FILE" >&2
  printf '%s' "$file"
}

oracle_keepalive_install() {
  docker_install; docker_require || return
  local cpu mem interval
  read -r -p "CPU 占用范围 [5-10]: " cpu; cpu="${cpu:-5-10}"
  read -r -p "内存占用百分比 [10]: " mem; mem="${mem:-10}"
  read -r -p "测速间隔秒数 [1800]: " interval; interval="${interval:-1800}"
  [[ "$cpu" =~ ^[0-9]{1,2}-[0-9]{1,2}$ && "$mem" =~ ^[0-9]{1,2}$ && "$interval" =~ ^[0-9]+$ ]] || { die "参数格式无效"; return; }
  confirm "将运行第三方镜像 fogforest/lookbusy，继续？" || return 0
  docker rm -f vps-toolkit-lookbusy >/dev/null 2>&1 || true
  run docker run -d --name vps-toolkit-lookbusy --restart unless-stopped --read-only --cap-drop ALL \
    --security-opt no-new-privileges --pids-limit 128 -e "CPU_UTIL=$cpu" -e CPU_CORE=1 -e "MEM_UTIL=$mem" \
    -e "SPEEDTEST_INTERVAL=$interval" fogforest/lookbusy
}
oracle_keepalive_remove() { docker_require || return; confirm "删除保活容器？" && run docker rm -f vps-toolkit-lookbusy; }

oracle_reinstall() {
  cat <<'EOF'
DD 重装目标：
1. Debian 13    2. Debian 12    3. Debian 11
4. Ubuntu 24.04 5. Ubuntu 22.04 6. Ubuntu 20.04
0. 返回
EOF
  local c os ver file
  read -r -p "请选择: " c
  case "$c" in 1) os=debian; ver=13;; 2) os=debian; ver=12;; 3) os=debian; ver=11;; 4) os=ubuntu; ver=24.04;; 5) os=ubuntu; ver=22.04;; 6) os=ubuntu; ver=20.04;; *) return;; esac
  file="$(external_fetch https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh reinstall.sh)" || return
  sed -n '1,100p' "$file"
  warn "执行后将清空系统盘并导致当前 SSH 断开。请先制作 OCI 启动卷备份，并确认串口控制台可用。"
  confirm "确认立即重装为 $os $ver？" || return 0
  chmod 700 "$file"; log WARN "执行 DD 重装：$os $ver"; bash "$file" "$os" "$ver"
}

oracle_r_helper() {
  local file; file="$(external_fetch https://github.com/Yohann0617/oci-helper/releases/latest/download/sh_oci-helper_install.sh oci-helper-install.sh)" || return
  sed -n '1,120p' "$file"; confirm "确认执行 Yohann0617/oci-helper 安装器？" || return 0
  chmod 700 "$file"; bash "$file"
}

oracle_sshd_dropin=/etc/ssh/sshd_config.d/00-vps-toolkit-root-login.conf

oracle_root_login_enable() {
  command -v sshd >/dev/null 2>&1 || { die "未安装 OpenSSH Server"; return; }
  sshd -t || { die "当前 sshd 配置已有错误"; return; }
  warn "Root 密码登录会显著增加暴力破解风险。建议限制 OCI 安全列表来源 IP 并启用 Fail2Ban。"
  confirm "确认开启 Root 密码 SSH 登录？" || return 0
  mkdir -p "$BACKUP_DIR" /etc/ssh/sshd_config.d
  [ -f "$oracle_sshd_dropin" ] && cp -a "$oracle_sshd_dropin" "$BACKUP_DIR/root-login.$(date +%s).bak" || true
  warn "现在设置 root 密码；密码由 passwd 直接读取，本工具不会记录"; passwd root || return
  cat >"$oracle_sshd_dropin" <<'EOF'
# Managed by vps-toolkit
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
EOF
  chmod 600 "$oracle_sshd_dropin"
  if ! sshd -t; then rm -f "$oracle_sshd_dropin"; die "配置校验失败，已撤销"; return; fi
  service_restart ssh sshd || { rm -f "$oracle_sshd_dropin"; service_restart ssh sshd || true; die "SSH 重启失败，已撤销"; return; }
  local effective; effective="$(sshd -T 2>/dev/null)"
  grep -q '^permitrootlogin yes$' <<<"$effective" && grep -q '^passwordauthentication yes$' <<<"$effective" || {
    rm -f "$oracle_sshd_dropin"; service_restart ssh sshd || true; die "有效配置未开启 Root 密码登录，已撤销"; return;
  }
  ok "Root 密码登录已开启。请立即测试新会话，并在 OCI 安全列表限制 SSH 来源 IP"
}

oracle_root_login_disable() {
  confirm "关闭 Root 密码登录并保留密钥登录？" || return 0
  [ -s /root/.ssh/authorized_keys ] || { die "未检测到 /root/.ssh/authorized_keys，拒绝关闭密码登录以避免失联"; return; }
  mkdir -p /etc/ssh/sshd_config.d
  cat >"$oracle_sshd_dropin" <<'EOF'
# Managed by vps-toolkit
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
EOF
  chmod 600 "$oracle_sshd_dropin"; sshd -t || { die "配置校验失败"; return; }
  service_restart ssh sshd; ok "Root 密码登录和普通密码登录已关闭，密钥登录保留"
}

oracle_ipv6_status() {
  printf 'IPv6 地址:\n'; ip -6 address show scope global || true
  printf '\nIPv6 路由:\n'; ip -6 route || true
  printf '\n内核开关:\n'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true
  printf '\n连通性:\n'; ping -6 -c 3 2606:4700:4700::1111 2>/dev/null || warn "IPv6 当前不通"
}

oracle_ipv6_repair() {
  oracle_ipv6_status; confirm "将启用内核 IPv6 开关并持久化（不修改 OCI 控制台配置），继续？" || return 0
  cat >/etc/sysctl.d/99-vps-toolkit-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
EOF
  run sysctl --system
  if command -v netplan >/dev/null 2>&1; then run netplan generate; run netplan apply
  elif command -v systemctl >/dev/null && systemctl is-active NetworkManager >/dev/null 2>&1; then run systemctl restart NetworkManager; fi
  oracle_ipv6_status; warn "若仍不通，请在 OCI VCN/子网分配 IPv6 CIDR，并检查安全列表与路由表"
}

oracle_jhb_ipv6() {
  local file; file="$(external_fetch https://jhb.ovh/jb/v6.sh jhb-ipv6.sh)" || return
  sed -n '1,120p' "$file"; confirm "确认执行参考项目使用的 JHB IPv6 第三方脚本？" || return 0
  chmod 700 "$file"; bash "$file"
}

oracle_metadata() {
  oracle_ipv6_status; printf '\nOCI 实例元数据（敏感字段已隐藏）:\n'
  command -v curl >/dev/null || return 0
  curl -fsS --max-time 2 -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/ 2>/dev/null |
    sed -E 's/(ssh_authorized_keys|user_data)"[[:space:]]*:[[:space:]]*"[^"]*"/\1":"[已隐藏]"/g' || warn "无法访问 OCI 元数据服务"
}
