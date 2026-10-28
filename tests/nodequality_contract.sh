#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
export VMT_BASE_DIR="$ROOT" VMT_STATE_DIR="$TMP/state" VMT_LOG_FILE="$TMP/log"
export VMT_ASSUME_YES=1 VMT_DRY_RUN=0
source "$ROOT/lib/core.sh"
source "$ROOT/lib/oracle.sh"
source "$ROOT/lib/extensions.sh"
source "$ROOT/lib/testsuite.sh"
source "$ROOT/lib/cli.sh"
# CLI alias must not append upload/default options and preserves argument boundaries.
# shellcheck disable=SC2317
(
  testsuite_run() { printf 'argc:%s\n' "$#"; printf 'arg:<%s>\n' "$@"; }
  output="$(cli_dispatch nq)"
  [[ "$output" == $'argc:2\narg:<nodequality>\narg:<test-nodequality>' ]]
  output="$(cli_dispatch nq -E -D 'two words')"
  [[ "$output" == $'argc:5\narg:<nodequality>\narg:<test-nodequality>\narg:<-E>\narg:<-D>\narg:<two words>' ]]
  testsuite_run() { return 42; }
  if cli_dispatch nq; then exit 1; else [ "$?" = 42 ]; fi
  extension_enabled() { return 1; }
  testsuite_run() { echo 'disabled extension unexpectedly reached launcher'; exit 99; }
  if cli_dispatch nq >/dev/null 2>&1; then exit 1; else [ "$?" = 1 ]; fi
)
# Top-level CLI still gates non-help commands on root before any download.
if [ "$EUID" -ne 0 ]; then
  if bash "$ROOT/vps-tool.sh" nq > "$TMP/root-check" 2>&1; then exit 1; fi
  grep -q '请使用 root' "$TMP/root-check"
fi
mkdir -p "$TMP/bin"
export MOCK_TRACE="$TMP/fetches" MOCK_SCRIPT="$TMP/mock.sh"
printf '#!/usr/bin/env bash\nprintf "mock-nodequality:<%%s>\\n" "$@"\n' > "$MOCK_SCRIPT"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf 'fetch\n' >> "$MOCK_TRACE"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output="$1"; fi
  shift
done
cp "$MOCK_SCRIPT" "$output"
MOCK
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
# The real manifest is structurally pinned; this does not download it.
nodequality_source_ready
# An unconfigured/pending row must fail before invoking transport.
SOURCE_MANIFEST="$TMP/sources.tsv"
printf 'test-nodequality\t-\tpending-publication\tpending-release\t-\ttest-nodequality.sh\n' > "$SOURCE_MANIFEST"
if cli_dispatch nq > "$TMP/out" 2>&1; then exit 1; fi
[ ! -e "$MOCK_TRACE" ]
grep -q '不会下载' "$TMP/out"
SOURCE_MANIFEST="$TMP/sources.tsv"
# Fixture-only identifiers, not published repository metadata.
ref="$(printf '%040d' 0)"
sha="$(sha256sum "$MOCK_SCRIPT" | awk '{print $1}')"
write_row() {
  printf 'test-nodequality\t%s\t%s\t%s\t%s\ttest-nodequality.sh\n' "$1" "$2" "$3" "$4" > "$SOURCE_MANIFEST"
}
for mode in dynamic wrong-repository short-ref missing-hash; do
  url="https://raw.githubusercontent.com/nbbk/NodeQuality/$ref/NodeQuality.sh"
  version="$ref"; policy=pinned-sha256; digest="$sha"
  case "$mode" in
    dynamic) policy=review-each-download;;
    wrong-repository) url="https://run.NodeQuality.com";;
    short-ref) version=abc123;;
    missing-hash) digest=-;;
  esac
  write_row "$url" "$version" "$policy" "$digest"
  if cli_dispatch nq > "$TMP/out" 2>&1; then exit 1; fi
  [ ! -e "$MOCK_TRACE" ]
done
url="https://raw.githubusercontent.com/nbbk/NodeQuality/$ref/NodeQuality.sh"
write_row "$url" "$ref" pinned-sha256 "$(printf '%064d' 0)"
if cli_dispatch nq > "$TMP/out" 2>&1; then exit 1; fi
grep -q '校验失败' "$TMP/out"
write_row "$url" "$ref" pinned-sha256 "$sha"
output="$(cli_dispatch nq 'two words' 2>/dev/null)"
grep -Fxq 'mock-nodequality:<two words>' <<< "$output"
# shellcheck disable=SC2317
confirm() { return 1; }
output="$(cli_dispatch nq 2>/dev/null)"
if grep -q '^mock-nodequality:' <<< "$output"; then exit 1; fi
rm "$MOCK_TRACE"
output="$(cli_dispatch --dry-run nq 2>/dev/null)"
[[ "$output" == *DRY-RUN* ]]
[ ! -e "$MOCK_TRACE" ]
echo 'nodequality-contract: PASS (mock only)'
