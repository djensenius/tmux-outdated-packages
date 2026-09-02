#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POLLER="$ROOT_DIR/scripts/poller.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# shellcheck source=/dev/null
source "$POLLER"

CACHE_DIR="$TEST_TMP/cache"
LOG_FILE="$CACHE_DIR/poller.log"
LOCK_DIR="$CACHE_DIR/poller.lock"
LOCK_OWNER_FILE="$LOCK_DIR/pid"
PID_FILE="$CACHE_DIR/poller.pid"
CHECKING_FILE="$CACHE_DIR/checking"
COMPLETE_FILE="$CACHE_DIR/complete"
REFRESH_COMPLETE_FILE="$CACHE_DIR/refresh-complete"
mkdir -p "$CACHE_DIR"

original_path=$PATH
timeout_bin="$TEST_TMP/timeout-bin"
gtimeout_bin="$TEST_TMP/gtimeout-bin"
missing_timeout_bin="$TEST_TMP/missing-timeout-bin"
mkdir -p "$timeout_bin" "$gtimeout_bin" "$missing_timeout_bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" timeout' > "$timeout_bin/timeout"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" gtimeout' > "$timeout_bin/gtimeout"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" gtimeout' > "$gtimeout_bin/gtimeout"
chmod +x "$timeout_bin/timeout" "$timeout_bin/gtimeout" "$gtimeout_bin/gtimeout"

PATH="$timeout_bin"
hash -r
TIMEOUT_COMMAND=''
resolve_timeout_command
[ "$TIMEOUT_COMMAND" = "$timeout_bin/timeout" ]
[ "$(run_with_timeout package-check)" = timeout ]

PATH="$gtimeout_bin"
hash -r
TIMEOUT_COMMAND=''
resolve_timeout_command
[ "$TIMEOUT_COMMAND" = "$gtimeout_bin/gtimeout" ]
[ "$(run_with_timeout package-check)" = gtimeout ]

PATH="$missing_timeout_bin"
hash -r
TIMEOUT_COMMAND=''
if resolve_timeout_command 2> "$TEST_TMP/missing-timeout.err"; then
	printf 'timeout resolution unexpectedly succeeded\n' >&2
	exit 1
fi
[ -z "$TIMEOUT_COMMAND" ]
PATH="$original_path"
hash -r
grep -q "neither 'timeout' nor 'gtimeout'" "$TEST_TMP/missing-timeout.err"

PATH="$missing_timeout_bin"
hash -r
TIMEOUT_COMMAND=''
if main 2> "$TEST_TMP/missing-timeout-startup.err"; then
	printf 'poller startup unexpectedly succeeded without timeout support\n' >&2
	exit 1
fi
PATH="$original_path"
hash -r
[ ! -e "$LOG_FILE" ]
[ ! -e "$LOCK_DIR" ]
[ ! -e "$LOCK_OWNER_FILE" ]
[ ! -e "$PID_FILE" ]
[ ! -e "$CHECKING_FILE" ]
[ ! -e "$COMPLETE_FILE" ]
[ ! -e "$REFRESH_COMPLETE_FILE" ]
grep -q "neither 'timeout' nor 'gtimeout'" "$TEST_TMP/missing-timeout-startup.err"

: > "$REFRESH_COMPLETE_FILE"
queue_sigusr1
[ "$REFRESH_GENERATION" -eq 1 ]
[ ! -e "$REFRESH_COMPLETE_FILE" ]
REFRESH_GENERATION=0

# shellcheck disable=SC2317,SC2329 # Invoked by run_checks_parallel from the sourced poller.
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
[ -s "$COMPLETE_FILE" ]
[ "$REFRESH_GENERATION" -eq 1 ]

check_brew() { :; }
# shellcheck disable=SC2317,SC2329 # Overrides date calls in the sourced poller.
date() {
	if [ "${1:-}" = "+%s" ]; then
		printf '%s\n' 1234567890
	else
		command date "$@"
	fi
}
run_checks_parallel
same_second_token_one=$(cat "$COMPLETE_FILE")
run_checks_parallel
same_second_token_two=$(cat "$COMPLETE_FILE")
unset -f date
[ "$same_second_token_one" != "$same_second_token_two" ]

