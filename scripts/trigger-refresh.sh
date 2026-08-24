#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
PID_FILE="$CACHE_DIR/poller.pid"
POLLER_COMMAND_PATH="tmux-outdated-packages/scripts/poller.sh"

if [ -f "$PID_FILE" ]; then
    PID=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$PID_FILE")
    PROCESS_COMMAND=$(ps -ww -p "$PID" -o command= 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null &&
        [[ "$PROCESS_COMMAND" == *"$POLLER_COMMAND_PATH"* ]]; then
        kill -SIGUSR1 "$PID"
        tmux display-message "Outdated packages: refreshing..."
    else
        rm -f "$PID_FILE"
        tmux display-message "Outdated packages: poller not running"
    fi
else
    tmux display-message "Outdated packages: poller not running"
fi
