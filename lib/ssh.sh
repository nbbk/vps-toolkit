#!/usr/bin/env bash

sshd_config_file() { [ -f /etc/ssh/sshd_config ] && echo /etc/ssh/sshd_config || return 1; }
current_ssh_ports() {
  command -v sshd >/dev/null && sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -nu || echo 22
}

ssh_socket_activation_active() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-enabled --quiet ssh.socket 2>/dev/null
}

restore_optional_file() {
  local target="$1" saved="$2" existed="$3"
  if [ "$existed" = 1 ]; then cp -a "$saved" "$target"; else rm -f -- "$target"; fi
}

change_ssh_port_ui() {
  local port; printf '当前 SSH 端口: '; current_ssh_ports | paste -sd, -
  read -r -p "新 SSH 端口: " port
  valid_port "$port" || { die "端口必须为 1-65535"; return; }
  change_ssh_port "$port"
}

change_ssh_port() {
  local new="$1" config dropin backup old_ports dropin_backup had_dropin=0
  local socket_override=/etc/systemd/system/ssh.socket.d/override.conf
  local socket_backup had_socket_override=0 use_socket=0
  config="$(sshd_config_file)" || { die "未安装 OpenSSH Server"; return; }
  command -v sshd >/dev/null || { die "找不到 sshd"; return; }
  sshd -t || { die "当前 SSH 配置已有语法错误"; return; }
  old_ports="$(current_ssh_ports | paste -sd, -)"
  if current_ssh_ports | grep -qx "$new"; then ok "SSH 已配置为端口 $new，无需修改"; return 0; fi
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$new$" && { die "端口 $new 已被其他程序占用"; return; }
  confirm "将先开放 $new/tcp，再修改 SSH；旧端口 $old_ports 暂不关闭，继续？" || return 0
  firewall_apply open "$new" tcp
  backup="$BACKUP_DIR/sshd_config.$(date +%Y%m%d-%H%M%S).bak"; cp -a "$config" "$backup"
  mkdir -p /etc/ssh/sshd_config.d
  dropin=/etc/ssh/sshd_config.d/90-vps-toolkit-port.conf
  dropin_backup="$backup.dropin"
  if [ -f "$dropin" ]; then cp -a "$dropin" "$dropin_backup"; had_dropin=1; fi
  printf '# Managed by vps-toolkit\nPort %s\n' "$new" >"$dropin"; chmod 600 "$dropin"
  if ! sshd -t; then restore_optional_file "$dropin" "$dropin_backup" "$had_dropin"; die "新配置校验失败，已回滚"; return; fi

  # Ubuntu 22.10+ may let systemd ssh.socket own port 22. In that mode the
  # sshd Port directive alone is valid but has no effect on the listener.
  if ssh_socket_activation_active; then
    use_socket=1
    socket_backup="$backup.ssh-socket-override"
    mkdir -p "$(dirname "$socket_override")"
    if [ -f "$socket_override" ]; then cp -a "$socket_override" "$socket_backup"; had_socket_override=1; fi
    printf '[Socket]\nListenStream=\n' >"$socket_override"
    while IFS= read -r old_port; do
      [ -n "$old_port" ] && [ "$old_port" != "$new" ] && printf 'ListenStream=%s\n' "$old_port" >>"$socket_override"
    done < <(printf '%s\n' "$old_ports" | tr ',' '\n')
    printf 'ListenStream=%s\n' "$new" >>"$socket_override"
    if ! systemctl daemon-reload || ! systemctl restart ssh.socket; then
      restore_optional_file "$dropin" "$dropin_backup" "$had_dropin"
      restore_optional_file "$socket_override" "$socket_backup" "$had_socket_override"
      systemctl daemon-reload || true; systemctl restart ssh.socket || true
      die "SSH Socket 重启失败，已回滚"; return
    fi
  elif ! service_restart ssh sshd; then
    restore_optional_file "$dropin" "$dropin_backup" "$had_dropin"
    service_restart ssh sshd || true
    die "SSH 重启失败，已回滚"; return
  fi
  local listening=0
  for _ in 1 2 3 4 5; do ss -H -ltn | awk '{print $4}' | grep -Eq "(^|:)$new$" && { listening=1; break; }; sleep 1; done
  if [ "$listening" != 1 ]; then
    restore_optional_file "$dropin" "$dropin_backup" "$had_dropin"
    if [ "$use_socket" = 1 ]; then
      restore_optional_file "$socket_override" "$socket_backup" "$had_socket_override"
      systemctl daemon-reload || true; systemctl restart ssh.socket || true
    else
      service_restart ssh sshd || true
    fi
    die "新端口未监听，已回滚"; return
  fi
  ok "SSH 已监听 $new；旧端口未自动关闭。请新开终端验证登录后再手动关闭旧端口"
}

change_password() {
  local user
  read -r -p "要修改密码的用户 [${SUDO_USER:-root}]: " user; user="${user:-${SUDO_USER:-root}}"
  id "$user" >/dev/null 2>&1 || { die "用户不存在"; return; }
  warn "密码不会被脚本读取或保存，将交给系统 passwd 安全输入"
  passwd "$user"
}

ssh_security_check() {
  local config; config="$(sshd_config_file)" || { die "未安装 OpenSSH Server"; return; }
  sshd -t && ok "sshd 配置语法正常" || warn "sshd 配置语法异常"
  local effective; effective="$(sshd -T 2>/dev/null || true)"
  for key in permitrootlogin passwordauthentication pubkeyauthentication permitemptypasswords x11forwarding; do
    printf '%-24s %s\n' "$key" "$(awk -v k="$key" '$1==k{print $2; exit}' <<<"$effective")"
  done
  printf '端口: '; current_ssh_ports | paste -sd, -
  warn "建议：先配置并验证密钥登录，再关闭密码登录；本工具不会自动锁死当前会话"
}
