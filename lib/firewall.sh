#!/usr/bin/env bash

firewall_backend() {
  if command -v ufw >/dev/null; then echo ufw
  elif command -v firewall-cmd >/dev/null; then echo firewalld
  elif command -v nft >/dev/null; then echo nft
  else echo none; fi
}

parse_port_spec() {
  local spec="$1" proto="$2" start end
  [[ "$proto" = tcp || "$proto" = udp ]] || return 1
  if [[ "$spec" =~ ^([0-9]+)(:([0-9]+))?$ ]]; then
    start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[3]:-}"
    valid_port "$start" || return 1
    [ -z "$end" ] || { valid_port "$end" && [ "$start" -le "$end" ]; }
  else return 1; fi
}

ensure_firewall() {
  FIREWALL_BACKEND="$(firewall_backend)"
  [ "$FIREWALL_BACKEND" != none ] && return 0
  warn "未检测到防火墙，将安装发行版默认防火墙"
  case "$PKG_FAMILY" in
    apt) pkg_install ufw || return 1;;
    dnf|yum) pkg_install firewalld && run systemctl enable --now firewalld || return 1;;
    apk) pkg_install nftables && run rc-update add nftables default || return 1;;
    *) die "当前系统没有可用的防火墙安装方案"; return 1;;
  esac
  FIREWALL_BACKEND="$(firewall_backend)"
  [ "$FIREWALL_BACKEND" != none ] || { die "防火墙安装后仍不可用"; return 1; }
}

firewall_rule_present() {
  local fw="$1" spec="$2" proto="$3" normalized
  case "$fw" in
    ufw) ufw status 2>/dev/null | awk -v rule="$spec/$proto" '$1==rule && $2=="ALLOW"{found=1} END{exit !found}' ;;
    firewalld) normalized="${spec/:/-}"; firewall-cmd --query-port="$normalized/$proto" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

firewall_apply() {
  local action="$1" spec="$2" proto="$3" fw label own_transaction=0 already=0
  # Consumed by SSH rollback logic in another sourced module.
  # shellcheck disable=SC2034
  FIREWALL_LAST_CHANGED=0
  parse_port_spec "$spec" "$proto" || { die "端口格式无效；示例 80 或 8000:8100，协议 tcp/udp"; return; }
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 防火墙 %s %s/%s\n' "$action" "$spec" "$proto"; plan_only; return 0; fi
  if ! ensure_firewall; then [ -z "${VMT_TRANSACTION_ID:-}" ] || transaction_finish failed; return 1; fi
  fw="$FIREWALL_BACKEND"
  firewall_rule_present "$fw" "$spec" "$proto" && already=1 || true
  if [ "$action" = open ] && [ "$already" = 1 ]; then
    ok "$spec/$proto 已经放行，无需修改"; return 0
  fi
  if [ "$action" = close ] && [ "$already" = 0 ]; then
    ok "$spec/$proto 原本未放行，无需修改"; return 0
  fi
  if [ "${VMT_UNDOING:-0}" != 1 ]; then
    if [ -z "${VMT_TRANSACTION_ID:-}" ]; then transaction_begin firewall || return; own_transaction=1; fi
    [ "$action" = open ] && transaction_note "firewall_undo=close|$spec|$proto" || transaction_note "firewall_undo=open|$spec|$proto"
  fi
  case "$fw:$action" in
    ufw:open) run ufw allow "$spec/$proto" || { transaction_finish failed; return 1; } ;;
    ufw:close) run ufw delete allow "$spec/$proto" || { transaction_finish failed; return 1; } ;;
    firewalld:open)
      run firewall-cmd --permanent --add-port="${spec/:/-}/$proto" || { transaction_finish failed; return 1; }
      if ! run firewall-cmd --reload; then firewall-cmd --permanent --remove-port="${spec/:/-}/$proto" >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true; transaction_finish rolled-back; die "firewalld 重载失败，已尝试撤销规则"; return; fi
      ;;
    firewalld:close)
      run firewall-cmd --permanent --remove-port="${spec/:/-}/$proto" || { transaction_finish failed; return 1; }
      if ! run firewall-cmd --reload; then firewall-cmd --permanent --add-port="${spec/:/-}/$proto" >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true; transaction_finish rolled-back; die "firewalld 重载失败，已尝试恢复规则"; return; fi
      ;;
    nft:*) die "检测到原生 nftables。为避免覆盖现有规则，请使用 nft 管理器人工维护"; transaction_finish failed; return 1 ;;
    *) die "没有可管理的防火墙"; transaction_finish failed; return 1 ;;
  esac
  # shellcheck disable=SC2034
  FIREWALL_LAST_CHANGED=1
  [ "$action" = open ] && label="开放" || label="关闭"
  [ "$own_transaction" = 1 ] && transaction_finish success
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
  local fw tcp_existed=0 udp_existed=0 prior_incoming prior_active state_file="$STATE_DIR/firewall-open-all.state"
  risk_preview "开放全部端口" "允许全部 TCP/UDP 入站，可能暴露数据库和内部 API" "nftables 会完整备份；UFW/firewalld 可由菜单第 20 项撤销" || return 0
  if plan_only; then printf '[DRY-RUN] 不会更改防火墙默认策略。\n'; return 0; fi
  operation_lock_acquire firewall-all || return
  ensure_firewall || { operation_lock_release; return 1; }; fw="$FIREWALL_BACKEND"
  case "$fw" in
    ufw)
      prior_incoming="$(ufw status verbose 2>/dev/null | sed -nE 's/^Default: ([a-z]+) \(incoming\).*/\1/p' | head -n1)"
      [[ "$prior_incoming" =~ ^(allow|deny|reject)$ ]] || { operation_lock_release; die "无法识别 UFW 原入站策略，拒绝开放全部端口"; return; }
      prior_active="$(ufw status 2>/dev/null | awk 'NR==1{print $2}')"; [ "$prior_active" = active ] || prior_active=inactive
      run ufw default allow incoming && run ufw --force enable || { operation_lock_release; return 1; }
      printf 'backend=ufw\nprior_incoming=%s\nprior_active=%s\n' "$prior_incoming" "$prior_active" >"$state_file"
      ;;
    firewalld)
      firewall-cmd --permanent --query-port=1-65535/tcp >/dev/null 2>&1 && tcp_existed=1 || true
      firewall-cmd --permanent --query-port=1-65535/udp >/dev/null 2>&1 && udp_existed=1 || true
      if ! run firewall-cmd --permanent --add-port=1-65535/tcp || ! run firewall-cmd --permanent --add-port=1-65535/udp || ! run firewall-cmd --reload; then
        [ "$tcp_existed" = 1 ] || firewall-cmd --permanent --remove-port=1-65535/tcp >/dev/null 2>&1 || true
        [ "$udp_existed" = 1 ] || firewall-cmd --permanent --remove-port=1-65535/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        operation_lock_release; die "开放全部端口失败，已尝试撤销整段规则"; return
      fi
      printf 'backend=firewalld\nadded_tcp=%s\nadded_udp=%s\n' "$((1-tcp_existed))" "$((1-udp_existed))" >"$state_file"
      ;;
    nft)
      local backup
      backup="$BACKUP_DIR/nftables-before-open-all-$(date +%Y%m%d-%H%M%S).nft"
      nft list ruleset >"$backup" || { operation_lock_release; die "无法备份 nftables 规则"; return; }
      run nft flush ruleset || { operation_lock_release; die "清空 nftables 规则失败"; return; }
      printf '%s\n' "$backup" >"$STATE_DIR/nftables-last-backup" || { operation_lock_release; die "无法记录 nftables 备份路径"; return; }
      printf 'backend=nft\nbackup=%s\n' "$backup" >"$state_file"
      warn "nftables 已清空，原规则备份：$backup"
      ;;
    *) operation_lock_release; die "没有可管理的防火墙"; return ;;
  esac
  chmod 600 "$state_file"
  operation_lock_release
  ok "机内防火墙已开放全部端口；云安全组仍需单独配置"
}

