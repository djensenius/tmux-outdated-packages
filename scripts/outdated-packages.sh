#!/usr/bin/env bash

# This script just reads the cached results - polling happens in background
CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
RESULT_FILE="$CACHE_DIR/result.txt"

# Icons using nerdfonts
BREW_ICON=""
NPM_ICON=""
PIP_ICON=""
GEM_ICON=""
CARGO_ICON=""
COMPOSER_ICON=""
GO_ICON=""
APT_ICON=""
DNF_ICON=""

format_output() {
	local output=""
	
	# Read individual cache files and format output
	[ -f "$CACHE_DIR/brew.count" ] && {
		local count=$(cat "$CACHE_DIR/brew.count")
		[ "$count" -gt 0 ] && output+=" ${BREW_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/npm.count" ] && {
		local count=$(cat "$CACHE_DIR/npm.count")
		[ "$count" -gt 0 ] && output+=" ${NPM_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/pip.count" ] && {
		local count=$(cat "$CACHE_DIR/pip.count")
		[ "$count" -gt 0 ] && output+=" ${PIP_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/gem.count" ] && {
		local count=$(cat "$CACHE_DIR/gem.count")
		[ "$count" -gt 0 ] && output+=" ${GEM_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/cargo.count" ] && {
		local count=$(cat "$CACHE_DIR/cargo.count")
		[ "$count" -gt 0 ] && output+=" ${CARGO_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/composer.count" ] && {
		local count=$(cat "$CACHE_DIR/composer.count")
		[ "$count" -gt 0 ] && output+=" ${COMPOSER_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/go.count" ] && {
		local count=$(cat "$CACHE_DIR/go.count")
		[ "$count" -gt 0 ] && output+=" ${GO_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/apt.count" ] && {
		local count=$(cat "$CACHE_DIR/apt.count")
		[ "$count" -gt 0 ] && output+=" ${APT_ICON} ${count}"
	}
	
	[ -f "$CACHE_DIR/dnf.count" ] && {
		local count=$(cat "$CACHE_DIR/dnf.count")
		[ "$count" -gt 0 ] && output+=" ${DNF_ICON} ${count}"
	}
	
	echo "$output"
}

main() {
	# Just read and format the cached results
	format_output
}

main
