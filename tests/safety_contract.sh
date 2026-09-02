#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR="$TMP/state" VMT_BACKUP_DIR="$TMP/legacy" VMT_MANAGED_BACKUP_DIR="$TMP/state/managed-backups"
export VMT_LOG_FILE="$TMP/toolkit.log" VMT_LOCK_DIR="$TMP/locks" VMT_ASSUME_YES=1
TOOL_VERSION=2.3.0; mkdir -p "$VMT_STATE_DIR"; touch "$VMT_LOG_FILE"
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do source "$ROOT/lib/$module.sh"; done

output="$(cli_dispatch --dry-run firewall open 54321 tcp)"
grep 'DRY-RUN.*54321' <<<"$output" >/dev/null
output="$(cli_dispatch --dry-run firewall open 54000:54010 udp)"
grep 'DRY-RUN.*54000:54010.*udp' <<<"$output" >/dev/null
! cli_dispatch firewall open invalid tcp >/dev/null 2>&1

DRY_RUN=0; target="$VMT_STATE_DIR/test-config"
transaction_begin unit-test; transaction_id="$VMT_TRANSACTION_ID"
managed_backup_file unit "$target" >/dev/null
printf 'changed\n' >"$target"; transaction_finish success
[ -f "$target" ]; transaction_undo "$transaction_id" >/dev/null; [ ! -e "$target" ]
[ "$(sed -n 's/^final_status=//p' "$VMT_STATE_DIR/transactions/$transaction_id" | tail -n1)" = undone ]

mock_bin="$TMP/mock-bin"; mkdir -p "$mock_bin"; cp "$ROOT/tests/fixtures/ufw" "$mock_bin/ufw"; chmod +x "$mock_bin/ufw"
export MOCK_UFW_STATE="$TMP/mock-ufw.state"; old_path="$PATH"; PATH="$mock_bin:$PATH"
firewall_apply open 54322 tcp >/dev/null
grep -Fxq '54322/tcp' "$MOCK_UFW_STATE"
transaction_undo latest >/dev/null
! grep -Fxq '54322/tcp' "$MOCK_UFW_STATE"
printf '54323/tcp\n' >"$MOCK_UFW_STATE"
before_order="$(wc -l <"$VMT_STATE_DIR/transaction-order")"
firewall_apply open 54323 tcp >/dev/null
[ "$(wc -l <"$VMT_STATE_DIR/transaction-order")" = "$before_order" ]
grep -Fxq '54323/tcp' "$MOCK_UFW_STATE"
PATH="$old_path"

extension_set tests disabled >/dev/null; ! extension_enabled tests
extension_set tests enabled >/dev/null; extension_enabled tests
! extension_set 'tests.*' disabled >/dev/null 2>&1

archive="$TMP/export.tar.gz"
managed_backup_export "$archive" >/dev/null
old_managed="$MANAGED_BACKUP_DIR"; MANAGED_BACKUP_DIR="$TMP/import-state/managed-backups"
managed_backup_import "$archive" >/dev/null
find "$MANAGED_BACKUP_DIR" -name metadata -type f -print -quit | grep -q .
MANAGED_BACKUP_DIR="$old_managed"

DRY_RUN=1
baseline_create >/dev/null
[ ! -e "$VMT_STATE_DIR/baseline/current.txt" ]
managed_backup_export "$TMP/dry-run.tar.gz" >/dev/null
[ ! -e "$TMP/dry-run.tar.gz" ]
echo 'safety-contract: PASS'
