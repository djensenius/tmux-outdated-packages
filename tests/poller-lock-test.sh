#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POLLER="$ROOT_DIR/scripts/poller.sh"
TRIGGER_REFRESH="$ROOT_DIR/scripts/trigger-refresh.sh"
TEST_TMP=$(mktemp -d)
owner_pid=''
startup_pid=''

cleanup() {
	if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
		kill -TERM "$owner_pid"
		wait "$owner_pid" 2>/dev/null || true
	fi
	if [ -n "$startup_pid" ] && kill -0 "$startup_pid" 2>/dev/null; then
		kill -TERM "$startup_pid"
		wait "$startup_pid" 2>/dev/null || true
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
[ "$(awk 'NR == 1 { print; exit }' "$CACHE_DIR/poller.lock/pid")" = "$owner_pid" ]
[ -n "$(awk 'NR == 2 {$1 = $1; print; exit}' "$CACHE_DIR/poller.lock/pid")" ]

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
	[ "$(awk "NR == 1 { print; exit }" "$LOCK_OWNER_FILE")" = "$$" ]
	release_lock
' _ "$POLLER"

[ ! -e "$CACHE_DIR/poller.lock" ]

bash -c '
	source "$1"
	setup
	acquire_lock
	trap cleanup_startup INT TERM
	: > "$CACHE_DIR/startup.ready"
	while :; do
		sleep 1
		:
	done
' _ "$POLLER" &
startup_pid=$!

attempts=0
while [ ! -f "$CACHE_DIR/startup.ready" ] && [ "$attempts" -lt 50 ]; do
	attempts=$((attempts + 1))
	sleep 0.1
done

[ -f "$CACHE_DIR/startup.ready" ]
kill -TERM "$startup_pid"
wait "$startup_pid" 2>/dev/null || true
startup_pid=''
[ ! -e "$CACHE_DIR/poller.lock" ]

mock_bin="$TEST_TMP/bin"
mkdir -p "$mock_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$mock_bin/tmux"
chmod +x "$mock_bin/tmux"
printf '%s\n' 99999999 'stale start time' > "$CACHE_DIR/poller.pid"
PATH="$mock_bin:$PATH" "$TRIGGER_REFRESH"
[ "$(awk 'NR == 1 { print; exit }' "$CACHE_DIR/poller.pid")" = 99999999 ]
