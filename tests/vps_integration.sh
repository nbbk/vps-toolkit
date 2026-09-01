#!/usr/bin/env bash
set -Eeuo pipefail
# Run only on a disposable, snapshot-backed VPS. It deliberately avoids changing
# SSH, firewall, kernel, IP family and disks unless VMT_DESTRUCTIVE_TESTS=1.
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "root required" >&2; exit 1; }
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR=/tmp/vmt-vps-state VMT_BACKUP_DIR=/tmp/vmt-vps-backups VMT_LOG_FILE=/tmp/vmt-vps.log
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions cli; do source "$ROOT/lib/$module.sh"; done
detect_os; compatibility_report >/tmp/vmt-compatibility.txt
system_info >/tmp/vmt-system-info.txt
security_audit >/tmp/vmt-security.txt || true
diagnostic_report_create /tmp/vmt-diagnostic.txt
bash "$ROOT/tests/update_integration.sh"
if [ "${VMT_DESTRUCTIVE_TESTS:-0}" = 1 ]; then
  echo "Destructive scenarios require operator-specific SSH/cloud recovery orchestration." >&2
  exit 2
fi
echo "vps-integration: PASS ($OS_PRETTY)"
