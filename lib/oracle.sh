#!/usr/bin/env bash

oracle_menu() {
  cat <<'EOF'
甲骨文云工具合集（隔离区）
--------------------------------------------------------
1. 安装闲置实例保活容器（lookbusy，可配置低负载）
2. 卸载闲置实例保活容器
3. 下载 DD 重装脚本供人工审计（不自动执行）
4. 下载 R 探长开机脚本供人工审计（不自动执行）
5. SSH Root/密码登录说明（不自动降低安全性）
6. IPv6 诊断与修复建议
0. 返回
--------------------------------------------------------
说明：第三方脚本会变更，下载后只展示 SHA-256 和保存路径。
EOF
  read -r -p "请选择: " c
  case "$c" in
    1) oracle_keepalive_install;; 2) oracle_keepalive_remove;;
    3) external_download "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh" "reinstall.sh";;
    4) external_download "https://raw.githubusercontent.com/spiritLHLS/Oracle-server-keep-alive-script/main/oalive.sh" "oracle-alive.sh";;
    5) oracle_root_login_note;; 6) oracle_ipv6_check;;
  esac
}

external_download() {
  local url="$1" name="$2" dir="$STATE_DIR/external" file
  mkdir -p "$dir"; chmod 700 "$dir"; file="$dir/$name"
  warn "来源：$url"
  confirm "仅下载到 $file（不会执行），继续？" || return 0
  if command -v curl >/dev/null; then run curl --fail --location --proto '=https' --tlsv1.2 -o "$file" "$url"
  elif command -v wget >/dev/null; then run wget --https-only -O "$file" "$url"
  else pkg_install curl; run curl --fail --location --proto '=https' --tlsv1.2 -o "$file" "$url"; fi
  chmod 600 "$file"
  printf 'SHA-256: '; sha256sum "$file" | tee -a "$LOG_FILE"
  ok "已下载但未执行：$file。请先审计，再手动 chmod +x 并运行"
}

oracle_keepalive_install() {
  docker_install; command -v docker >/dev/null || return
  local cpu mem interval
  read -r -p "CPU 占用范围 [5-10]: " cpu; cpu="${cpu:-5-10}"
  read -r -p "内存占用百分比 [10]: " mem; mem="${mem:-10}"
  read -r -p "测速间隔秒数 [1800]: " interval; interval="${interval:-1800}"
  [[ "$cpu" =~ ^[0-9]{1,2}-[0-9]{1,2}$ && "$mem" =~ ^[0-9]{1,2}$ && "$interval" =~ ^[0-9]+$ ]] || { die "参数格式无效"; return; }
  confirm "将运行第三方镜像 fogforest/lookbusy；继续？" || return 0
  docker rm -f vps-toolkit-lookbusy >/dev/null 2>&1 || true
  run docker run -d --name vps-toolkit-lookbusy --restart unless-stopped --read-only --cap-drop ALL \
    --security-opt no-new-privileges --pids-limit 128 -e "CPU_UTIL=$cpu" -e CPU_CORE=1 -e "MEM_UTIL=$mem" \
    -e "SPEEDTEST_INTERVAL=$interval" fogforest/lookbusy
}
oracle_keepalive_remove() { confirm "删除保活容器？" && run docker rm -f vps-toolkit-lookbusy; }
oracle_root_login_note() {
  warn "不建议开放 root 密码登录。推荐：普通 sudo 用户 + Ed25519 密钥 + PasswordAuthentication no。"
  warn "如确有需要，请先确保云控制台救援通道可用，再人工修改 sshd_config 并运行 sshd -t。"
}
oracle_ipv6_check() {
  printf 'IPv6 地址:\n'; ip -6 address show scope global || true
  printf '\nIPv6 路由:\n'; ip -6 route || true
  printf '\n内核开关:\n'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true
  printf '\n连通性:\n'; ping -6 -c 3 2606:4700:4700::1111 2>/dev/null || warn "IPv6 不通；请先检查 OCI VCN/子网 IPv6 CIDR、安全列表和实例路由"
}
