#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR=/tmp/vmt-contract-state VMT_BACKUP_DIR=/tmp/vmt-contract-backup VMT_LOG_FILE=/tmp/vmt-contract.log VMT_DRY_RUN=1
export PKG_FAMILY=apt OS_PRETTY="Test Linux"
for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do source "$ROOT/lib/$module.sh"; done

[[ "$C_CYAN" == $'\033[36m' ]] || { echo "color escape is not an ANSI byte" >&2; exit 1; }
if [ -r /etc/os-release ]; then
  VERSION="toolkit-test"
  detect_os
  [ "$VERSION" = "toolkit-test" ] || { echo "/etc/os-release overwrote toolkit VERSION" >&2; exit 1; }
fi
# Match the literal template expression in source.
# shellcheck disable=SC2016
grep -q 'v${TOOL_VERSION}' "$ROOT/vps-tool.sh" || { echo "menu header does not use TOOL_VERSION" >&2; exit 1; }
grep -q 'systemctl restart ssh.socket' "$ROOT/lib/ssh.sh" || { echo "missing SSH socket activation support" >&2; exit 1; }

required_functions=(
  system_info system_update system_clean firewall_open_ui firewall_close_ui firewall_open_all firewall_restore_default
  bbr_menu swap_ui docker_menu change_password change_ssh_port_ui ssh_security_check oracle_menu oracle_r_tanzhang
  system_tools_menu reinstall_menu testsuite_menu web_menu basics_menu workspace_menu
  ip_family_menu ip_family_prefer ip_family_only4 ip_family_only6 ip_family_dual
  compatibility_report diagnostic_report_create security_audit backup_center_menu extensions_menu cli_dispatch
  baseline_create baseline_check transaction_history transaction_undo managed_backup_diff
  bbr_profile_apply bbr_profile_menu bbr_custom_profile_ui
)
for fn in "${required_functions[@]}"; do declare -F "$fn" >/dev/null || { echo "missing function: $fn" >&2; exit 1; }; done

for module in core system firewall ssh docker oracle tools reinstall testsuite web basics workspace backup diagnostics security extensions baseline cli; do grep -q "source \"\$BASE_DIR/lib/\$module.sh\"\|for module in" "$ROOT/vps-tool.sh"; done
for file in lib/core.sh lib/system.sh lib/firewall.sh lib/ssh.sh lib/docker.sh lib/oracle.sh lib/tools.sh lib/reinstall.sh lib/testsuite.sh lib/web.sh lib/basics.sh lib/workspace.sh lib/backup.sh lib/diagnostics.sh lib/security.sh lib/extensions.sh lib/baseline.sh lib/cli.sh; do grep -q "$file" "$ROOT/update.sh"; done
if grep -q "trap .* ERR" "$ROOT/vps-tool.sh"; then echo "unexpected global ERR trap" >&2; exit 1; fi
for file in system docker oracle tools reinstall testsuite web basics workspace; do grep -q 'while true; do' "$ROOT/lib/$file.sh" || { echo "submenu is not persistent: $file" >&2; exit 1; }; done
for menu in bbr_menu bbr_profile_menu docker_menu oracle_menu system_tools_menu reinstall_menu testsuite_menu web_menu basics_menu; do "$menu" <<<"0" >/dev/null; done

