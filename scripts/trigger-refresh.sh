#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
PID_FILE="$CACHE_DIR/poller.pid"

poller_is_running() {
    local pid=$1 recorded_start actual_start process_command
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    recorded_start=$(awk 'NR == 2 {$1 = $1; print; exit}' "$PID_FILE" 2>/dev/null)
    if [ -n "$recorded_start" ]; then
        actual_start=$(LC_ALL=C ps -ww -p "$pid" -o lstart= 2>/dev/null |
            awk '{$1 = $1; print; exit}')
        if [ -z "$actual_start" ] || [ "$recorded_start" != "$actual_start" ]; then
            return 1
        fi
        process_command=$(ps -ww -p "$pid" -o command= 2>/dev/null) || return 1
        [[ "$process_command" == *"/scripts/poller.sh"* ]]
        return
    fi

    process_command=$(ps -ww -p "$pid" -o command= 2>/dev/null) || return 1
    [[ "$process_command" == *"/scripts/poller.sh"* ]]
}

attempts=0
while [ "$attempts" -lt 2 ]; do
    PID=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$PID_FILE" 2>/dev/null)
    if poller_is_running "$PID" && kill -SIGUSR1 "$PID" 2>/dev/null; then
        tmux display-message "Outdated packages: refreshing..."
        exit 0
    fi
    attempts=$((attempts + 1))
done

tmux display-message "Outdated packages: poller not running"
