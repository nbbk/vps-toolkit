#!/usr/bin/env bash

MANAGED_BACKUP_DIR="${VMT_MANAGED_BACKUP_DIR:-$STATE_DIR/managed-backups}"

managed_backup_file() {
  local module="$1" source="$2" stamp dir
  [ -e "$source" ] || return 0
  stamp="$(date +%Y%m%d-%H%M%S)-$$"; dir="$MANAGED_BACKUP_DIR/$stamp"
  mkdir -p "$dir/payload"
  cp -a -- "$source" "$dir/payload/item"
  printf 'module=%s\nsource=%s\ntype=file\ncreated=%s\nversion=%s\n' "$module" "$source" "$(date -Is)" "$TOOL_VERSION" >"$dir/metadata"
  sha256sum "$dir/payload/item" >"$dir/sha256"
  chmod -R go-rwx "$dir"
  log INFO "BACKUP module=$module source=$source id=$stamp"
  printf '%s' "$stamp"
}

managed_backup_list() {
  printf '%-24s %-16s %s\n' "ID" "模块" "原路径"
  local meta id module source
  for meta in "$MANAGED_BACKUP_DIR"/*/metadata; do
    [ -f "$meta" ] || continue; id="$(basename "$(dirname "$meta")")"
    module="$(sed -n 's/^module=//p' "$meta")"; source="$(sed -n 's/^source=//p' "$meta")"
    printf '%-24s %-16s %s\n' "$id" "$module" "$source"
  done
}

managed_backup_restore() {
  local id="$1" dir="$MANAGED_BACKUP_DIR/$id" meta source
  meta="$dir/metadata"; [ -f "$meta" ] || { die "备份不存在：$id"; return; }
  source="$(sed -n 's/^source=//p' "$meta")"
  case "$source" in /etc/*|/opt/*|/var/lib/*) ;; *) die "拒绝恢复到不安全路径：$source"; return;; esac
  sha256sum -c "$dir/sha256" --status || { die "备份校验失败"; return; }
  risk_preview "恢复配置备份" "覆盖路径：$source" "回滚方式：恢复前会再次制作当前文件备份" || return 0
  [ -e "$source" ] && managed_backup_file pre-restore "$source" >/dev/null
  mkdir -p "$(dirname "$source")"; cp -a -- "$dir/payload/item" "$source"
  ok "已恢复：$source"
}

managed_backup_export() {
  local out="${1:-$STATE_DIR/vps-toolkit-backups-$(date +%Y%m%d-%H%M%S).tar.gz}"
  mkdir -p "$MANAGED_BACKUP_DIR"; tar -czf "$out" -C "$STATE_DIR" "$(basename "$MANAGED_BACKUP_DIR")"
  chmod 600 "$out"; ok "备份包：$out"
}

backup_center_menu() {
  while true; do
    ui_header "配置备份中心"
    cat <<'EOF'
1. 查看托管备份     2. 恢复指定备份
3. 导出全部备份     4. 删除过期备份（30天）
0. 返回
EOF
    local c id; read -r -p "请选择: " c
    case "$c" in
      1) managed_backup_list;;
      2) managed_backup_list; read -r -p "备份 ID: " id; managed_backup_restore "$id";;
      3) managed_backup_export;;
      4) risk_preview "清理旧备份" "删除 30 天前的托管备份" "不可恢复，建议先导出" && find "$MANAGED_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf -- {} +;;
      0) break;; *) warn "无效选择";;
    esac
    submenu_pause
  done
}
