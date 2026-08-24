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
[ "$FORCE_UPDATE" -eq 1 ]
