#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
PID_FILE="$CACHE_DIR/poller.pid"

poller_is_running() {
    local pid=$1 recorded_start actual_start process_command
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    recorded_start=$(awk 'NR == 2 {$1 = $1; print; exit}' "$PID_FILE")
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

if [ -f "$PID_FILE" ]; then
    PID=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$PID_FILE")
    if poller_is_running "$PID"; then
        kill -SIGUSR1 "$PID"
        tmux display-message "Outdated packages: refreshing..."
    else
        rm -f "$PID_FILE"
        tmux display-message "Outdated packages: poller not running"
    fi
else
    tmux display-message "Outdated packages: poller not running"
fi
