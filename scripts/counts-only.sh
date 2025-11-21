#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"

# Read counts from cache
brew_count=0
npm_count=0
gem_count=0
pipx_count=0

[ -f "$CACHE_DIR/brew.count" ] && brew_count=$(cat "$CACHE_DIR/brew.count" 2>/dev/null || echo 0)
[ -f "$CACHE_DIR/npm.count" ] && npm_count=$(cat "$CACHE_DIR/npm.count" 2>/dev/null || echo 0)
[ -f "$CACHE_DIR/gem.count" ] && gem_count=$(cat "$CACHE_DIR/gem.count" 2>/dev/null || echo 0)
[ -f "$CACHE_DIR/pipx.count" ] && pipx_count=$(cat "$CACHE_DIR/pipx.count" 2>/dev/null || echo 0)

total=$((brew_count + npm_count + gem_count + pipx_count))

if [ $total -gt 0 ]; then
    echo " ${total}"
fi
