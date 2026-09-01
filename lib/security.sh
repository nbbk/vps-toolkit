#!/usr/bin/env bash

security_audit() {
  local score=100 findings=0 effective=""
  command -v sshd >/dev/null 2>&1 && effective="$(sshd -T 2>/dev/null || true)"
  ui_header "安全体检（只读）"
  security_check "防火墙已启用" firewall_is_active || { score=$((score-20)); findings=$((findings+1)); }
  if grep -q '^permitrootlogin yes$' <<<"$effective"; then warn "Root SSH 登录已开放"; score=$((score-15)); findings=$((findings+1)); else ok "Root SSH 登录未完全开放"; fi
  if grep -q '^passwordauthentication yes$' <<<"$effective"; then warn "SSH 密码认证已开放"; score=$((score-10)); findings=$((findings+1)); else ok "SSH 密码认证已关闭或未启用"; fi
  if awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null | grep -q .; then warn "存在空密码账户"; score=$((score-30)); findings=$((findings+1)); else ok "未发现空密码账户"; fi
  if command -v fail2ban-client >/dev/null 2>&1; then ok "Fail2Ban 已安装"; else warn "未安装 Fail2Ban"; score=$((score-5)); findings=$((findings+1)); fi
  if ss -lnt 2>/dev/null | grep -Eq '0\.0\.0\.0:(3306|5432|6379|27017)|\[::\]:(3306|5432|6379|27017)'; then warn "数据库/缓存端口可能监听公网"; score=$((score-20)); findings=$((findings+1)); else ok "未发现常见数据库端口监听所有地址"; fi
  df -P / | awk 'NR==2{gsub("%","",$5); exit ($5>=90)}' || { warn "根分区使用率达到 90%"; score=$((score-10)); findings=$((findings+1)); }
  df -Pi / | awk 'NR==2{gsub("%","",$5); exit ($5>=90)}' || { warn "根分区 inode 使用率达到 90%"; score=$((score-10)); findings=$((findings+1)); }
  if [ "$PKG_FAMILY" = apt ]; then
    local updates; updates="$(apt-get -s upgrade 2>/dev/null | awk '/^Inst /{n++} END{print n+0}')"
    [ "$updates" -eq 0 ] && ok "没有待安装的软件更新" || { warn "有 $updates 个待安装更新"; score=$((score-5)); findings=$((findings+1)); }
  fi
  command -v lastb >/dev/null 2>&1 && printf '最近失败登录（最多 5 条）：\n' && lastb -n 5 2>/dev/null || true
  command -v timedatectl >/dev/null 2>&1 && timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qx yes && ok "时间同步正常" || warn "未确认时间同步状态"
  printf '\n安全评分：%s/100，发现 %s 项建议。评分仅用于快速排查，不代表合规认证。\n' "$score" "$findings"
}

security_check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; return 0; else warn "$label：未通过"; return 1; fi; }
firewall_is_active() {
  ufw status 2>/dev/null | grep -q 'Status: active' || firewall-cmd --state 2>/dev/null | grep -q running || nft list ruleset 2>/dev/null | grep -q 'hook input'
}
