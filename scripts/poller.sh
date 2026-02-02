#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
POLL_INTERVAL="${TMUX_OUTDATED_POLL_INTERVAL:-300}"  # Default 5 minutes
WATCH_INTERVAL=5  # Check file changes every 5 seconds
CHECK_TIMEOUT=120 # Timeout for each check in seconds
DEBUG_MODE="${TMUX_OUTDATED_DEBUG:-0}"
FORCE_UPDATE=0
LOG_FILE="$CACHE_DIR/poller.log"
LOCK_FILE="$CACHE_DIR/poller.lock"
PID_FILE="$CACHE_DIR/poller.pid"

# Package install directories for quick change detection
BREW_CELLAR="${HOMEBREW_PREFIX:-/usr/local}/Cellar"
BREW_TAPS="${HOMEBREW_PREFIX:-/usr/local}/Library/Taps"
NPM_GLOBAL="$(npm config get prefix 2>/dev/null)/lib/node_modules"
NPM_BIN="$(npm config get prefix 2>/dev/null)/bin"
PIP_SITE="$(python3 -m site --user-site 2>/dev/null)"
CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"

log_debug() {
	if [ "$DEBUG_MODE" = "1" ]; then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
	fi
}

handle_sigusr1() {
	log_debug "Received SIGUSR1, forcing update..."
	FORCE_UPDATE=1
}

setup() {
	mkdir -p "$CACHE_DIR"
	if [ "$DEBUG_MODE" = "1" ]; then
		log_debug "=== Poller started with PID $$ ==="
		log_debug "Poll interval: ${POLL_INTERVAL}s"
		log_debug "Cache directory: $CACHE_DIR"
	fi
}

