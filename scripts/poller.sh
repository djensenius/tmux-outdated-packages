#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
POLL_INTERVAL="${TMUX_OUTDATED_POLL_INTERVAL:-300}"  # Default 5 minutes
WATCH_INTERVAL=5  # Check file changes every 5 seconds
CHECK_TIMEOUT=120 # Timeout for each check in seconds
DEBUG_MODE="${TMUX_OUTDATED_DEBUG:-0}"
TIMEOUT_COMMAND=''
COMPLETE_PROTOCOL_VERSION='v2'
COMPLETE_GENERATION=0
REFRESH_GENERATION=0
APPLIED_REFRESH_GENERATION=0
CYCLE_REFRESH_GENERATION=0
CURRENT_FORCE_UPDATE=0
RETRY_FAILED_CHECKS=0
CHECK_FAILURE_STATUS=2
LOG_FILE="$CACHE_DIR/poller.log"
LOCK_DIR="$CACHE_DIR/poller.lock"
LOCK_OWNER_FILE="$LOCK_DIR/pid"
PID_FILE="$CACHE_DIR/poller.pid"
CHECKING_FILE="$CACHE_DIR/checking"
COMPLETE_FILE="$CACHE_DIR/complete"
REFRESH_COMPLETE_FILE="$CACHE_DIR/refresh-complete"
PROCESS_START_TIME=''
PROCESS_RECORD_TEMP=''
COMPLETE_TEMP=''
COMPLETE_CANDIDATE_TOKEN=''
CYCLE_CACHE_DIR=''
CYCLE_BACKUP_DIR=''
CYCLE_PROMOTION_ACTIVE=0

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

resolve_timeout_command() {
	TIMEOUT_COMMAND=$(type -P timeout 2>/dev/null) && return 0
	TIMEOUT_COMMAND=$(type -P gtimeout 2>/dev/null) && return 0
	TIMEOUT_COMMAND=''
	printf '%s\n' \
		"tmux-outdated-packages: neither 'timeout' nor 'gtimeout' is available; install GNU coreutils (brew install coreutils on macOS)." >&2
	return 1
}

run_with_timeout() {
	"$TIMEOUT_COMMAND" "$CHECK_TIMEOUT" "$@"
}

capture_check_output() {
	local name=$1 allowed_status=$2 output status
	shift 2
	if output=$(run_with_timeout "$@" 2>/dev/null); then
		status=0
	else
		status=$?
	fi
	if [ "$status" -ne 0 ]; then
		if [ -n "$allowed_status" ] &&
			[ "$status" -eq "$allowed_status" ] &&
			[ -n "$output" ]; then
			:
		else
			log_debug "$name: Check command failed (exit $status)"
			return "$status"
		fi
	fi
	printf '%s' "$output"
}

write_check_result() {
	local name=$1 count=$2 output=$3
	if [ -z "$CYCLE_CACHE_DIR" ] || [ ! -d "$CYCLE_CACHE_DIR" ]; then
		log_debug "$name: Check cycle staging directory is unavailable"
		return 1
	fi
	if ! printf '%s\n' "$count" > "$CYCLE_CACHE_DIR/$name.count" ||
		! printf '%s\n' "$output" > "$CYCLE_CACHE_DIR/$name.list"; then
		log_debug "$name: Unable to write check result"
		return 1
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

cleanup_complete_temp() {
	if [ -n "$COMPLETE_TEMP" ]; then
		rm -f "$COMPLETE_TEMP"
		COMPLETE_TEMP=''
	fi
}

cleanup_cycle_cache() {
	if [ -n "$CYCLE_CACHE_DIR" ] && [ -d "$CYCLE_CACHE_DIR" ]; then
		rm -rf "$CYCLE_CACHE_DIR"
	fi
	CYCLE_CACHE_DIR=''
	CYCLE_BACKUP_DIR=''
	CYCLE_PROMOTION_ACTIVE=0
}

rollback_cycle_outputs() {
	local backup marker name failed=0
	[ "$CYCLE_PROMOTION_ACTIVE" -eq 1 ] || return 0
	for backup in "$CYCLE_BACKUP_DIR"/*.count "$CYCLE_BACKUP_DIR"/*.list; do
		[ -f "$backup" ] || continue
		name=${backup##*/}
		mv -f "$backup" "$CACHE_DIR/$name" || failed=1
	done
	for marker in "$CYCLE_BACKUP_DIR"/*.missing; do
		[ -f "$marker" ] || continue
		name=${marker##*/}
		rm -f "$CACHE_DIR/${name%.missing}" || failed=1
	done
	CYCLE_PROMOTION_ACTIVE=0
	return "$failed"
}

