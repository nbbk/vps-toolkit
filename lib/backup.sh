#!/usr/bin/env bash

MANAGED_BACKUP_DIR="${VMT_MANAGED_BACKUP_DIR:-$STATE_DIR/managed-backups}"
valid_record_id() { [[ "${1:-}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+-[0-9]+$ ]]; }

managed_backup_file() {
  local module="$1" source="$2" stamp dir type=file
  stamp="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}"; dir="$MANAGED_BACKUP_DIR/$stamp"
  mkdir -p "$dir/payload" || { die "无法创建备份目录：$dir"; return 1; }
  if [ -e "$source" ]; then
    [ -f "$source" ] || { rm -rf -- "$dir"; die "托管备份目前只接受普通文件：$source"; return 1; }
    cp -a -- "$source" "$dir/payload/item" || { rm -rf -- "$dir"; die "备份复制失败：$source"; return 1; }
    (cd "$dir" && sha256sum payload/item >sha256) || { rm -rf -- "$dir"; die "备份校验值生成失败：$source"; return 1; }
  else type=absent; : >"$dir/sha256"; fi
  printf 'module=%s\nsource=%s\ntype=%s\ncreated=%s\nversion=%s\n' "$module" "$source" "$type" "$(date -Is)" "$TOOL_VERSION" >"$dir/metadata" || { rm -rf -- "$dir"; return 1; }
  chmod -R go-rwx "$dir" || { rm -rf -- "$dir"; return 1; }
  log INFO "BACKUP module=$module source=$source id=$stamp"
  transaction_note "backup=$stamp"
  printf '%s' "$stamp"
}

managed_backup_list() {
  printf '%-24s %-16s %s\n' "ID" "模块" "原路径"
  local meta id module source
  while IFS= read -r meta; do
    [ -f "$meta" ] || continue; id="$(basename "$(dirname "$meta")")"
    module="$(sed -n 's/^module=//p' "$meta")"; source="$(sed -n 's/^source=//p' "$meta")"
    printf '%-24s %-16s %s\n' "$id" "$module" "$source"
  done < <(find "$MANAGED_BACKUP_DIR" -mindepth 2 -maxdepth 2 -type f -name metadata -print 2>/dev/null | sort -r)
}

managed_backup_restore_force() {
  local id="$1" dir meta source type
  valid_record_id "$id" || { die "备份 ID 格式无效"; return; }
  dir="$MANAGED_BACKUP_DIR/$id"
  meta="$dir/metadata"; [ -f "$meta" ] || { die "备份不存在：$id"; return; }
  source="$(sed -n 's/^source=//p' "$meta")"
  type="$(sed -n 's/^type=//p' "$meta")"
  case "$source" in /etc/*|/opt/*|/var/lib/*|"$STATE_DIR"/*) ;; *) die "拒绝恢复到不安全路径：$source"; return;; esac
  if [ "$type" = absent ]; then rm -f -- "$source"; return 0; fi
  [ "$type" = file ] || { die "备份类型无效：$type"; return; }
  (cd "$dir" && sha256sum -c sha256 --status) || { die "备份校验失败"; return; }
  mkdir -p "$(dirname "$source")" || return 1
  cp -a -- "$dir/payload/item" "$source" || { die "恢复备份失败：$source"; return; }
}

managed_backup_restore() {
  local id="$1" dir source
  valid_record_id "$id" || { die "备份 ID 格式无效"; return; }
  dir="$MANAGED_BACKUP_DIR/$id"
  [ -f "$dir/metadata" ] || { die "备份不存在：$id"; return; }
  source="$(sed -n 's/^source=//p' "$dir/metadata")"
  risk_preview "恢复配置备份" "覆盖路径：$source" "回滚方式：恢复前会再次制作当前文件备份" || return 0
  if plan_only; then printf '[DRY-RUN] 将校验并恢复备份 %s 到 %s\n' "$id" "$source"; return 0; fi
  operation_lock_acquire restore || return
  managed_backup_file pre-restore "$source" >/dev/null || { operation_lock_release; die "恢复前备份失败，已停止"; return; }
  managed_backup_restore_force "$id" || { operation_lock_release; return; }
  operation_lock_release; ok "已恢复：$source"
}

managed_backup_diff() {
  local id="$1" dir source type
  valid_record_id "$id" || { die "备份 ID 格式无效"; return; }
  dir="$MANAGED_BACKUP_DIR/$id"
  [ -f "$dir/metadata" ] || { die "备份不存在：$id"; return; }
  source="$(sed -n 's/^source=//p' "$dir/metadata")"; type="$(sed -n 's/^type=//p' "$dir/metadata")"
  if [ "$type" = absent ]; then echo "备份时文件不存在：$source"; return; fi
  [ -f "$source" ] || { warn "当前文件不存在：$source"; return; }
  diff -u -- "$dir/payload/item" "$source" || true
}

managed_backup_export() {
  local out="${1:-$STATE_DIR/vps-toolkit-backups-$(date +%Y%m%d-%H%M%S).tar.gz}"
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 将导出托管备份到 %s\n' "$out"; plan_only; return 0; fi
  mkdir -p "$MANAGED_BACKUP_DIR"
  tar -czf "$out" -C "$STATE_DIR" "$(basename "$MANAGED_BACKUP_DIR")" || { rm -f -- "$out"; die "备份导出失败"; return; }
  chmod 600 "$out" || return; ok "备份包：$out"
}

managed_backup_export_encrypted() {
  local plain="$STATE_DIR/.backup-export-$$.tar.gz" out="${1:-$STATE_DIR/vps-toolkit-backups-$(date +%Y%m%d-%H%M%S).tar.gz.enc}"
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 将使用 AES-256-CBC（PBKDF2）加密导出到 %s\n' "$out"; plan_only; return 0; fi
  command -v openssl >/dev/null 2>&1 || { die "缺少 openssl"; return; }
  managed_backup_export "$plain" >/dev/null || return
  if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$plain" -out "$out"; then chmod 600 "$out"; rm -f -- "$plain"; ok "加密备份包：$out"
  else rm -f -- "$plain" "$out"; die "加密导出失败"; fi
}

managed_backup_import() {
  local input="$1" archive temp="" entry relative id stage dir source type found=0
  archive="$input"
  [ -f "$input" ] || { die "导入文件不存在"; return; }
  if [[ "$input" = *.enc ]]; then
    command -v openssl >/dev/null 2>&1 || { die "缺少 openssl"; return; }
    temp="$(mktemp)"; openssl enc -d -aes-256-cbc -pbkdf2 -in "$input" -out "$temp" || { rm -f -- "$temp"; die "解密失败"; return; }; archive="$temp"
  fi
  while IFS= read -r entry; do
    case "$entry" in
      managed-backups|managed-backups/*)
        [[ "$entry" != *../* ]] || { [ -z "$temp" ] || rm -f -- "$temp"; die "压缩包包含不安全路径"; return; }
        relative="${entry#managed-backups/}"; id="${relative%%/*}"
        if [ -n "$id" ] && [ -e "$MANAGED_BACKUP_DIR/$id" ]; then
          [ -z "$temp" ] || rm -f -- "$temp"; die "同名备份已存在：$id"; return
        fi
        ;;
      *) [ -z "$temp" ] || rm -f -- "$temp"; die "不是有效的工具备份包"; return;;
    esac
  done < <(tar -tzf "$archive")
  if tar -tvzf "$archive" | awk 'substr($1,1,1) ~ /^[lh]$/ {bad=1} END {exit !bad}'; then
    [ -z "$temp" ] || rm -f -- "$temp"; die "备份包包含符号链接或硬链接，拒绝导入"; return
  fi
  risk_preview "导入备份" "合并备份包到 $MANAGED_BACKUP_DIR" "同名备份会被拒绝覆盖" || { [ -z "$temp" ] || rm -f -- "$temp"; return 0; }
  if plan_only; then printf '[DRY-RUN] 已验证压缩包目录结构；不会导入文件。\n'; [ -z "$temp" ] || rm -f -- "$temp"; return 0; fi
  stage="$(mktemp -d)"
  tar -xzf "$archive" -C "$stage" || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "导入解包失败"; return; }
  for dir in "$stage/managed-backups"/*; do
    [ -d "$dir" ] || continue; found=1; id="$(basename "$dir")"
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+-[0-9]+$ ]] || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "非法备份 ID：$id"; return; }
    [ -f "$dir/metadata" ] && [ -f "$dir/sha256" ] || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 结构不完整"; return; }
    [ "$(grep -c '^source=' "$dir/metadata")" = 1 ] && [ "$(grep -c '^type=' "$dir/metadata")" = 1 ] || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 元数据无效"; return; }
    source="$(sed -n 's/^source=//p' "$dir/metadata")"; type="$(sed -n 's/^type=//p' "$dir/metadata")"
    case "$source" in /etc/*|/opt/*|/var/lib/*|"$STATE_DIR"/*) ;; *) rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 的恢复路径不安全"; return;; esac
    if [ "$type" = file ]; then
      [ -f "$dir/payload/item" ] && awk 'NF==2 && length($1)==64 && $1 !~ /[^0-9a-fA-F]/ && ($2=="payload/item" || $2=="*payload/item"){ok=1} END{exit !ok}' "$dir/sha256" && (cd "$dir" && sha256sum -c sha256 --status) || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 校验失败"; return; }
    elif [ "$type" = absent ]; then
      [ ! -s "$dir/sha256" ] && [ ! -e "$dir/payload/item" ] || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 的空文件记录无效"; return; }
    else rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份 $id 类型无效"; return
    fi
  done
  [ "$found" = 1 ] || { rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; die "备份包中没有备份记录"; return; }
  mkdir -p "$MANAGED_BACKUP_DIR"
  chmod -R go-rwx "$stage/managed-backups"
  for dir in "$stage/managed-backups"/*; do [ -d "$dir" ] && mv -- "$dir" "$MANAGED_BACKUP_DIR/"; done
  rm -rf -- "$stage"; [ -z "$temp" ] || rm -f -- "$temp"; ok "备份导入完成"
}

managed_backup_prune() {
  local keep="${VMT_BACKUP_KEEP:-30}" count=0 dir
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=30
  if [ "$DRY_RUN" = 1 ]; then printf '[DRY-RUN] 将仅保留最近 %s 份托管备份。\n' "$keep"; plan_only; return 0; fi
  while IFS= read -r dir; do count=$((count+1)); [ "$count" -le "$keep" ] || rm -rf -- "$dir"; done < <(find "$MANAGED_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r)
  ok "已保留最近 $keep 份托管备份"
}

transaction_history() {
  printf '%-30s %-18s %-14s %s\n' "事务 ID" "模块" "状态" "开始时间"
  local file id module status started order="$STATE_DIR/transaction-order"
  if [ -s "$order" ]; then
    while IFS= read -r id; do
      valid_record_id "$id" || continue; file="$STATE_DIR/transactions/$id"; [ -f "$file" ] || continue
      module="$(sed -n 's/^module=//p' "$file")"; status="$(sed -n 's/^final_status=//p' "$file" | tail -n1)"; started="$(sed -n 's/^started=//p' "$file")"
      printf '%-30s %-18s %-14s %s\n' "$id" "$module" "${status:-running}" "$started"
    done < <(awk '{line[NR]=$0} END{for(i=NR;i>=1;i--) print line[i]}' "$order")
    return
  fi
  while IFS= read -r file; do [ -f "$file" ] || continue
    id="$(sed -n 's/^id=//p' "$file")"; module="$(sed -n 's/^module=//p' "$file")"; status="$(sed -n 's/^final_status=//p' "$file" | tail -n1)"; started="$(sed -n 's/^started=//p' "$file")"
    printf '%-30s %-18s %-14s %s\n' "$id" "$module" "${status:-running}" "$started"
  done < <(find "$STATE_DIR/transactions" -maxdepth 1 -type f -print 2>/dev/null | sort -r)
}

transaction_undo() {
  local id="${1:-latest}" file candidate backup meta source swap_state swap_size swap_active
  if [ "$id" = latest ]; then
    file=""
    if [ -s "$STATE_DIR/transaction-order" ]; then
      while IFS= read -r candidate; do
        valid_record_id "$candidate" || continue; candidate="$STATE_DIR/transactions/$candidate"
        if [ -f "$candidate" ] && [ "$(sed -n 's/^final_status=//p' "$candidate" | tail -n1)" = success ]; then file="$candidate"; break; fi
      done < <(awk '{line[NR]=$0} END{for(i=NR;i>=1;i--) print line[i]}' "$STATE_DIR/transaction-order")
    else
      while IFS= read -r candidate; do
        if [ "$(sed -n 's/^final_status=//p' "$candidate" | tail -n1)" = success ]; then file="$candidate"; break; fi
      done < <(find "$STATE_DIR/transactions" -type f -print 2>/dev/null | sort -r)
    fi
  else valid_record_id "$id" || { die "事务 ID 格式无效"; return; }; file="$STATE_DIR/transactions/$id"; fi
  [ -f "$file" ] || { die "没有找到事务：$id"; return; }; id="$(sed -n 's/^id=//p' "$file")"
  [ "$(sed -n 's/^final_status=//p' "$file" | tail -n1)" = success ] || { die "只有成功完成且未撤销的事务可以撤销"; return; }
  risk_preview "撤销事务" "恢复事务 $id 的全部配置备份" "撤销前仍会保留当前配置备份" || return 0
  if plan_only; then printf '[DRY-RUN] 将按相反顺序恢复事务 %s。\n' "$id"; return 0; fi
  operation_lock_acquire undo || return
  while IFS= read -r backup; do
    [ -n "$backup" ] || continue
    valid_record_id "$backup" || { operation_lock_release; die "事务包含非法备份 ID"; return; }
    meta="$MANAGED_BACKUP_DIR/$backup/metadata"; [ -f "$meta" ] || { operation_lock_release; die "事务引用的备份不存在：$backup"; return; }
    source="$(sed -n 's/^source=//p' "$meta")"
    case "$source" in /etc/*|/opt/*|/var/lib/*|"$STATE_DIR"/*) ;; *) operation_lock_release; die "事务引用了不安全路径：$source"; return;; esac
    managed_backup_file pre-undo "$source" >/dev/null || { operation_lock_release; die "撤销前备份失败，已停止"; return; }
    managed_backup_restore_force "$backup" || { operation_lock_release; return; }
  done < <(sed -n 's/^backup=//p' "$file" | awk '{line[NR]=$0} END{for(i=NR;i>=1;i--) print line[i]}')
  # Consumed by firewall_apply in another sourced module.
  # shellcheck disable=SC2034
  VMT_UNDOING=1
  while IFS='|' read -r action spec proto; do
    if [ -n "$action" ] && ! firewall_apply "$action" "$spec" "$proto"; then unset VMT_UNDOING; operation_lock_release; die "防火墙状态恢复失败"; return; fi
  done < <(sed -n 's/^firewall_undo=//p' "$file" | awk '{line[NR]=$0} END{for(i=NR;i>=1;i--) print line[i]}')
  case "$(sed -n 's/^module=//p' "$file")" in
    ssh-port)
      sshd -t || { unset VMT_UNDOING; operation_lock_release; die "恢复后的 SSH 配置校验失败"; return; }
      if ssh_socket_activation_active; then
        systemctl daemon-reload && systemctl restart ssh.socket || { unset VMT_UNDOING; operation_lock_release; die "SSH Socket 恢复失败"; return; }
      else service_restart ssh sshd || { unset VMT_UNDOING; operation_lock_release; die "SSH 服务恢复失败"; return; }; fi
      ;;
    bbr|network) sysctl --system || { unset VMT_UNDOING; operation_lock_release; die "sysctl 状态恢复失败"; return; };;
    swap)
      swap_state="$(sed -n 's/^swap_undo=//p' "$file" | tail -n1)"
      if [ -n "$swap_state" ]; then
        IFS='|' read -r swap_size swap_active <<<"$swap_state"
        [[ "$swap_size" =~ ^[0-9]+$ && "$swap_active" =~ ^[01]$ ]] || { unset VMT_UNDOING; operation_lock_release; die "事务中的 Swap 状态无效"; return; }
        swap_restore_state "$swap_size" "$swap_active" || { unset VMT_UNDOING; operation_lock_release; die "Swap 状态恢复失败"; return; }
      else swapon -a 2>/dev/null || true; fi
      ;;
  esac
  unset VMT_UNDOING
  printf 'undone=%s\nfinal_status=undone\n' "$(date -Is)" >>"$file"
  operation_lock_release; ok "事务已撤销：$id"
}

backup_center_menu() {
  while true; do
    ui_header "配置备份中心"
    cat <<'EOF'
1. 查看托管备份     2. 查看备份差异
3. 恢复指定备份     4. 导出全部备份
5. 加密导出备份     6. 导入备份包
7. 按保留数量清理   8. 操作历史
9. 撤销指定事务
0. 返回
EOF
    local c id file; read -r -p "请选择: " c
    case "$c" in
      1) managed_backup_list;;
      2) managed_backup_list; read -r -p "备份 ID: " id; managed_backup_diff "$id";;
      3) managed_backup_list; read -r -p "备份 ID: " id; managed_backup_restore "$id";;
      4) managed_backup_export "";; 5) managed_backup_export_encrypted "";;
      6) read -r -p "备份包绝对路径: " file; managed_backup_import "$file";;
      7) risk_preview "清理备份" "仅保留最近 ${VMT_BACKUP_KEEP:-30} 份" "删除的备份不可恢复" && managed_backup_prune;;
      8) transaction_history;; 9) transaction_history; read -r -p "事务 ID（latest 为最近一次）: " id; transaction_undo "$id";;
      0) break;; *) warn "无效选择";;
    esac
    submenu_pause
  done
}