check_if_running() {
	if [ -f "$PID_FILE" ]; then
		local pid
		pid=$(cat "$PID_FILE")
		if kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

get_dir_mtime() {
	if [ -d "$1" ]; then
		stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
	else
		echo "0"
	fi
}

should_check() {
	local name=$1
	local dirs_str=$2
	local count_file="$CACHE_DIR/${name}.count"
	
	# Always check on first run
	if [ ! -f "$count_file" ]; then
		log_debug "$name: First run, checking..."
		return 0
	fi
	
	# Check for forced update
	if [ "${FORCE_UPDATE:-0}" -eq 1 ]; then
		log_debug "$name: Forced update requested"
		return 0
	fi
	
	# Check if poll interval passed
	local last_check=0
	if [ -f "$count_file" ]; then
		last_check=$(stat -f %m "$count_file" 2>/dev/null || stat -c %Y "$count_file" 2>/dev/null || echo 0)
	fi
	local now
	now=$(date +%s)
	if [ $((now - last_check)) -ge "$POLL_INTERVAL" ]; then
		log_debug "$name: Poll interval passed, checking..."
		return 0
	fi
	
	local IFS=':'
	read -ra dirs <<< "$dirs_str"
	
	if [ ${#dirs[@]} -eq 0 ]; then
		log_debug "$name: No directory to monitor, checking on interval"
		return 0
	fi
	
	local changed=0
	for i in "${!dirs[@]}"; do
		local dir="${dirs[$i]}"
		local mtime_file="$CACHE_DIR/${name}.mtime"
		
		# If multiple directories, use suffixed mtime files
		if [ ${#dirs[@]} -gt 1 ]; then
			mtime_file="$CACHE_DIR/${name}_${i}.mtime"
		fi
		
		if [ -n "$dir" ] && [ -d "$dir" ]; then
			local current_mtime
			current_mtime=$(get_dir_mtime "$dir")
			local cached_mtime
			cached_mtime=$(cat "$mtime_file" 2>/dev/null || echo "0")
			
			if [ "$current_mtime" != "$cached_mtime" ]; then
				log_debug "$name: Directory $dir changed (mtime: $cached_mtime -> $current_mtime)"
				echo "$current_mtime" > "$mtime_file"
				changed=1
			fi
		fi
	done
	
	if [ "$changed" -eq 1 ]; then
		return 0
	fi
	
	log_debug "$name: No changes detected, skipping"
	return 1
}

check_brew() {
	if ! command -v brew &> /dev/null; then
		log_debug "brew: Not installed, skipping"
		return
	fi
	
	if should_check "brew" "$BREW_CELLAR:$BREW_TAPS"; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" brew outdated --verbose 2>/dev/null)
		local count
		count=$(echo "$output" | grep -c '[^[:space:]]' || echo "0")
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/brew.count"
		echo "$output" > "$CACHE_DIR/brew.list"
		log_debug "brew: Found $count outdated packages (took ${duration}s)"
	fi
}

check_npm() {
	if ! command -v npm &> /dev/null; then
		log_debug "npm: Not installed, skipping"
		return
	fi
	
	if should_check "npm" "$NPM_GLOBAL:$NPM_BIN"; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" npm outdated -g 2>/dev/null)
		local count
		count=$(echo "$output" | tail -n +2 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/npm.count"
		echo "$output" > "$CACHE_DIR/npm.list"
		log_debug "npm: Found $count outdated packages (took ${duration}s)"
	fi
}

check_pip() {
	if ! command -v pip3 &> /dev/null; then
		log_debug "pip3: Not installed, skipping"
		return
	fi
	
	if should_check "pip" "$PIP_SITE"; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" pip3 list --outdated 2>/dev/null)
		local count
		count=$(echo "$output" | tail -n +3 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/pip.count"
		echo "$output" > "$CACHE_DIR/pip.list"
		log_debug "pip3: Found $count outdated packages (took ${duration}s)"
	fi
}

check_cargo() {
	if ! command -v cargo &> /dev/null || ! command -v cargo-install-update &> /dev/null; then
		log_debug "cargo: Not installed or cargo-install-update missing, skipping"
		return
	fi
	
	if should_check "cargo" "$CARGO_BIN"; then
		local start
		start=$(date +%s)
		local raw_output
		raw_output=$(timeout "$CHECK_TIMEOUT" cargo install-update --list 2>/dev/null)
		local output
		output=$(echo "$raw_output" | grep -E "Needs update|Yes[[:space:]]*$")
		local count
		count=$(echo "$output" | grep -c "Yes[[:space:]]*$" || echo "0")
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/cargo.count"
		echo "$output" > "$CACHE_DIR/cargo.list"
		log_debug "cargo: Found $count outdated packages (took ${duration}s)"
	fi
}

check_composer() {
	if ! command -v composer &> /dev/null; then
		log_debug "composer: Not installed, skipping"
		return
	fi
	
	if should_check "composer" ""; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" composer global outdated 2>/dev/null)
		local count
		count=$(echo "$output" | grep -c '^[a-z]' || echo "0")
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/composer.count"
		echo "$output" > "$CACHE_DIR/composer.list"
		log_debug "composer: Found $count outdated packages (took ${duration}s)"
	fi
}

check_go() {
	if ! command -v go &> /dev/null || ! command -v go-global-update &> /dev/null; then
		log_debug "go: Not installed or go-global-update missing, skipping"
		return
	fi
	
	if should_check "go" ""; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" go-global-update -n 2>/dev/null)
		local count
		count=$(echo "$output" | grep -c "outdated" || echo "0")
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/go.count"
		echo "$output" > "$CACHE_DIR/go.list"
		log_debug "go: Found $count outdated packages (took ${duration}s)"
	fi
}

check_apt() {
	if ! command -v apt &> /dev/null; then
		log_debug "apt: Not installed, skipping"
		return
	fi
	
	if [ -r /var/lib/apt/lists ] || [ "$EUID" -eq 0 ]; then
		if should_check "apt" "/var/lib/apt/lists"; then
			local start
			start=$(date +%s)
			local output
			output=$(timeout "$CHECK_TIMEOUT" apt list --upgradable 2>/dev/null)
			local count
			count=$(echo "$output" | grep -c "upgradable" || echo "0")
			local duration=$(($(date +%s) - start))
			echo "$count" > "$CACHE_DIR/apt.count"
			echo "$output" > "$CACHE_DIR/apt.list"
			log_debug "apt: Found $count outdated packages (took ${duration}s)"
		fi
	else
		log_debug "apt: No permissions to check, skipping"
	fi
}

check_dnf() {
	if ! command -v dnf &> /dev/null; then
		log_debug "dnf: Not installed, skipping"
		return
	fi
	
	if should_check "dnf" ""; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" dnf list --upgrades 2>/dev/null)
		local count
		count=$(echo "$output" | tail -n +2 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/dnf.count"
		echo "$output" > "$CACHE_DIR/dnf.list"
		log_debug "dnf: Found $count outdated packages (took ${duration}s)"
	fi
}

check_mise() {
	if ! command -v mise &> /dev/null; then
		log_debug "mise: Not installed, skipping"
		return
	fi
	
	# Check common config locations
	local config_files="$HOME/.config/mise/config.toml:$HOME/.mise.toml:$HOME/.tool-versions"
	
	if should_check "mise" "$config_files"; then
		local start
		start=$(date +%s)
		local output
		output=$(timeout "$CHECK_TIMEOUT" mise outdated 2>/dev/null)
		local count=0
		
		if [[ "$output" != *"All tools are up to date"* ]] && [ -n "$output" ]; then
			count=$(echo "$output" | grep -c '[^[:space:]]')
		else
			output=""
		fi
		
		local duration=$(($(date +%s) - start))
		echo "$count" > "$CACHE_DIR/mise.count"
		echo "$output" > "$CACHE_DIR/mise.list"
		log_debug "mise: Found $count outdated packages (took ${duration}s)"
	fi
}

run_checks_parallel() {
	log_debug "--- Starting check cycle ---"
	local cycle_start
	cycle_start=$(date +%s)
	
	# Run all checks in parallel background jobs
	check_brew &
	check_npm &
	check_pip &
	check_cargo &
	check_composer &
	check_go &
	check_apt &
	check_dnf &
	check_mise &
	
	# Wait for all background jobs to complete
	wait
	
	local cycle_duration=$(($(date +%s) - cycle_start))
	log_debug "--- Check cycle complete (took ${cycle_duration}s) ---"
}

cleanup() {
	log_debug "=== Poller stopped ==="
	rm -f "$LOCK_FILE" "$PID_FILE"
	exit 0
}

main() {
	setup
	
	# Check if already running
	if check_if_running; then
		log_debug "Poller already running, exiting"
		exit 0
	fi
	
	# Write PID
	echo $$ > "$PID_FILE"
	log_debug "PID file written: $PID_FILE"
	
	# Trap cleanup
	trap cleanup EXIT INT TERM
	trap handle_sigusr1 SIGUSR1
	
	# Initial check
	run_checks_parallel
	
	# Poll loop
	while true; do
		log_debug "Sleeping for ${WATCH_INTERVAL}s..."
		sleep "$WATCH_INTERVAL"
		run_checks_parallel
		FORCE_UPDATE=0
	done
}

main