previous_token=$same_second_token_two
atomic_source=''
atomic_previous=''
# shellcheck disable=SC2317,SC2329 # Overrides the atomic rename in publish_complete.
mv() {
	if [ "$#" -ne 3 ] || [ "$1" != "-f" ] || [ "$3" != "$COMPLETE_FILE" ]; then
		return 1
	fi
	atomic_source=$2
	[ -s "$atomic_source" ] || return 1
	atomic_previous=$(cat "$COMPLETE_FILE")
	[ "$atomic_previous" = "$previous_token" ] || return 1
	command mv "$@"
}
publish_complete
unset -f mv
atomic_token=$(cat "$COMPLETE_FILE")
[ "$atomic_previous" = "$previous_token" ]
[ "$atomic_token" != "$previous_token" ]
[ ! -e "$atomic_source" ]
[ -z "$COMPLETE_TEMP" ]

previous_generation=$COMPLETE_GENERATION
failed_temp="$CACHE_DIR/.complete.$$.$((previous_generation + 1)).tmp"
# shellcheck disable=SC2317,SC2329 # Forces the publish_complete failure path.
mv() { return 1; }
if run_checks_parallel; then
	printf 'completion publication unexpectedly succeeded\n' >&2
	exit 1
fi
unset -f mv
[ "$COMPLETE_GENERATION" -eq "$previous_generation" ]
[ "$(cat "$COMPLETE_FILE")" = "$atomic_token" ]
[ ! -e "$failed_temp" ]
[ ! -e "$CHECKING_FILE" ]
[ -z "$COMPLETE_TEMP" ]

COMPLETE_TEMP="$CACHE_DIR/.complete.cleanup.tmp"
: > "$COMPLETE_TEMP"
cleanup_temp=$COMPLETE_TEMP
cleanup_complete_temp
[ ! -e "$cleanup_temp" ]
[ -z "$COMPLETE_TEMP" ]

cleanup_status=0
if (cleanup 23); then
	printf 'cleanup unexpectedly replaced a failure status\n' >&2
	exit 1
else
	cleanup_status=$?
fi
[ "$cleanup_status" -eq 23 ]

for signal_case in INT:130 TERM:143; do
	signal_name=${signal_case%%:*}
	expected_status=${signal_case##*:}
	signal_status=0
	if bash -c '
		# shellcheck source=/dev/null
		source "$1"
		CACHE_DIR="$2"
		LOG_FILE="$CACHE_DIR/poller.log"
		LOCK_DIR="$CACHE_DIR/poller.lock"
		LOCK_OWNER_FILE="$LOCK_DIR/pid"
		PID_FILE="$CACHE_DIR/poller.pid"
		CHECKING_FILE="$CACHE_DIR/checking"
		COMPLETE_FILE="$CACHE_DIR/complete"
		REFRESH_COMPLETE_FILE="$CACHE_DIR/refresh-complete"
		install_runtime_traps
		kill "-$3" "$$"
		exit 99
	' _ "$POLLER" "$TEST_TMP/signal-$signal_name" "$signal_name"; then
		printf '%s trap unexpectedly succeeded\n' "$signal_name" >&2
		exit 1
	else
		signal_status=$?
	fi
	[ "$signal_status" -eq "$expected_status" ]
done

REFRESH_GENERATION=0
APPLIED_REFRESH_GENERATION=0
begin_check_cycle
handle_sigusr1
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 0 ]
[ ! -e "$REFRESH_COMPLETE_FILE" ]

begin_check_cycle
[ "$CURRENT_FORCE_UPDATE" -eq 1 ]
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 1 ]
[ -f "$REFRESH_COMPLETE_FILE" ]

handle_sigusr1
[ ! -e "$REFRESH_COMPLETE_FILE" ]
begin_check_cycle
[ "$CURRENT_FORCE_UPDATE" -eq 1 ]
handle_sigusr1
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 2 ]
[ ! -e "$REFRESH_COMPLETE_FILE" ]

begin_check_cycle
[ "$CURRENT_FORCE_UPDATE" -eq 1 ]
complete_check_cycle
[ "$APPLIED_REFRESH_GENERATION" -eq 3 ]
[ -f "$REFRESH_COMPLETE_FILE" ]

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
