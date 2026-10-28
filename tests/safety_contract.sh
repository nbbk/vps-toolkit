#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR="$TMP/state" VMT_BACKUP_DIR="$TMP/legacy" VMT_MANAGED_BACKUP_DIR="$TMP/state/managed-backups"
export VMT_LOG_FILE="$TMP/toolkit.log" VMT_LOCK_DIR="$TMP/locks" VMT_ASSUME_YES=1
export TOOL_VERSION=2.3.5; mkdir -p "$VMT_STATE_DIR"; touch "$VMT_LOG_FILE"
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do source "$ROOT/lib/$module.sh"; done

output="$(cli_dispatch --dry-run firewall open 54321 tcp)"
grep 'DRY-RUN.*54321' <<<"$output" >/dev/null
output="$(cli_dispatch --dry-run firewall open 54000:54010 udp)"
grep 'DRY-RUN.*54000:54010.*udp' <<<"$output" >/dev/null
if cli_dispatch firewall open invalid tcp >/dev/null 2>&1; then exit 1; fi
DRY_RUN=1; export VMT_DRY_RUN=1
output="$(bbr_profile_apply bbr fq 'test profile')"
grep -q 'bbr + fq' <<<"$output"
output="$(cli_dispatch --dry-run bbr profile cubic-fq_codel)"
grep -q 'cubic + fq_codel' <<<"$output"
if cli_dispatch --dry-run bbr profile invalid-profile >/dev/null 2>&1; then exit 1; fi

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
if grep -Fxq '54322/tcp' "$MOCK_UFW_STATE"; then exit 1; fi
printf '54323/tcp\n' >"$MOCK_UFW_STATE"
before_order="$(wc -l <"$VMT_STATE_DIR/transaction-order")"
firewall_apply open 54323 tcp >/dev/null
[ "$(wc -l <"$VMT_STATE_DIR/transaction-order")" = "$before_order" ]
grep -Fxq '54323/tcp' "$MOCK_UFW_STATE"
PATH="$old_path"

extension_set tests disabled >/dev/null; if extension_enabled tests; then exit 1; fi
extension_set tests enabled >/dev/null; extension_enabled tests
if extension_set 'tests.*' disabled >/dev/null 2>&1; then exit 1; fi

archive="$TMP/export.tar.gz"
managed_backup_export "$archive" >/dev/null
old_managed="$MANAGED_BACKUP_DIR"; MANAGED_BACKUP_DIR="$TMP/import-state/managed-backups"
managed_backup_import "$archive" >/dev/null
find "$MANAGED_BACKUP_DIR" -name metadata -type f -print -quit | grep -q .
MANAGED_BACKUP_DIR="$old_managed"

export DRY_RUN=1
baseline_create >/dev/null
[ ! -e "$VMT_STATE_DIR/baseline/current.txt" ]
managed_backup_export "$TMP/dry-run.tar.gz" >/dev/null
[ ! -e "$TMP/dry-run.tar.gz" ]
# Download/runner regressions use only local fixtures, never upstream code.
# The curl and confirmation overrides are called indirectly by sourced helpers.
# shellcheck disable=SC2317
(
  export VMT_STATE_DIR="$TMP/external-state"
  STATE_DIR="$VMT_STATE_DIR"; DRY_RUN=0
  mkdir -p "$STATE_DIR/external"
  SOURCE_MANIFEST="$TMP/test-sources.tsv"
  fixture="$TMP/script-fixture.sh"
  printf 'test-fixture\thttps://example.invalid/test.sh\ttest\treview-each-download\t-\ttest.sh\n' >"$SOURCE_MANIFEST"
  curl_mode=success
  curl() {
    [ "$curl_mode" != failure ] || return 28
    local destination=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then destination="$2"; shift 2; else shift; fi
    done
    [ -n "$destination" ] || return 2
    cp "$fixture" "$destination"
  }
  confirm() { touch "$STATE_DIR/confirmed"; }
  cat >"$fixture" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$VMT_STATE_DIR/executed"
EOF
  cp "$fixture" "$STATE_DIR/external/test.sh"
  curl_mode=failure
  if testsuite_run fixture test-fixture >"$TMP/download-failure.log" 2>&1; then exit 1; else [ "$?" = 28 ]; fi
  [ ! -e "$STATE_DIR/executed" ] && [ ! -e "$STATE_DIR/confirmed" ]

  curl_mode=success
  : >"$fixture"
  if testsuite_run fixture test-fixture >"$TMP/empty.log" 2>&1; then exit 1; fi
  [ ! -e "$STATE_DIR/confirmed" ]
  printf '#!/usr/bin/env bash\nif\n' >"$fixture"
  if testsuite_run fixture test-fixture >"$TMP/syntax.log" 2>&1; then exit 1; fi
  [ ! -e "$STATE_DIR/confirmed" ]

  printf '#!/usr/bin/env bash\nexit 42\n' >"$fixture"
  if testsuite_run fixture test-fixture >"$TMP/exit-status.log" 2>&1; then exit 1; else [ "$?" = 42 ]; fi
  grep -q '退出码 42' "$TMP/exit-status.log"
  rm "$STATE_DIR/confirmed"
  printf 'test-fixture\thttps://example.invalid/test.sh\ttest\tpinned-sha256\tincorrect\ttest.sh\n' >"$SOURCE_MANIFEST"
  if testsuite_run fixture test-fixture >"$TMP/digest.log" 2>&1; then exit 1; fi
  [ ! -e "$STATE_DIR/confirmed" ]

  cat >"$fixture" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$VMT_STATE_DIR/executed"
EOF
  digest="$(sha256sum "$fixture" | awk '{print $1}')"
  printf 'test-fixture\thttps://example.invalid/test.sh\ttest\tpinned-sha256\t%s\ttest.sh\n' "$digest" >"$SOURCE_MANIFEST"
  testsuite_run fixture test-fixture -i -5 'argument with spaces' >/dev/null 2>&1
  printf '%s\n' -i -5 'argument with spaces' >"$TMP/expected-arguments"
  cmp "$TMP/expected-arguments" "$STATE_DIR/executed"
)

echo 'safety-contract: PASS'
