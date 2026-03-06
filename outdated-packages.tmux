#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

get_tmux_option() {
	local option=$1
	local default_value=$2
	local option_value
	option_value=$(tmux show-option -gqv "$option")
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
		local pid
		pid=$(cat "$pid_file")
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
	local text_color
	text_color=$(get_tmux_option "@outdated_text_color" "white")
	
	# Build the status module - use show-status.sh which handles spinner
	local script_call="#($CURRENT_DIR/scripts/show-status.sh)"
	
	# Set the interpolation variable for direct use
	set_tmux_option "@outdated_packages" "$script_call"
	
	# Check if catppuccin is installed/active
	local catppuccin_active
	catppuccin_active=$(tmux show-option -gqv "@catppuccin_status_application")
	
	if [ -n "$catppuccin_active" ]; then
		# Catppuccin is active, use its formatting with styled left separator
		set_tmux_option "@catppuccin_status_outdated_packages" "#[fg=#{E:@thm_peach}]#{@_ctp_connect_style}#{@catppuccin_status_left_separator}#[fg=#{E:@catppuccin_status_module_text_fg},bg=#{E:@thm_peach}]#{@catppuccin_status_middle_separator}#[fg=#{E:@thm_text},bg=#{E:@catppuccin_status_module_text_bg}]$script_call#[fg=#{E:@catppuccin_status_module_text_bg}]#{@_ctp_connect_style}#{@catppuccin_status_right_separator}"
	else
		# No catppuccin - use simple formatting
		set_tmux_option "@catppuccin_status_outdated_packages" "#[fg=$text_color]$script_call#[default]"
	fi
	
	# Start the background poller
	start_poller
	
	# Configurable keybindings
	local popup_key
	popup_key=$(get_tmux_option "@outdated_popup_key" "P")
	local refresh_key
	refresh_key=$(get_tmux_option "@outdated_refresh_key" "u")
	local mouse_click
	mouse_click=$(get_tmux_option "@outdated_mouse_click" "on")
	local update_key
	update_key=$(get_tmux_option "@outdated_update_key" "")

	# Mouse binding
	if [ "$mouse_click" = "on" ]; then
		tmux bind-key -n MouseDown1StatusRight run-shell "$CURRENT_DIR/scripts/show-popup.sh"
	fi

	# Popup key
	if [ -n "$popup_key" ]; then
		tmux bind-key "$popup_key" run-shell "$CURRENT_DIR/scripts/show-popup.sh"
	fi

	# Refresh key
	if [ -n "$refresh_key" ]; then
		tmux bind-key "$refresh_key" run-shell "$CURRENT_DIR/scripts/trigger-refresh.sh"
	fi

	# Update key (interactive update selector)
	if [ -n "$update_key" ]; then
		tmux bind-key "$update_key" display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/update-packages.sh"
	fi
}

main
