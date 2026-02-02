#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load shared icons
# shellcheck disable=SC1091
source "$CURRENT_DIR/icons.sh"

# Build a temporary file with the content
TMPFILE=$(mktemp)

# Header
cat > "$TMPFILE" << 'HEADER'
╔══════════════════════════════════════════════════════════╗
║                    📦 Outdated Packages                  ║
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
        {
            echo "${BREW_ICON} Homebrew ($count outdated)"
            echo "Check: brew outdated --verbose"
            echo "Update: brew upgrade"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/brew.list" ]; then
                cat "$CACHE_DIR/brew.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check npm
if [ -f "$CACHE_DIR/npm.count" ]; then
    count=$(cat "$CACHE_DIR/npm.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${NPM_ICON} npm global ($count outdated)"
            echo "Check: npm outdated -g"
            echo "Update: npm update -g"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/npm.list" ]; then
                cat "$CACHE_DIR/npm.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check cargo
if [ -f "$CACHE_DIR/cargo.count" ]; then
    count=$(cat "$CACHE_DIR/cargo.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${CARGO_ICON} Cargo ($count outdated)"
            echo "Check: cargo install-update --list"
            echo "Update: cargo install-update -a"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/cargo.list" ]; then
                cat "$CACHE_DIR/cargo.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check composer
if [ -f "$CACHE_DIR/composer.count" ]; then
    count=$(cat "$CACHE_DIR/composer.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${COMPOSER_ICON} Composer ($count outdated)"
            echo "Check: composer global outdated"
            echo "Update: composer global update"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/composer.list" ]; then
                cat "$CACHE_DIR/composer.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check go
if [ -f "$CACHE_DIR/go.count" ]; then
    count=$(cat "$CACHE_DIR/go.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${GO_ICON} Go ($count outdated)"
            echo "Check: go-global-update -n"
            echo "Update: go-global-update"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/go.list" ]; then
                cat "$CACHE_DIR/go.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check apt
if [ -f "$CACHE_DIR/apt.count" ]; then
    count=$(cat "$CACHE_DIR/apt.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${APT_ICON} Apt ($count outdated)"
            echo "Check: apt list --upgradable"
            echo "Update: sudo apt upgrade"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/apt.list" ]; then
                cat "$CACHE_DIR/apt.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check dnf
if [ -f "$CACHE_DIR/dnf.count" ]; then
    count=$(cat "$CACHE_DIR/dnf.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${DNF_ICON} DNF ($count outdated)"
            echo "Check: dnf list --upgrades"
            echo "Update: sudo dnf upgrade"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/dnf.list" ]; then
                cat "$CACHE_DIR/dnf.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check mise
if [ -f "$CACHE_DIR/mise.count" ]; then
    count=$(cat "$CACHE_DIR/mise.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${MISE_ICON} Mise ($count outdated)"
            echo "Check: mise outdated"
            echo "Update: mise upgrade"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/mise.list" ]; then
                cat "$CACHE_DIR/mise.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

# Check pip
if [ -f "$CACHE_DIR/pip.count" ]; then
    count=$(cat "$CACHE_DIR/pip.count")
    if [ "$count" -gt 0 ]; then
        has_outdated=true
        {
            echo "${PIP_ICON} pip ($count outdated)"
            echo "Check: pip3 list --outdated"
            echo "Update: pip3 install --upgrade <package>"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -f "$CACHE_DIR/pip.list" ]; then
                cat "$CACHE_DIR/pip.list"
            else
                echo "Loading..."
            fi
            echo ""
        } >> "$TMPFILE"
    fi
fi

if [ "$has_outdated" = false ] && [ "$is_loading" = false ]; then
    echo "✨ All packages are up to date!" >> "$TMPFILE"
fi

{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Press q or ESC to close  |  Use ↑↓ or j/k to scroll"
} >> "$TMPFILE"

# Show in tmux popup with less
tmux display-popup -E -w 90% -h 90% "less -r $TMPFILE; rm -f $TMPFILE"
