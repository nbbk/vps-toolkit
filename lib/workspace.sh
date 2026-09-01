#!/usr/bin/env bash

workspace_require() { command -v tmux >/dev/null 2>&1 || { warn "tmux 未安装，正在安装"; pkg_install tmux; }; }
workspace_valid_name() { [[ "${1:-}" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; }

workspace_list() {
  workspace_require
  printf '%b当前工作区：%b\n' "$C_CYAN" "$C_RESET"
  tmux list-sessions -F '  ● #{session_name}  窗口:#{session_windows}  创建:#{session_created_string}' 2>/dev/null || printf '  ○ 暂无工作区\n'
}

workspace_enter() {
  local name="$1"; workspace_valid_name "$name" || { die "工作区名只能包含字母、数字、下划线和连字符"; return; }
  workspace_require
  if tmux has-session -t "=$name" 2>/dev/null; then tmux attach-session -t "=$name"; else tmux new-session -s "$name"; fi
}

workspace_menu() {
  while true; do
  ui_header "后台工作区（tmux）"
  say "即使 SSH 断开，工作区中的任务也会继续运行。"
  say "退出但保留任务：按 Ctrl+b，再按 d。"
  ui_line; workspace_list; ui_line
  printf '  1-10. 进入对应编号工作区\n  21. SSH 登录自动驻留\n  22. 创建/进入自定义工作区\n  23. 进入已有工作区\n  24. 删除指定工作区\n  25. 关闭 SSH 自动驻留\n   0. 返回\n'
  ui_line
  local c name; read -r -p "请选择: " c
  case "$c" in
    [1-9]|10) workspace_enter "workspace-$c";;
    21) workspace_autostart_enable;;
    22) read -r -p "工作区名称: " name; workspace_enter "$name";;
    23) read -r -p "已有工作区名称: " name; workspace_valid_name "$name" && tmux has-session -t "=$name" 2>/dev/null && tmux attach -t "=$name" || die "工作区不存在";;
    24) read -r -p "删除工作区名称: " name; workspace_valid_name "$name" || return; tmux has-session -t "=$name" 2>/dev/null || { die "工作区不存在"; return; }; confirm "终止并删除 $name？" && tmux kill-session -t "=$name";;
    25) workspace_autostart_disable;; 0) break;; *) warn "无效选择";;
  esac
  submenu_pause
  done
}

workspace_autostart_enable() {
  workspace_require
  local user home profile name
  read -r -p "启用自动驻留的用户 [${SUDO_USER:-root}]: " user; user="${user:-${SUDO_USER:-root}}"
  id "$user" >/dev/null 2>&1 || { die "用户不存在"; return; }
  read -r -p "默认工作区名称 [workspace-1]: " name; name="${name:-workspace-1}"; workspace_valid_name "$name" || { die "名称无效"; return; }
  home="$(getent passwd "$user" | cut -d: -f6)"; profile="$home/.profile"; touch "$profile"
  sed -i '/# BEGIN VPS-TOOLKIT TMUX/,/# END VPS-TOOLKIT TMUX/d' "$profile"
  cat >>"$profile" <<EOF
# BEGIN VPS-TOOLKIT TMUX
if [ -n "\${SSH_CONNECTION:-}" ] && [ -z "\${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
  tmux attach-session -t '=$name' 2>/dev/null || tmux new-session -s '$name'
fi
# END VPS-TOOLKIT TMUX
EOF
  chown "$user":"$(id -gn "$user")" "$profile"; ok "用户 $user 下次 SSH 登录将进入 $name"
}

workspace_autostart_disable() {
  local user home profile
  read -r -p "关闭自动驻留的用户 [${SUDO_USER:-root}]: " user; user="${user:-${SUDO_USER:-root}}"; id "$user" >/dev/null 2>&1 || { die "用户不存在"; return; }
  home="$(getent passwd "$user" | cut -d: -f6)"; profile="$home/.profile"; [ -f "$profile" ] && sed -i '/# BEGIN VPS-TOOLKIT TMUX/,/# END VPS-TOOLKIT TMUX/d' "$profile"
  ok "已关闭用户 $user 的 SSH 自动驻留"
}