firewall_restore_default() {
  local fw state_file="$STATE_DIR/firewall-open-all.state" recorded prior_incoming prior_active added_tcp added_udp
  fw="$(firewall_backend)"
  risk_preview "恢复入站防火墙" "撤销开放全部端口规则" "必须先单独放行当前 SSH 端口，否则可能失联" || return 0
  if plan_only; then printf '[DRY-RUN] 不会恢复防火墙规则。\n'; return 0; fi
  operation_lock_acquire firewall-all || return
  [ -f "$state_file" ] || { operation_lock_release; die "没有找到本工具记录的开放全部端口状态"; return; }
  recorded="$(sed -n 's/^backend=//p' "$state_file")"
  [ "$recorded" = "$fw" ] || { operation_lock_release; die "当前防火墙 $fw 与记录的 $recorded 不一致，拒绝自动恢复"; return; }
  case "$fw" in
    ufw)
      prior_incoming="$(sed -n 's/^prior_incoming=//p' "$state_file")"; prior_active="$(sed -n 's/^prior_active=//p' "$state_file")"
      [[ "$prior_incoming" =~ ^(allow|deny|reject)$ ]] && [[ "$prior_active" =~ ^(active|inactive)$ ]] || { operation_lock_release; die "UFW 恢复记录无效"; return; }
      run ufw default "$prior_incoming" incoming || { operation_lock_release; return 1; }
      [ "$prior_active" = active ] || run ufw --force disable || { operation_lock_release; return 1; }
      ;;
    firewalld)
      added_tcp="$(sed -n 's/^added_tcp=//p' "$state_file")"; added_udp="$(sed -n 's/^added_udp=//p' "$state_file")"
      [[ "$added_tcp" =~ ^[01]$ && "$added_udp" =~ ^[01]$ ]] || { operation_lock_release; die "firewalld 恢复记录无效"; return; }
      [ "$added_tcp" = 0 ] || firewall-cmd --permanent --remove-port=1-65535/tcp >/dev/null 2>&1 || true
      [ "$added_udp" = 0 ] || firewall-cmd --permanent --remove-port=1-65535/udp >/dev/null 2>&1 || true
      run firewall-cmd --reload || { operation_lock_release; return 1; }
      ;;
    nft)
      local pointer="$STATE_DIR/nftables-last-backup" backup
      [ -f "$pointer" ] || { operation_lock_release; die "没有找到本工具创建的 nftables 备份"; return; }
      backup="$(cat "$pointer")"; [ -f "$backup" ] || { operation_lock_release; die "nftables 备份文件不存在"; return; }
      run nft -f "$backup" || { operation_lock_release; die "恢复 nftables 规则失败"; return; }
      rm -f -- "$state_file" "$pointer"
      operation_lock_release; ok "已恢复 nftables 规则：$backup"; return
      ;;
    *) operation_lock_release; die "当前防火墙不支持自动恢复"; return ;;
  esac
  rm -f -- "$state_file"
  operation_lock_release
  ok "已撤销全部端口开放规则"
}
