#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POLLER="$ROOT_DIR/scripts/poller.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# shellcheck source=/dev/null
source "$POLLER"

CACHE_DIR="$TEST_TMP/cache"
CHECKING_FILE="$CACHE_DIR/checking"
COMPLETE_FILE="$CACHE_DIR/complete"
mkdir -p "$CACHE_DIR"

check_brew() {
	sleep 1
	: > "$CACHE_DIR/slow-check-complete"
}
check_npm() { :; }
check_pip() { :; }
check_cargo() { :; }
check_composer() { :; }
check_go() { :; }
check_apt() { :; }
check_dnf() { :; }
check_mise() { :; }

trap handle_sigusr1 USR1
(sleep 0.1; kill -USR1 "$$") &
signal_sender=$!

run_checks_parallel
wait "$signal_sender"

[ -f "$CACHE_DIR/slow-check-complete" ]
[ ! -e "$CHECKING_FILE" ]
[ -f "$COMPLETE_FILE" ]
[ "$REFRESH_GENERATION" -eq 1 ]

REFRESH_GENERATION=0
APPLIED_REFRESH_GENERATION=0
begin_check_cycle
handle_sigusr1
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 0 ]

begin_check_cycle
[ "$CURRENT_FORCE_UPDATE" -eq 1 ]
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 1 ]

record_file="$CACHE_DIR/test.pid"
write_process_record "$record_file"
[ "$(awk 'END { print NR }' "$record_file")" -eq 2 ]
[ "$(awk 'NR == 1 { print; exit }' "$record_file")" = "$$" ]
[ -n "$(awk 'NR == 2 {$1 = $1; print; exit}' "$record_file")" ]
[ ! -e "$CACHE_DIR/.test.pid.$$.tmp" ]
[ -z "$PROCESS_RECORD_TEMP" ]

mock_bin="$TEST_TMP/bin"
mkdir -p "$mock_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$mock_bin/npm"
chmod +x "$mock_bin/npm"
PATH="$mock_bin:/usr/bin:/bin" bash -c '
	# shellcheck source=/dev/null
	source "$1"
	[ -z "$NPM_WATCH_DIRS" ]
' _ "$POLLER"
