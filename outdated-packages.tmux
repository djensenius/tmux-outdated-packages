#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

get_tmux_option() {
	local option=$1
	local default_value=$2
	local option_value=$(tmux show-option -gqv "$option")
	if [ -z "$option_value" ]; then
		echo "$default_value"
	else
		echo "$option_value"
	fi
}

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
	mkdir -p "$cache_dir"
	"$CURRENT_DIR/scripts/poller.sh" &
	disown
}

main() {
	local text_color=$(get_tmux_option "@outdated_text_color" "white")
	
	# Build the status module - use show-status.sh which handles spinner
	local script_call="#($CURRENT_DIR/scripts/show-status.sh)"
	
	# Set the interpolation variable for direct use
	set_tmux_option "@outdated_packages" "$script_call"
	
	# Check if catppuccin is installed/active
	local catppuccin_active=$(tmux show-option -gqv "@catppuccin_status_application")
	
	if [ -n "$catppuccin_active" ]; then
		# Catppuccin is active, use its formatting
		set_tmux_option "@catppuccin_status_outdated_packages" "#[fg=$text_color]$script_call#[default]"
	else
		# No catppuccin - use simple formatting
		set_tmux_option "@catppuccin_status_outdated_packages" "#[fg=$text_color]$script_call#[default]"
	fi
	
	# Start the background poller
	start_poller
	
	# Set up mouse binding - click on status-right to show popup
	tmux bind-key -n MouseDown1StatusRight run-shell "$CURRENT_DIR/scripts/show-popup.sh"
	
	# Set up keyboard binding - prefix + u to show popup
	tmux bind-key u run-shell "$CURRENT_DIR/scripts/show-popup.sh"
}

main
