#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
POLL_INTERVAL="${TMUX_OUTDATED_POLL_INTERVAL:-300}"  # Default 5 minutes
WATCH_INTERVAL=5  # Check file changes every 5 seconds
CHECK_TIMEOUT=120 # Timeout for each check in seconds
DEBUG_MODE="${TMUX_OUTDATED_DEBUG:-0}"
REFRESH_GENERATION=0
APPLIED_REFRESH_GENERATION=0
CYCLE_REFRESH_GENERATION=0
CURRENT_FORCE_UPDATE=0
LOG_FILE="$CACHE_DIR/poller.log"
LOCK_DIR="$CACHE_DIR/poller.lock"
LOCK_OWNER_FILE="$LOCK_DIR/pid"
PID_FILE="$CACHE_DIR/poller.pid"
CHECKING_FILE="$CACHE_DIR/checking"
COMPLETE_FILE="$CACHE_DIR/complete"
PROCESS_START_TIME=''
PROCESS_RECORD_TEMP=''

# Package install directories for quick change detection
BREW_CELLAR="${HOMEBREW_PREFIX:-/usr/local}/Cellar"
BREW_TAPS="${HOMEBREW_PREFIX:-/usr/local}/Library/Taps"
NPM_PREFIX="$(npm config get prefix 2>/dev/null || true)"
NPM_WATCH_DIRS=''
if [ -n "$NPM_PREFIX" ]; then
	NPM_WATCH_DIRS="$NPM_PREFIX/lib/node_modules:$NPM_PREFIX/bin"
fi
PIP_SITE="$(python3 -m site --user-site 2>/dev/null || true)"
CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"

log_debug() {
	if [ "$DEBUG_MODE" = "1" ]; then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
	fi
}

process_start_time() {
	local pid=$1 start
	case "$pid" in
		'' | *[!0-9]*) return 1 ;;
	esac
	kill -0 "$pid" 2>/dev/null || return 1
	start=$(LC_ALL=C ps -ww -p "$pid" -o lstart= 2>/dev/null |
		awk '{$1 = $1; print; exit}')
	[ -n "$start" ] || return 1
	printf '%s\n' "$start"
}

poller_command_is_running() {
	local pid=$1 process_command
	kill -0 "$pid" 2>/dev/null || return 1
	process_command=$(ps -ww -p "$pid" -o command= 2>/dev/null) || return 1
	case "$process_command" in
		*"/scripts/poller.sh"*) return 0 ;;
		*) return 1 ;;
	esac
}

process_record_is_running() {
	local file=$1 pid recorded_start actual_start
	pid=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$file" 2>/dev/null)
	recorded_start=$(awk 'NR == 2 {$1 = $1; print; exit}' "$file" 2>/dev/null)
	[ -n "$pid" ] || return 1
	if [ -z "$recorded_start" ]; then
		poller_command_is_running "$pid"
		return
	fi
	actual_start=$(process_start_time "$pid") || return 1
	[ "$actual_start" = "$recorded_start" ] &&
		poller_command_is_running "$pid"
}

write_process_record() {
	local file=$1
	if [ -z "$PROCESS_START_TIME" ]; then
		PROCESS_START_TIME=$(process_start_time "$$") || return 1
	fi
	PROCESS_RECORD_TEMP="$CACHE_DIR/.${file##*/}.$$.tmp"
	if ! printf '%s\n%s\n' "$$" "$PROCESS_START_TIME" > "$PROCESS_RECORD_TEMP"; then
		rm -f "$PROCESS_RECORD_TEMP"
		PROCESS_RECORD_TEMP=''
		return 1
	fi
	if ! mv -f "$PROCESS_RECORD_TEMP" "$file"; then
		rm -f "$PROCESS_RECORD_TEMP"
		PROCESS_RECORD_TEMP=''
		return 1
	fi
	PROCESS_RECORD_TEMP=''
}