export WEB_ROOT=/; if web_safe_root; then exit 1; fi
export WEB_ROOT=/opt/vps-web; web_safe_root
workspace_valid_name workspace-1; if workspace_valid_name 'bad;id'; then exit 1; fi
web_valid_name wordpress; if web_valid_name '../site'; then exit 1; fi
basics_valid_package docker-compose-plugin; if basics_valid_package 'curl | sh'; then exit 1; fi
# Exercise affected menus without installing anything or contacting upstreams.
# These overrides are called indirectly by the sourced menu functions.
# shellcheck disable=SC2317
(
  ui_header() { :; }
  clear_screen() { :; }
  submenu_pause() { :; }
  warn() { printf 'invalid:%s\n' "$*"; }
  web_prepare() { echo 'unexpected:web_prepare'; return 1; }
  external_fetch_id() { echo 'unexpected:download'; return 1; }
  web_app_compose() { echo 'unexpected:compose'; return 1; }
  for removed in web_install_discuz web_install_typecho oracle_oci_helper; do
    if declare -F "$removed" >/dev/null; then echo "removed function remains: $removed" >&2; exit 1; fi
  done
  for selection in 3 5; do
    output="$(web_menu <<<"$selection"$'\n0')"
    [[ "$output" == *invalid:* && "$output" != *unexpected:* ]] || exit 1
    [[ "$output" != *Discuz* && "$output" != *Typecho* ]] || exit 1
  done
  output="$(oracle_menu <<<'10
0')"
  [[ "$output" == *invalid:* && "$output" != *unexpected:* && "$output" != *'OCI Helper'* ]] || exit 1
  [ -z "$(source_manifest_lookup oci-helper)" ]
  [ -z "$(source_manifest_lookup test-chatgpt)" ]
  testsuite_run() { printf 'test-call:%s\n' "$*"; }
  output="$(testsuite_menu <<<'1
0')"
  [[ "$output" == *invalid:* && "$output" != *test-call:* && "$output" != *ChatGPT* ]] || exit 1
  test_actions='2:region:test-region 3:media:test-media 11:besttrace:test-besttrace 12:mtr:test-mtr 13:superspeed:test-superspeed 14:nexttrace:test-nexttrace 16:backtrace:test-backtrace 18:netquality:test-netquality 19:tcpquality:test-tcpquality 21:yabs:test-yabs 22:gb5:test-gb5 31:bench:test-bench 32:ecs:test-ecs 33:nodequality:test-nodequality'
  for entry in $test_actions; do
    IFS=: read -r selection action source_id <<<"$entry"
    expected="test-call:$action $source_id"
    [ "$selection" != 21 ] || expected+=' -i -5'
    output="$(testsuite_menu <<<"$selection"$'\n0')"
    grep -Fxq "$expected" <<<"$output" || { echo "wrong test dispatch: $entry" >&2; exit 1; }
  done

  # Fixed, local mappings: mock every retained action and verify its old number.
  web_actions='1:web_install_ldnmp 2:web_install_wordpress 4:web_install_halo 6:web_install_vaultwarden 7:web_static 8:web_proxy 9:web_status 10:web_backup 11:web_restore 12:web_update 13:web_optimize 14:web_uninstall 15:web_install_panel:bt 16:web_install_panel:aapanel'
  oracle_actions='1:oracle_keepalive_install 2:oracle_keepalive_remove 3:oracle_reinstall 4:oracle_r_tanzhang 5:oracle_root_login_enable 6:oracle_root_login_disable 7:oracle_ipv6_repair 8:oracle_jhb_ipv6 9:oracle_metadata'
  for entry in $web_actions $oracle_actions; do
    IFS=: read -r selection action argument <<<"$entry"
    eval "$action() { printf 'called:%s:%s\\n' '$action' \"\${1:-}\"; }"
  done
  for entry in $web_actions $oracle_actions; do
    IFS=: read -r selection action argument <<<"$entry"
    case "$action" in web_*) menu=web_menu;; oracle_*) menu=oracle_menu;; esac
    output="$("$menu" <<<"$selection"$'\n0')"
    grep -Fxq "called:$action:$argument" <<<"$output" || { echo "wrong menu dispatch: $entry" >&2; exit 1; }
  done
)

# Every literal third-party ID used by a caller must resolve, and no registry
# row may be orphaned. Dynamic panel assignments are included explicitly.
used_sources="$(
  grep -hEo 'external_fetch_id [a-z][a-z0-9-]*|testsuite_run [a-z0-9]+ [a-z][a-z0-9-]*|source_id=[a-z][a-z0-9-]*' "$ROOT"/lib/*.sh |
    sed -E 's/.*[ =]//' | sort -u
)"
registered_sources="$(awk -F '\t' '!/^#/ && NF {print $1}' "$SOURCE_MANIFEST" | sort -u)"
[ "$used_sources" = "$registered_sources" ] || { echo 'source registry/caller mismatch' >&2; diff <(echo "$used_sources") <(echo "$registered_sources"); exit 1; }

echo "menu-contract: PASS"
