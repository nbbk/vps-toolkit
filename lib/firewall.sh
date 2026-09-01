#!/usr/bin/env bash

firewall_backend() {
  if command -v ufw >/dev/null; then echo ufw
  elif command -v firewall-cmd >/dev/null; then echo firewalld
  elif command -v nft >/dev/null; then echo nft
  else echo none; fi
}

parse_port_spec() {
  local spec="$1" proto="$2"
  [[ "$proto" = tcp || "$proto" = udp ]] || return 1
  if [[ "$spec" =~ ^([0-9]+)(:([0-9]+))?$ ]]; then
    valid_port "${BASH_REMATCH[1]}" || return 1
    [ -z "${BASH_REMATCH[3]:-}" ] || { valid_port "${BASH_REMATCH[3]}" && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[3]}" ]; }
  else return 1; fi
}

ensure_firewall() {
  local fw; fw="$(firewall_backend)"
  [ "$fw" != none ] && { echo "$fw"; return; }
  warn "未检测到防火墙，将安装发行版默认防火墙"
  case "$PKG_FAMILY" in apt) pkg_install ufw;; dnf|yum) pkg_install firewalld; run systemctl enable --now firewalld;; apk) pkg_install nftables; run rc-update add nftables default;; esac
  firewall_backend
}

firewall_apply() {
  local action="$1" spec="$2" proto="$3" fw label; fw="$(ensure_firewall)"
  parse_port_spec "$spec" "$proto" || { die "端口格式无效；示例 80 或 8000:8100，协议 tcp/udp"; return; }
  case "$fw:$action" in
    ufw:open) run ufw allow "$spec/$proto" ;;
    ufw:close) run ufw delete allow "$spec/$proto" ;;
    firewalld:open) run firewall-cmd --permanent --add-port="${spec/:/-}/$proto"; run firewall-cmd --reload ;;
    firewalld:close) run firewall-cmd --permanent --remove-port="${spec/:/-}/$proto"; run firewall-cmd --reload ;;
    nft:*) die "检测到原生 nftables。为避免覆盖现有规则，请使用 nft 管理器人工维护"; return ;;
    *) die "没有可管理的防火墙"; return ;;
  esac
  [ "$action" = open ] && label="开放" || label="关闭"
  ok "已${label} $spec/$proto"
}

firewall_open_ui() { local p proto; read -r -p "端口或范围（如 443 / 8000:8100）: " p; read -r -p "协议 tcp/udp [tcp]: " proto; firewall_apply open "$p" "${proto:-tcp}"; }
firewall_close_ui() { local p proto; read -r -p "端口或范围: " p; read -r -p "协议 tcp/udp [tcp]: " proto; firewall_apply close "$p" "${proto:-tcp}"; }
firewall_status() {
  local fw; fw="$(firewall_backend)"; say "防火墙后端: $fw"
  case "$fw" in ufw) ufw status verbose;; firewalld) firewall-cmd --state; firewall-cmd --list-all;; nft) nft list ruleset;; *) warn "未安装防火墙";; esac
  printf '\n监听端口:\n'; ss -lntup 2>/dev/null || true
}

firewall_open_all() {
  local fw; fw="$(ensure_firewall)"
  warn "开放全部端口会把所有监听服务暴露到公网，包括数据库、面板和内部 API。"
  confirm "确认开放全部 TCP/UDP 端口？" || return 0
  case "$fw" in
    ufw) run ufw default allow incoming; run ufw --force enable ;;
    firewalld) run firewall-cmd --permanent --add-port=1-65535/tcp; run firewall-cmd --permanent --add-port=1-65535/udp; run firewall-cmd --reload ;;
    nft) die "检测到原生 nftables，拒绝覆盖现有规则"; return ;;
    *) die "没有可管理的防火墙"; return ;;
  esac
  ok "机内防火墙已开放全部端口；云安全组仍需单独配置"
}

firewall_restore_default() {
  local fw; fw="$(firewall_backend)"
  warn "恢复默认拒绝入站前，请确认当前 SSH 端口已经单独放行。"
  confirm "确认撤销全部端口开放？" || return 0
  case "$fw" in
    ufw) run ufw default deny incoming ;;
    firewalld) run firewall-cmd --permanent --remove-port=1-65535/tcp || true; run firewall-cmd --permanent --remove-port=1-65535/udp || true; run firewall-cmd --reload ;;
    *) die "当前防火墙不支持自动恢复"; return ;;
  esac
  ok "已撤销全部端口开放规则"
}