acquire_lock() {
	local attempts=0 owner
	while [ "$attempts" -lt 50 ]; do
		if mkdir "$LOCK_DIR" 2>/dev/null; then
			if write_process_record "$LOCK_OWNER_FILE"; then
				return 0
			fi
			rmdir "$LOCK_DIR" 2>/dev/null || true
			return 1
		fi

		owner=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$LOCK_OWNER_FILE" 2>/dev/null)
		if [ -n "$owner" ] && process_record_is_running "$LOCK_OWNER_FILE"; then
			return 1
		fi

		# Give a new owner time to publish its PID before treating an empty
		# directory as a stale lock.
		if [ -n "$owner" ] || [ "$attempts" -ge 10 ]; then
			rm -f "$LOCK_OWNER_FILE"
			rmdir "$LOCK_DIR" 2>/dev/null || true
			if [ -e "$LOCK_DIR" ] && [ ! -d "$LOCK_DIR" ]; then
				rm -f "$LOCK_DIR"
			fi
		fi
		attempts=$((attempts + 1))
		sleep 0.1
	done
	return 1
}

release_lock() {
	local owner
	owner=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$LOCK_OWNER_FILE" 2>/dev/null)
	[ "$owner" = "$$" ] || return 0
	rm -f "$LOCK_OWNER_FILE"
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

cleanup_startup() {
	if [ "$(awk 'NR == 1 { print; exit }' "$PID_FILE" 2>/dev/null)" = "$$" ]; then
		rm -f "$PID_FILE"
	fi
	if [ -n "$PROCESS_RECORD_TEMP" ]; then
		rm -f "$PROCESS_RECORD_TEMP"
	fi
	release_lock
	exit 130
}

handle_sigusr1() {
	log_debug "Received SIGUSR1, forcing update..."
	REFRESH_GENERATION=$((REFRESH_GENERATION + 1))
}

begin_check_cycle() {
	CYCLE_REFRESH_GENERATION=$REFRESH_GENERATION
	if [ "$CYCLE_REFRESH_GENERATION" -gt "$APPLIED_REFRESH_GENERATION" ]; then
		CURRENT_FORCE_UPDATE=1
	else
		CURRENT_FORCE_UPDATE=0
	fi
}

complete_check_cycle() {
	if [ "$CURRENT_FORCE_UPDATE" -eq 1 ]; then
		APPLIED_REFRESH_GENERATION=$CYCLE_REFRESH_GENERATION
	fi
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
	local pid
	[ -f "$PID_FILE" ] || return 1
	pid=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$PID_FILE")
	[ "$pid" != "$$" ] && process_record_is_running "$PID_FILE"
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
	if [ "${CURRENT_FORCE_UPDATE:-0}" -eq 1 ]; then
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
		log_debug "$name: No directory to monitor, relying on poll interval, skipping"
		return 1
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
	
	if should_check "npm" "$NPM_WATCH_DIRS"; then
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
	local pid
	local pids=()
	cycle_start=$(date +%s)
	: > "$CHECKING_FILE"
	
	# Run all checks in parallel background jobs
	check_brew & pids+=("$!")
	check_npm & pids+=("$!")
	check_pip & pids+=("$!")
	check_cargo & pids+=("$!")
	check_composer & pids+=("$!")
	check_go & pids+=("$!")
	check_apt & pids+=("$!")
	check_dnf & pids+=("$!")
	check_mise & pids+=("$!")
	
	# A trapped refresh signal interrupts wait. Retry while the child still
	# exists so completion is not published before every check has finished.
	for pid in "${pids[@]}"; do
		while ! wait "$pid" 2>/dev/null; do
			kill -0 "$pid" 2>/dev/null || break
		done
	done
	rm -f "$CHECKING_FILE"
	touch "$COMPLETE_FILE"
	
	local cycle_duration=$(($(date +%s) - cycle_start))
	log_debug "--- Check cycle complete (took ${cycle_duration}s) ---"
}

cleanup() {
	log_debug "=== Poller stopped ==="
	if [ "$(awk 'NR == 1 { print; exit }' "$PID_FILE" 2>/dev/null)" = "$$" ]; then
		rm -f "$PID_FILE"
	fi
	rm -f "$CHECKING_FILE"
	release_lock
	exit 0
}

main() {
	setup

	if ! acquire_lock; then
		log_debug "Poller lock is already held, exiting"
		exit 0
	fi
	trap cleanup_startup INT TERM
	
	# Check if already running
	if check_if_running; then
		log_debug "Poller already running, exiting"
		release_lock
		exit 0
	fi
	
	# Write PID
	if ! write_process_record "$PID_FILE"; then
		log_debug "Unable to write poller PID record"
		release_lock
		return 1
	fi
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
		begin_check_cycle
		run_checks_parallel
		complete_check_cycle
	done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main
fi
