#!/usr/bin/env bash
set -Eeuo pipefail
# Run only on a disposable, snapshot-backed VPS. It deliberately avoids changing
# SSH, firewall, kernel, IP family and disks unless VMT_DESTRUCTIVE_TESTS=1.
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "root required" >&2; exit 1; }
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR=/tmp/vmt-vps-state VMT_BACKUP_DIR=/tmp/vmt-vps-backups VMT_LOG_FILE=/tmp/vmt-vps.log
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do source "$ROOT/lib/$module.sh"; done
detect_os; compatibility_report >/tmp/vmt-compatibility.txt
system_info >/tmp/vmt-system-info.txt
security_audit >/tmp/vmt-security.txt || true
diagnostic_report_create /tmp/vmt-diagnostic.txt
bash "$ROOT/tests/safety_contract.sh"
bash "$ROOT/tests/update_integration.sh"

if [ "${VMT_MUTATION_TESTS:-0}" = 1 ]; then
  [ "${VMT_TEST_SNAPSHOT_CONFIRMED:-}" = DISPOSABLE ] || { echo "snapshot confirmation missing" >&2; exit 2; }
  test_port="${VMT_TEST_SSH_PORT:-46222}"; valid_port "$test_port"
  ss -H -ltn | awk '{print $4}' | grep -Eq "(^|:)$test_port$" && { echo "test port occupied" >&2; exit 2; }
  export VMT_ASSUME_YES=1
  change_ssh_port "$test_port"
  ss -H -ltn | awk '{print $4}' | grep -Eq "(^|:)$test_port$"
  transaction_undo latest
  sshd -t
  firewall_apply open 46223 tcp; firewall_apply close 46223 tcp
  echo "vps-mutation-integration: PASS"
fi
echo "vps-integration: PASS ($OS_PRETTY)"
