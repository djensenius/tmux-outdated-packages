#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load shared icons
# shellcheck disable=SC1091
source "$CURRENT_DIR/icons.sh"

# ANSI colour codes
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
RESET='\033[0m'

# Build a temporary file with the content
TMPFILE=$(mktemp)

# Header
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}" > "$TMPFILE"
echo -e "${BOLD}${CYAN}║${RESET}                    📦 ${BOLD}Outdated Packages${RESET}                  ${BOLD}${CYAN}║${RESET}" >> "$TMPFILE"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}" >> "$TMPFILE"
echo "" >> "$TMPFILE"

has_outdated=false
is_loading=false

# Check if we're currently checking for updates
if [ -f "$CACHE_DIR/checking" ]; then
    is_loading=true
    echo -e "${YELLOW}${BOLD}⏳ Checking for outdated packages...${RESET}" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    echo -e "${DIM}This may take a few minutes. The display will update when complete.${RESET}" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
fi

# Helper to render a package manager section
render_section() {
    local icon="$1" name="$2" count_file="$3" list_file="$4"
    local check_cmd="$5" update_cmd="$6" colour="$7"

    if [ -f "$CACHE_DIR/$count_file" ]; then
        local count
        count=$(cat "$CACHE_DIR/$count_file")
        if [ "$count" -gt 0 ]; then
            has_outdated=true
            {
                echo -e "${colour}${BOLD}${icon} ${name}${RESET} ${YELLOW}(${count} outdated)${RESET}"
                echo -e "${DIM}Check:  ${check_cmd}${RESET}"
                echo -e "${DIM}Update: ${update_cmd}${RESET}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                if [ -f "$CACHE_DIR/$list_file" ]; then
                    cat "$CACHE_DIR/$list_file"
                else
                    echo -e "${DIM}Loading...${RESET}"
                fi
                echo ""
            } >> "$TMPFILE"
        fi
    fi
}

render_section "$BREW_ICON"     "Homebrew" "brew.count"     "brew.list"     "brew outdated --verbose"    "brew upgrade"          "$GREEN"
render_section "$NPM_ICON"      "npm global" "npm.count"    "npm.list"      "npm outdated -g"            "npm update -g"         "$RED"
render_section "$CARGO_ICON"    "Cargo"    "cargo.count"    "cargo.list"    "cargo install-update --list" "cargo install-update -a" "$YELLOW"
render_section "$COMPOSER_ICON" "Composer" "composer.count" "composer.list" "composer global outdated"    "composer global update" "$MAGENTA"
render_section "$GO_ICON"       "Go"       "go.count"       "go.list"       "go-global-update -n"        "go-global-update"      "$CYAN"
render_section "$APT_ICON"      "Apt"      "apt.count"      "apt.list"      "apt list --upgradable"      "sudo apt upgrade"      "$GREEN"
render_section "$DNF_ICON"      "DNF"      "dnf.count"      "dnf.list"      "dnf list --upgrades"        "sudo dnf upgrade"      "$BLUE"
render_section "$MISE_ICON"     "Mise"     "mise.count"     "mise.list"     "mise outdated"              "mise upgrade"          "$MAGENTA"
render_section "$PIP_ICON"      "pip"      "pip.count"      "pip.list"      "pip3 list --outdated"       "pip3 install --upgrade <package>" "$BLUE"

if [ "$has_outdated" = false ] && [ "$is_loading" = false ]; then
    echo -e "${GREEN}${BOLD}✨ All packages are up to date!${RESET}" >> "$TMPFILE"
fi

{
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${DIM}Press q or ESC to close  |  Use ↑↓ or j/k to scroll${RESET}"
} >> "$TMPFILE"

# Show in tmux popup with less
tmux display-popup -E -w 90% -h 90% "less -R $TMPFILE; rm -f $TMPFILE"
