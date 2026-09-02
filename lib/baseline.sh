#!/usr/bin/env bash

BASELINE_DIR="${VMT_BASELINE_DIR:-$STATE_DIR/baseline}"

baseline_collect() {
  local out="$1"
  {
    echo '# VPS Toolkit state baseline'
    echo '[identity]'; printf 'hostname=%s\nos=%s\nkernel=%s\n' "$(hostname)" "$OS_PRETTY" "$(uname -r)"
    echo '[ssh-config-hashes]'; find /etc/ssh -maxdepth 2 -type f \( -name '*.conf' -o -name sshd_config \) -print 2>/dev/null | sort | while IFS= read -r file; do sha256sum "$file"; done || true
    echo '[toolkit-sysctl-hashes]'; find /etc/sysctl.d -maxdepth 1 -type f -name '*vps-toolkit*' -print 2>/dev/null | sort | while IFS= read -r file; do sha256sum "$file"; done || true
    echo '[admin-users]'; awk -F: '$3==0{print $1":"$3}' /etc/passwd; getent group sudo wheel 2>/dev/null | sort || true
    echo '[listening-tcp]'; ss -H -lnt 2>/dev/null | awk '{print $4}' | sort -u || true
    echo '[cron-hashes]'; find /etc/cron.d /var/spool/cron -maxdepth 2 -type f -print 2>/dev/null | sort | while IFS= read -r file; do sha256sum "$file"; done || true
    echo '[package-sources]'; find /etc/apt/sources.list /etc/apt/sources.list.d /etc/yum.repos.d /etc/apk/repositories -maxdepth 2 -type f -print 2>/dev/null | sort | while IFS= read -r file; do sha256sum "$file"; done || true
    echo '[docker]'; command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}|{{.Image}}|{{.Ports}}' 2>/dev/null | sort || true
    echo '[firewall]'
    case "$(detect_firewall_backend)" in
      ufw) ufw status verbose 2>/dev/null || true;;
      firewalld) firewall-cmd --list-all-zones 2>/dev/null || true;;
      nftables) nft --stateless list ruleset 2>/dev/null || nft list ruleset 2>/dev/null || true;;
      *) echo none;;
    esac
  } >"$out"
  chmod 600 "$out"
}

baseline_create() {
  local target="$BASELINE_DIR/current.txt"
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 将采集 SSH、sysctl、管理员、监听端口、计划任务、软件源、Docker 与防火墙基线。\n'; plan_only; return 0; fi
  mkdir -p "$BASELINE_DIR"
  if [ -f "$target" ]; then
    risk_preview "更新系统基线" "用当前状态替换原基线" "旧基线会保存到历史目录" || return 0
    cp -a "$target" "$BASELINE_DIR/baseline-$(date +%Y%m%d-%H%M%S).txt"
  fi
  baseline_collect "$target"; ok "系统状态基线已保存：$target"
}

baseline_check() {
  local target="$BASELINE_DIR/current.txt" now report
  [ -f "$target" ] || { die "尚未创建系统基线"; return; }
  now="$(mktemp)"; report="$BASELINE_DIR/drift-$(date +%Y%m%d-%H%M%S).diff"; baseline_collect "$now"
  if diff -u "$target" "$now" >"$report"; then rm -f -- "$report"; ok "没有检测到基线变化"
  else chmod 600 "$report"; warn "检测到状态变化：$report"; sed -n '1,200p' "$report"; fi
  rm -f -- "$now"
}

baseline_menu() {
  while true; do
    ui_header "系统状态基线"
    cat <<'EOF'
1. 创建/更新基线   2. 检查当前变化
3. 查看历史报告
0. 返回
EOF
    local c; read -r -p "请选择: " c
    case "$c" in 1) baseline_create;; 2) baseline_check;; 3) find "$BASELINE_DIR" -maxdepth 1 -type f -print 2>/dev/null | sed 's|.*/||' | sort;; 0) break;; *) warn "无效选择";; esac
    submenu_pause
  done
}
