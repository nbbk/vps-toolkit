#!/usr/bin/env bash

SOURCE_MANIFEST="$VMT_BASE_DIR/config/sources.tsv"

source_manifest_show() {
  printf '%-20s %-12s %-10s %s\n' "ID" "策略" "版本/引用" "来源"
  awk -F '\t' 'BEGIN{OFS="\t"} !/^#/ && NF>=5 {printf "%-20s %-12s %-10s %s\n",$1,$4,$3,$2}' "$SOURCE_MANIFEST"
}

source_manifest_lookup() {
  local id="$1"; awk -F '\t' -v id="$id" '!/^#/ && $1==id {print; exit}' "$SOURCE_MANIFEST"
}

external_fetch_id() {
  local id="$1" row url ref policy expected name file actual
  row="$(source_manifest_lookup "$id")"; [ -n "$row" ] || { die "第三方来源未登记：$id"; return 1; }
  IFS=$'\t' read -r _ url ref policy expected name <<<"$row"
  file="$(external_fetch "$url" "$name")" || return
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$policy" = pinned-sha256 ] && [ "$expected" != "$actual" ]; then die "第三方脚本校验失败：$id"; return 1; fi
  printf '来源编号: %s\n版本/引用: %s\n校验策略: %s\n' "$id" "$ref" "$policy" >&2
  printf '%s' "$file"
}

extensions_menu() {
  while true; do
    ui_header "扩展中心（第三方功能）"
    cat <<'EOF'
1. 甲骨文云工具合集     2. 测试脚本合集
3. LDNMP/建站与面板     4. 重装系统
5. 查看第三方来源清单
0. 返回
EOF
    local c; read -r -p "请选择: " c
    case "$c" in 1) oracle_menu;; 2) testsuite_menu;; 3) web_menu;; 4) reinstall_menu;; 5) source_manifest_show;; 0) break;; *) warn "无效选择";; esac
    submenu_pause
  done
}
