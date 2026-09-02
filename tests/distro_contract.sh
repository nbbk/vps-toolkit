#!/usr/bin/env bash
set -Eeuo pipefail
[ "${VMT_TEST_TRACE:-0}" = 1 ] && set -x
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR=/tmp/vmt-distro-state VMT_BACKUP_DIR=/tmp/vmt-distro-backups VMT_LOG_FILE=/tmp/vmt-distro.log
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions cli; do
  # shellcheck source=/dev/null
  source "$ROOT/lib/$module.sh"
done
VERSION=toolkit-sentinel
detect_os
[ "$VERSION" = toolkit-sentinel ]
[ "$PKG_FAMILY" = "${EXPECTED_FAMILY:?}" ]
[ -n "$OS_PRETTY" ]
[ "$(detect_init_system)" != "" ]
cli_usage | grep 'nb doctor' >/dev/null
source_manifest_lookup reinstall | grep pinned-sha256 >/dev/null
bash "$ROOT/vps-tool.sh" version | grep -x '2.2.0' >/dev/null
bash "$ROOT/vps-tool.sh" --help | grep 'backup list' >/dev/null
echo "distro-contract: PASS ($OS_PRETTY / $PKG_FAMILY)"
