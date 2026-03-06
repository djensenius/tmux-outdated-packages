#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
PID_FILE="$CACHE_DIR/poller.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill -SIGUSR1 "$PID"
        tmux display-message "Outdated packages: refreshing..."
    else
        tmux display-message "Outdated packages: poller not running"
    fi
else
    tmux display-message "Outdated packages: poller not running"
fi
