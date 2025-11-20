#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load shared icons
source "$CURRENT_DIR/icons.sh"

# Build a temporary file with the content
TMPFILE=$(mktemp)

# Header
cat > "$TMPFILE" << 'HEADER'
╔══════════════════════════════════════════════════════════╗
║           📦 Outdated Packages                          ║
╚══════════════════════════════════════════════════════════╝

HEADER

has_outdated=false
is_loading=false

# Check if we're currently checking for updates
if [ -f "$CACHE_DIR/checking" ]; then
    is_loading=true
    cat >> "$TMPFILE" << 'LOADING'
⏳ Checking for outdated packages...

This may take a few minutes. The display will update when complete.

LOADING
fi

# Show cached counts and package lists from cache files
# Check Homebrew
if [ -f "$CACHE_DIR/brew.count" ]; then
    count=$(cat "$CACHE_DIR/brew.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        echo "${BREW_ICON} Homebrew ($count outdated)" >> "$TMPFILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
        if [ -f "$CACHE_DIR/brew.list" ]; then
            cat "$CACHE_DIR/brew.list" >> "$TMPFILE"
        else
            echo "Loading..." >> "$TMPFILE"
        fi
        echo "" >> "$TMPFILE"
    fi
fi

# Check npm
if [ -f "$CACHE_DIR/npm.count" ]; then
    count=$(cat "$CACHE_DIR/npm.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        echo "${NPM_ICON} npm global ($count outdated)" >> "$TMPFILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
        if [ -f "$CACHE_DIR/npm.list" ]; then
            cat "$CACHE_DIR/npm.list" >> "$TMPFILE"
        else
            echo "Loading..." >> "$TMPFILE"
        fi
        echo "" >> "$TMPFILE"
    fi
fi

# Check gems
if [ -f "$CACHE_DIR/gem.count" ]; then
    count=$(cat "$CACHE_DIR/gem.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        echo "${GEM_ICON} Ruby gems ($count outdated)" >> "$TMPFILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
        if [ -f "$CACHE_DIR/gem.list" ]; then
            cat "$CACHE_DIR/gem.list" >> "$TMPFILE"
        else
            echo "Loading..." >> "$TMPFILE"
        fi
        echo "" >> "$TMPFILE"
    fi
fi

# Check pip
if [ -f "$CACHE_DIR/pip.count" ]; then
    count=$(cat "$CACHE_DIR/pip.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        echo "${PIP_ICON} pip ($count outdated)" >> "$TMPFILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
        if [ -f "$CACHE_DIR/pip.list" ]; then
            cat "$CACHE_DIR/pip.list" >> "$TMPFILE"
        else
            echo "Loading..." >> "$TMPFILE"
        fi
        echo "" >> "$TMPFILE"
    fi
fi

if [ "$has_outdated" = false ] && [ "$is_loading" = false ]; then
    echo "✨ All packages are up to date!" >> "$TMPFILE"
fi

echo "" >> "$TMPFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TMPFILE"
echo "Press q or ESC to close  |  Use ↑↓ or j/k to scroll" >> "$TMPFILE"

# Show in tmux popup with less
tmux display-popup -E -w 90% -h 90% "less -r $TMPFILE; rm -f $TMPFILE"