cleanup_active_cycle() {
	local published_token=''
	if [ "$CYCLE_PROMOTION_ACTIVE" -eq 1 ]; then
		if [ -n "$COMPLETE_CANDIDATE_TOKEN" ] && [ -f "$COMPLETE_FILE" ]; then
			IFS= read -r published_token < "$COMPLETE_FILE" || true
		fi
		if [ "$published_token" = "$COMPLETE_CANDIDATE_TOKEN" ] &&
			[ -n "$published_token" ]; then
			CYCLE_PROMOTION_ACTIVE=0
		elif ! rollback_cycle_outputs; then
			log_debug "Unable to restore the previous completed generation"
		fi
	fi
	COMPLETE_CANDIDATE_TOKEN=''
	cleanup_cycle_cache
}

prepare_cycle_cache() {
	cleanup_active_cycle
	CYCLE_CACHE_DIR=$(mktemp -d "$CACHE_DIR/.cycle.$$.XXXXXX") || return 1
	CYCLE_BACKUP_DIR="$CYCLE_CACHE_DIR/.backup"
	if ! mkdir "$CYCLE_BACKUP_DIR"; then
		cleanup_cycle_cache
		return 1
	fi
}

backup_cycle_outputs() {
	local staged name live
	for staged in "$CYCLE_CACHE_DIR"/*.count "$CYCLE_CACHE_DIR"/*.list; do
		[ -f "$staged" ] || continue
		name=${staged##*/}
		live="$CACHE_DIR/$name"
		if [ -e "$live" ]; then
			cp -p "$live" "$CYCLE_BACKUP_DIR/$name" || return 1
		else
			: > "$CYCLE_BACKUP_DIR/$name.missing" || return 1
		fi
	done
}

promote_cycle_outputs() {
	local staged name
	CYCLE_PROMOTION_ACTIVE=1
	for staged in "$CYCLE_CACHE_DIR"/*.count "$CYCLE_CACHE_DIR"/*.list; do
		[ -f "$staged" ] || continue
		name=${staged##*/}
		mv -f "$staged" "$CACHE_DIR/$name" || return 1
	done
}

publish_complete() {
	local next_generation token
	if [ -z "$PROCESS_START_TIME" ]; then
		PROCESS_START_TIME=$(process_start_time "$$") || return 1
	fi
	next_generation=$((COMPLETE_GENERATION + 1))
	token="$COMPLETE_PROTOCOL_VERSION:$$:${PROCESS_START_TIME}:${next_generation}"
	COMPLETE_CANDIDATE_TOKEN=$token
	COMPLETE_TEMP="$CACHE_DIR/.complete.$$.${next_generation}.tmp"
	if ! printf '%s\n' "$token" > "$COMPLETE_TEMP"; then
		cleanup_complete_temp
		COMPLETE_CANDIDATE_TOKEN=''
		return 1
	fi
	if ! mv -f "$COMPLETE_TEMP" "$COMPLETE_FILE"; then
		cleanup_complete_temp
		COMPLETE_CANDIDATE_TOKEN=''
		return 1
	fi
	COMPLETE_GENERATION=$next_generation
	COMPLETE_TEMP=''
}

