#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for file in "$ROOT"/vps-tool.sh "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/bootstrap.sh "$ROOT"/lib/*.sh; do bash -n "$file"; done
export VMT_STATE_DIR=/tmp/vmt-test-state VMT_BACKUP_DIR=/tmp/vmt-test-backup VMT_LOG_FILE=/tmp/vmt-test.log VMT_DRY_RUN=1 VMT_BASE_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/core.sh"; source "$ROOT/lib/firewall.sh"
valid_port 22; valid_port 65535; ! valid_port 0; ! valid_port 65536; ! valid_port abc
parse_port_spec 443 tcp; parse_port_spec 8000:8100 udp; ! parse_port_spec 9000:8000 tcp; ! parse_port_spec '22;id' tcp
valid_size_mb 128; valid_size_mb 262144; ! valid_size_mb 127; ! valid_size_mb '1G'
echo "smoke: PASS"
