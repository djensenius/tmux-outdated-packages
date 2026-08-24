#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POLLER="$ROOT_DIR/scripts/poller.sh"
TEST_TMP=$(mktemp -d)
owner_pid=''

cleanup() {
	if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
		kill -TERM "$owner_pid"
		wait "$owner_pid" 2>/dev/null || true
	fi
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

export TMPDIR="$TEST_TMP"
CACHE_DIR="$TMPDIR/tmux-outdated-packages"

bash -c '
	source "$1"
	setup
	acquire_lock
	: > "$CACHE_DIR/test.ready"
	trap "exit 0" INT TERM
	while :; do
		sleep 1
		:
	done
' _ "$POLLER" &
owner_pid=$!

attempts=0
while [ ! -f "$CACHE_DIR/test.ready" ] && [ "$attempts" -lt 50 ]; do
	attempts=$((attempts + 1))
	sleep 0.1
done

[ -f "$CACHE_DIR/test.ready" ]
[ "$(cat "$CACHE_DIR/poller.lock/pid")" = "$owner_pid" ]

if bash -c 'source "$1"; setup; acquire_lock' _ "$POLLER"; then
	printf 'a second poller acquired the live lock\n' >&2
	exit 1
fi

kill -TERM "$owner_pid"
wait "$owner_pid" 2>/dev/null || true
owner_pid=''

bash -c '
	source "$1"
	setup
	acquire_lock
	[ "$(cat "$LOCK_OWNER_FILE")" = "$$" ]
	release_lock
' _ "$POLLER"

[ ! -e "$CACHE_DIR/poller.lock" ]