commit_cycle_outputs() {
	COMPLETE_CANDIDATE_TOKEN=''
	if ! backup_cycle_outputs; then
		cleanup_cycle_cache
		return 1
	fi
	if ! promote_cycle_outputs; then
		if ! rollback_cycle_outputs; then
			log_debug "Unable to restore cache after promotion failure"
		fi
		cleanup_cycle_cache
		return 1
	fi
	if ! publish_complete; then
		if ! rollback_cycle_outputs; then
			log_debug "Unable to restore cache after completion publication failure"
		fi
		cleanup_cycle_cache
		return 1
	fi
	CYCLE_PROMOTION_ACTIVE=0
	COMPLETE_CANDIDATE_TOKEN=''
	cleanup_cycle_cache
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
	local status="${1:-130}"
	if [ "$(awk 'NR == 1 { print; exit }' "$PID_FILE" 2>/dev/null)" = "$$" ]; then
		rm -f "$PID_FILE"
	fi
	if [ -n "$PROCESS_RECORD_TEMP" ]; then
		rm -f "$PROCESS_RECORD_TEMP"
	fi
	cleanup_active_cycle
	cleanup_complete_temp
	release_lock
	exit "$status"
}

queue_sigusr1() {
	REFRESH_GENERATION=$((REFRESH_GENERATION + 1))
	rm -f "$REFRESH_COMPLETE_FILE"
}

handle_sigusr1() {
	log_debug "Received SIGUSR1, forcing update..."
	queue_sigusr1
}

begin_check_cycle() {
	CYCLE_REFRESH_GENERATION=$REFRESH_GENERATION
	if [ "$CYCLE_REFRESH_GENERATION" -gt "$APPLIED_REFRESH_GENERATION" ] ||
		[ "$RETRY_FAILED_CHECKS" -eq 1 ]; then
		CURRENT_FORCE_UPDATE=1
	else
		CURRENT_FORCE_UPDATE=0
	fi
}

