#!/usr/bin/env bash

SOURCE_MANIFEST="$VMT_BASE_DIR/config/sources.tsv"
EXTENSION_MANIFEST="$VMT_BASE_DIR/config/extensions.tsv"
EXTENSION_DISABLED_FILE="$STATE_DIR/extensions.disabled"

extension_enabled() { ! grep -Fxq "$1" "$EXTENSION_DISABLED_FILE" 2>/dev/null; }
extension_list() {
  local id name _entry risk _default state
  printf '%-12s %-22s %-10s %s\n' "ID" "扩展" "风险" "状态"
  while IFS=$'\t' read -r id name _entry risk _default; do
    [[ "$id" = \#* || -z "$id" ]] && continue
    extension_enabled "$id" && state=enabled || state=disabled
    printf '%-12s %-22s %-10s %s\n' "$id" "$name" "$risk" "$state"
  done <"$EXTENSION_MANIFEST"
}
extension_set() {
  local id="$1" state="$2"
  [[ "$id" =~ ^[a-z0-9_-]+$ ]] || { die "扩展 ID 格式无效"; return; }
  [[ "$state" = enabled || "$state" = disabled ]] || { die "扩展状态无效"; return; }
  awk -F '\t' -v id="$id" '$1==id{found=1} END{exit !found}' "$EXTENSION_MANIFEST" || { die "未知扩展：$id"; return; }
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 将扩展 %s 设为 %s\n' "$id" "$state"; plan_only; return 0; fi
  mkdir -p "$STATE_DIR"; touch "$EXTENSION_DISABLED_FILE"
  if [ "$state" = enabled ]; then sed -i "\|^${id}$|d" "$EXTENSION_DISABLED_FILE"; else grep -Fxq "$id" "$EXTENSION_DISABLED_FILE" || echo "$id" >>"$EXTENSION_DISABLED_FILE"; fi
  ok "扩展 $id 已设为 $state"
}
extension_launch() {
  local id="$1" entry risk
  extension_enabled "$id" || { die "扩展 $id 已禁用"; return; }
  entry="$(awk -F '\t' -v id="$id" '$1==id{print $3}' "$EXTENSION_MANIFEST")"
  risk="$(awk -F '\t' -v id="$id" '$1==id{print $4}' "$EXTENSION_MANIFEST")"
  [[ "$entry" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && declare -F "$entry" >/dev/null || { die "扩展入口无效：$id"; return; }
  printf '扩展：%s｜风险：%s｜注册表：%s\n' "$id" "$risk" "$EXTENSION_MANIFEST"
  "$entry"
}

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
5. 查看第三方来源清单   6. 查看扩展状态
7. 启用扩展             8. 禁用扩展
0. 返回
EOF
    local c id; read -r -p "请选择: " c
    case "$c" in
      1) extension_launch oracle;; 2) extension_launch tests;;
      3) extension_launch web;; 4) extension_launch reinstall;;
      5) source_manifest_show;; 6) extension_list;;
      7) extension_list; read -r -p "扩展 ID: " id; extension_set "$id" enabled;;
      8) extension_list; read -r -p "扩展 ID: " id; extension_set "$id" disabled;;
      0) break;; *) warn "无效选择";;
    esac
    submenu_pause
  done
}
