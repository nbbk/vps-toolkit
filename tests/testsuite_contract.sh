#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR="$TMP/state" VMT_LOG_FILE="$TMP/log"
export VMT_ASSUME_YES=1
source "$ROOT/lib/core.sh"
source "$ROOT/lib/oracle.sh"
source "$ROOT/lib/extensions.sh"
source "$ROOT/lib/testsuite.sh"
mkdir -p "$STATE_DIR/external" "$TMP/bin"
# Stub the transport, not the downloader: no real network or package changes.
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output="$1"; fi
  shift
done
case "$MOCK_CURL" in
  failed) exit 22;;
  partial) printf 'partial' > "$output"; exit 18;;
  empty) : > "$output";;
  script) printf '#!/bin/bash\nprintf "arg:<%%s>\\n" "$@"\nexit "${MOCK_EXIT:-0}"\n' > "$output";;
  invalid) printf 'if then\n' > "$output";;
esac
MOCK
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH" MOCK_CURL=script MOCK_EXIT=0
printf '#!/bin/bash\necho stale\n' > "$STATE_DIR/external/local.sh"
printf 'local\thttps://example.invalid/test.sh\ttest\treview-each-download\t-\tlocal.sh\n' > "$TMP/sources.tsv"
SOURCE_MANIFEST="$TMP/sources.tsv"
for MOCK_CURL in failed partial empty; do
  export MOCK_CURL
  if external_fetch_id local > "$TMP/path" 2>/dev/null; then echo "accepted $MOCK_CURL download" >&2; exit 1; fi
  [ ! -s "$TMP/path" ]
  grep -q stale "$STATE_DIR/external/local.sh"
  [ -z "$(find "$STATE_DIR/external" -name '.download.*' -print)" ]
done
export MOCK_CURL=script
file="$(external_fetch_id local 2>/dev/null)"
[ "$file" = "$STATE_DIR/external/local.sh" ]; bash -n "$file"
# Exact argv boundaries survive the launcher; a failed script stays failed.
output="$(testsuite_run local local 'two words' -i -5 2>/dev/null)"
grep -Fxq 'arg:<two words>' <<< "$output"
grep -Fxq 'arg:<-i>' <<< "$output"
grep -Fxq 'arg:<-5>' <<< "$output"
export MOCK_EXIT=37
if testsuite_run local local > "$TMP/output" 2>&1; then exit 1; else [ "$?" = 37 ]; fi
grep -q '退出码 37' "$TMP/output"
export MOCK_EXIT=0 MOCK_CURL=invalid
if testsuite_run local local >/dev/null 2>&1; then exit 1; fi
# Reject a hash mismatch before any script reaches the launcher.
export MOCK_CURL=script
sed -i 's/review-each-download\t-/pinned-sha256\tbad-hash/' "$TMP/sources.tsv"
if testsuite_run local local >/dev/null 2>&1; then exit 1; fi
sed -i 's/pinned-sha256\tbad-hash/review-each-download\t-/' "$TMP/sources.tsv"
# Cancellation and dry-run never execute, even if a cached script exists.
# shellcheck disable=SC2317
confirm() { return 1; }
output="$(testsuite_run local local 2>/dev/null)"
! grep -q '^arg:' <<< "$output"
DRY_RUN=1
output="$(testsuite_run local local 2>/dev/null)"
[[ "$output" == *DRY-RUN* ]]
if external_fetch_id local >/dev/null 2>&1; then exit 1; fi
echo 'testsuite-contract: PASS'
# Every remaining test number dispatches exactly its reviewed argv; old numbers
# cannot accidentally run a different high-traffic test.
# shellcheck disable=SC2317
(
  ui_header() { :; }
  submenu_pause() { :; }
  testsuite_run() { printf 'dispatch'; printf ':<%s>' "$@"; printf '\n'; }
  mapping='2:region 3:media 11:besttrace 12:mtr 13:superspeed 16:backtrace 18:netquality 19:tcpquality 21:yabs 22:gb5 31:bench 32:ecs 33:nodequality'
  for item in $mapping; do
    IFS=: read -r choice name <<< "$item"
    expected="dispatch:<$name>:<test-$name>"
    [ "$choice" != 21 ] || expected="$expected:<-i>:<-5>"
    output="$(testsuite_menu <<< "$choice"$'\n0')"
    grep -Fxq "$expected" <<< "$output"
  done
  for choice in 1 14; do
    output="$(testsuite_menu <<< "$choice"$'\n0')"
    [[ "$output" == *无效选择* && "$output" != *dispatch* ]]
  done
)
echo 'testsuite-menu-contract: PASS'