complete_check_cycle() {
	if [ "$CYCLE_REFRESH_GENERATION" -gt "$APPLIED_REFRESH_GENERATION" ]; then
		APPLIED_REFRESH_GENERATION=$CYCLE_REFRESH_GENERATION
		if [ "$REFRESH_GENERATION" -eq "$CYCLE_REFRESH_GENERATION" ]; then
			touch "$REFRESH_COMPLETE_FILE"
			# A signal can arrive between the generation check and publication.
			if [ "$REFRESH_GENERATION" -ne "$CYCLE_REFRESH_GENERATION" ]; then
				rm -f "$REFRESH_COMPLETE_FILE"
			fi
		fi
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
	pid=$(awk 'NR == 1 && /^[0-9]+$/ { print; exit }' "$PID_FILE" 2>/dev/null)
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
		output=$(capture_check_output brew '' brew outdated --verbose) || return
		local count
		count=$(echo "$output" | grep -c '[^[:space:]]' || echo "0")
		local duration=$(($(date +%s) - start))
		write_check_result brew "$count" "$output" || return
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
		output=$(capture_check_output npm 1 npm outdated -g) || return
		local count
		count=$(echo "$output" | tail -n +2 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		write_check_result npm "$count" "$output" || return
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
		output=$(capture_check_output pip '' pip3 list --outdated) || return
		local count
		count=$(echo "$output" | tail -n +3 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		write_check_result pip "$count" "$output" || return
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
		raw_output=$(capture_check_output cargo '' cargo install-update --list) || return
		local output
		output=$(echo "$raw_output" | grep -E "Needs update|Yes[[:space:]]*$")
		local count
		count=$(echo "$output" | grep -c "Yes[[:space:]]*$" || echo "0")
		local duration=$(($(date +%s) - start))
		write_check_result cargo "$count" "$output" || return
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
		output=$(capture_check_output composer '' composer global outdated) || return
		local count
		count=$(echo "$output" | grep -c '^[a-z]' || echo "0")
		local duration=$(($(date +%s) - start))
		write_check_result composer "$count" "$output" || return
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
		output=$(capture_check_output go '' go-global-update -n) || return
		local count
		count=$(echo "$output" | grep -c "outdated" || echo "0")
		local duration=$(($(date +%s) - start))
		write_check_result go "$count" "$output" || return
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
			output=$(capture_check_output apt '' apt list --upgradable) || return
			local count
			count=$(echo "$output" | grep -c "upgradable" || echo "0")
			local duration=$(($(date +%s) - start))
			write_check_result apt "$count" "$output" || return
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
		output=$(capture_check_output dnf '' dnf list --upgrades) || return
		local count
		count=$(echo "$output" | tail -n +2 | wc -l | tr -d ' ')
		local duration=$(($(date +%s) - start))
		write_check_result dnf "$count" "$output" || return
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
		output=$(capture_check_output mise '' mise outdated) || return
		local count=0
		
		if [[ "$output" != *"All tools are up to date"* ]] && [ -n "$output" ]; then
			count=$(echo "$output" | grep -c '[^[:space:]]')
		else
			output=""
		fi
		local duration=$(($(date +%s) - start))
		write_check_result mise "$count" "$output" || return
		log_debug "mise: Found $count outdated packages (took ${duration}s)"
	fi
}

run_checks_parallel() {
	log_debug "--- Starting check cycle ---"
	local cycle_start
	local pid
	local pids=()
	local child_status checks_failed=0
	local sigusr1_wait_status wait_status
	cycle_start=$(date +%s)
	sigusr1_wait_status=$((128 + $(kill -l USR1)))
	if ! prepare_cycle_cache || ! : > "$CHECKING_FILE"; then
		cleanup_active_cycle
		return 1
	fi
	
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
	
	# A trapped refresh signal interrupts wait. Retry only that status so
	# ordinary checker failures are not mistaken for signal interruptions.
	for pid in "${pids[@]}"; do
		child_status=0
		while true; do
			if wait "$pid" 2>/dev/null; then
				break
			else
				wait_status=$?
			fi
			if [ "$wait_status" -eq "$sigusr1_wait_status" ]; then
				continue
			fi
			child_status=$wait_status
			break
		done
		[ "$child_status" -eq 0 ] || checks_failed=1
	done
	if [ "$checks_failed" -ne 0 ]; then
		RETRY_FAILED_CHECKS=1
		log_debug "Check cycle failed; retaining the previous completed generation"
		cleanup_cycle_cache
		rm -f "$CHECKING_FILE"
		return "$CHECK_FAILURE_STATUS"
	fi
	if ! commit_cycle_outputs; then
		log_debug "Unable to publish check cycle completion"
		rm -f "$CHECKING_FILE"
		return 1
	fi
	RETRY_FAILED_CHECKS=0
	rm -f "$CHECKING_FILE"
	
	local cycle_duration=$(($(date +%s) - cycle_start))
	log_debug "--- Check cycle complete (took ${cycle_duration}s) ---"
}

run_check_cycle() {
	local status
	begin_check_cycle
	if run_checks_parallel; then
		complete_check_cycle
		return 0
	else
		status=$?
	fi
	[ "$status" -eq "$CHECK_FAILURE_STATUS" ] && return 0
	return "$status"
}

cleanup() {
	local status="${1:-$?}"
	trap - EXIT INT TERM
	log_debug "=== Poller stopped ==="
	if [ "$(awk 'NR == 1 { print; exit }' "$PID_FILE" 2>/dev/null)" = "$$" ]; then
		rm -f "$PID_FILE"
	fi
	rm -f "$CHECKING_FILE"
	cleanup_active_cycle
	cleanup_complete_temp
	release_lock
	exit "$status"
}

install_runtime_traps() {
	trap 'cleanup $?' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

main() {
	if ! resolve_timeout_command; then
		return 1
	fi
	trap queue_sigusr1 SIGUSR1
	setup

	if ! acquire_lock; then
		log_debug "Poller lock is already held, exiting"
		exit 0
	fi
	trap 'cleanup_startup 130' INT
	trap 'cleanup_startup 143' TERM
	trap handle_sigusr1 SIGUSR1
	if [ "$REFRESH_GENERATION" -gt "$APPLIED_REFRESH_GENERATION" ]; then
		rm -f "$REFRESH_COMPLETE_FILE"
	fi
	
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
	install_runtime_traps
	
	# Initial check
	run_check_cycle || return
	
	# Poll loop
	while true; do
		log_debug "Sleeping for ${WATCH_INTERVAL}s..."
		sleep "$WATCH_INTERVAL"
		run_check_cycle || return
	done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main
fi
