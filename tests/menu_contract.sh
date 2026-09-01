#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR=/tmp/vmt-contract-state VMT_BACKUP_DIR=/tmp/vmt-contract-backup VMT_LOG_FILE=/tmp/vmt-contract.log VMT_DRY_RUN=1
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace; do source "$ROOT/lib/$module.sh"; done

required_functions=(
  system_info system_update system_clean firewall_open_ui firewall_close_ui firewall_open_all firewall_restore_default
  bbr_menu swap_ui docker_menu change_password change_ssh_port_ui ssh_security_check oracle_menu
  system_tools_menu reinstall_menu testsuite_menu web_menu basics_menu workspace_menu
)
for fn in "${required_functions[@]}"; do declare -F "$fn" >/dev/null || { echo "missing function: $fn" >&2; exit 1; }; done

for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace; do grep -q "source \"\$BASE_DIR/lib/\$module.sh\"\|for module in" "$ROOT/vps-tool.sh"; done
for file in lib/core.sh lib/system.sh lib/firewall.sh lib/ssh.sh lib/docker.sh lib/oracle.sh lib/tools.sh lib/reinstall.sh lib/testsuite.sh lib/web.sh lib/basics.sh lib/workspace.sh; do grep -q "$file" "$ROOT/update.sh"; done

export WEB_ROOT=/; if web_safe_root; then exit 1; fi
export WEB_ROOT=/opt/vps-web; web_safe_root
workspace_valid_name workspace-1; if workspace_valid_name 'bad;id'; then exit 1; fi
web_valid_name wordpress; if web_valid_name '../site'; then exit 1; fi
basics_valid_package docker-compose-plugin; if basics_valid_package 'curl | sh'; then exit 1; fi
echo "menu-contract: PASS"
