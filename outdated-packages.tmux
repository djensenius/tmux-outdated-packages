#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

outdated_packages_interpolation="#($CURRENT_DIR/scripts/outdated-packages.sh)"

set_tmux_option() {
	local option=$1
	local value=$2
	tmux set-option -gq "$option" "$value"
}

start_poller() {
	# Start background poller if not already running
	local cache_dir="${TMPDIR:-/tmp}/tmux-outdated-packages"
	local pid_file="$cache_dir/poller.pid"
	
	# Check if poller is already running
	if [ -f "$pid_file" ]; then
		local pid=$(cat "$pid_file")
		if kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	fi
	
	# Start poller in background
	"$CURRENT_DIR/scripts/poller.sh" &
	disown
}

main() {
	set_tmux_option "@catppuccin_status_outdated_packages" "$outdated_packages_interpolation"
	start_poller
}

main
