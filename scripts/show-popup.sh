#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load shared icons
# shellcheck disable=SC1091
source "$CURRENT_DIR/icons.sh"

# ANSI colour codes
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

# Read configured keybindings for footer
get_tmux_option() {
    local option=$1 default=$2
    local val
    val=$(tmux show-option -gqv "$option")
    if [ -z "$val" ]; then echo "$default"; else echo "$val"; fi
}

refresh_key=$(get_tmux_option "@outdated_refresh_key" "E")

# Upgrade all outdated pip packages by parsing the cached list
pip_upgrade_all() {
    local list_file="$CACHE_DIR/pip.list"
    if [ ! -f "$list_file" ]; then
        echo "No pip package list found"
        return 1
    fi
    local packages
    packages=$(awk 'NR > 2 { print $1 }' "$list_file")
    if [ -z "$packages" ]; then
        echo "No packages to upgrade"
        return 0
    fi
    echo "$packages" | while IFS= read -r pkg; do
        echo "${BOLD}Upgrading ${pkg}...${RESET}"
        pip3 install --upgrade "$pkg"
    done
}

# Collect outdated managers
declare -a mgr_icons=()
declare -a mgr_names=()
declare -a mgr_counts=()
declare -a mgr_commands=()
declare -a mgr_lists=()
declare -a mgr_colours=()

add_manager() {
    local icon="$1" name="$2" count_file="$3" command="$4" list_file="$5" colour="$6"
    if [ -f "$CACHE_DIR/$count_file" ]; then
        local count
        count=$(cat "$CACHE_DIR/$count_file")
        if [ "$count" -gt 0 ]; then
            mgr_icons+=("$icon")
            mgr_names+=("$name")
            mgr_counts+=("$count")
            mgr_commands+=("$command")
            mgr_lists+=("$list_file")
            mgr_colours+=("$colour")
        fi
    fi
}

add_manager "$BREW_ICON"     "Homebrew"  "brew.count"     "brew upgrade"            "brew.list"     "$GREEN"
add_manager "$NPM_ICON"      "npm"       "npm.count"      "npm update -g"           "npm.list"      "$YELLOW"
add_manager "$CARGO_ICON"    "Cargo"     "cargo.count"    "cargo install-update -a" "cargo.list"    "$YELLOW"
add_manager "$COMPOSER_ICON" "Composer"  "composer.count"  "composer global update" "composer.list" "$MAGENTA"
add_manager "$GO_ICON"       "Go"        "go.count"       "go-global-update"        "go.list"       "$CYAN"
add_manager "$APT_ICON"      "Apt"       "apt.count"      "sudo apt upgrade"        "apt.list"      "$GREEN"
add_manager "$DNF_ICON"      "DNF"       "dnf.count"      "sudo dnf upgrade"        "dnf.list"      "$BLUE"
add_manager "$MISE_ICON"     "Mise"      "mise.count"     "mise upgrade"            "mise.list"     "$MAGENTA"
add_manager "$PIP_ICON"      "pip"       "pip.count"      "pip_upgrade_all"         "pip.list"      "$BLUE"

total=${#mgr_names[@]}
is_loading=false
[ -f "$CACHE_DIR/checking" ] && is_loading=true

draw_screen() {
    clear
    # Header
    echo "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${CYAN}║${RESET}                    📦 ${BOLD}Outdated Packages${RESET}                  ${BOLD}${CYAN}║${RESET}"
    echo "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if [ "$is_loading" = true ]; then
        echo "  ${YELLOW}${BOLD}⏳ Checking for outdated packages...${RESET}"
        echo "  ${DIM}This may take a few minutes.${RESET}"
        echo ""
    fi

    if [ "$total" -eq 0 ] && [ "$is_loading" = false ]; then
        echo "  ${GREEN}${BOLD}✨ All packages are up to date!${RESET}"
        echo ""
    fi

    for i in $(seq 0 $((total - 1))); do
        local colour="${mgr_colours[$i]}"
        echo "  ${YELLOW}$((i + 1)))${RESET} ${colour}${BOLD}${mgr_icons[$i]} ${mgr_names[$i]}${RESET}  ${YELLOW}${mgr_counts[$i]} outdated${RESET}"
        echo "  ${DIM}   └─ ${mgr_commands[$i]}${RESET}"
        if [ -f "$CACHE_DIR/${mgr_lists[$i]}" ]; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                echo "  ${DIM}      ${line}${RESET}"
            done < "$CACHE_DIR/${mgr_lists[$i]}"
        fi
        echo ""
    done

    # Actions
    if [ "$total" -gt 0 ]; then
        echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo ""
        if [ "$total" -gt 1 ]; then
            echo "  ${YELLOW}a)${RESET} ${BOLD}Update all${RESET} ${DIM}(runs each sequentially)${RESET}"
        fi
        echo "  ${YELLOW}q)${RESET} ${DIM}Quit${RESET}"
        echo ""
    fi

    # Footer
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    local hints=""
    [ -n "$refresh_key" ] && hints="${YELLOW}prefix+${refresh_key}${RESET} refresh"
    echo "${DIM}Enter a number to update │ q to quit${RESET}  ${hints}"
}

# If nothing to show and not loading, just display and exit
if [ "$total" -eq 0 ]; then
    draw_screen
    echo ""
    read -r -n 1 -s -p ""
    exit 0
fi

# Interactive loop
while true; do
    draw_screen
    echo ""
    echo -n "  ${BOLD}❯ ${RESET}"
    read -r choice

    case "$choice" in
        q|Q|"")
            exit 0
            ;;
        a|A)
            if [ "$total" -gt 1 ]; then
                echo ""
                for i in $(seq 0 $((total - 1))); do
                    echo ""
                    echo "  ${BOLD}${CYAN}▶ Updating ${mgr_names[$i]}...${RESET}"
                    echo "  ${DIM}Running: ${mgr_commands[$i]}${RESET}"
                    echo ""
                    eval "${mgr_commands[$i]}"
                    echo ""
                    echo "  ${GREEN}✓ ${mgr_names[$i]} done${RESET}"
                done
                echo ""
                echo "  ${GREEN}${BOLD}✨ All updates complete!${RESET}"
                "$CURRENT_DIR/trigger-refresh.sh" 2>/dev/null
                echo ""
                echo "  ${DIM}Press any key to continue...${RESET}"
                read -r -n 1 -s
            fi
            ;;
        [1-9]*)
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "$total" ]; then
                echo ""
                echo "  ${BOLD}${CYAN}▶ Updating ${mgr_names[$idx]}...${RESET}"
                echo "  ${DIM}Running: ${mgr_commands[$idx]}${RESET}"
                echo ""
                eval "${mgr_commands[$idx]}"
                echo ""
                echo "  ${GREEN}✓ ${mgr_names[$idx]} done${RESET}"
                "$CURRENT_DIR/trigger-refresh.sh" 2>/dev/null
                echo ""
                echo "  ${DIM}Press any key to continue...${RESET}"
                read -r -n 1 -s
            else
                echo "  ${YELLOW}Invalid selection${RESET}"
                sleep 1
            fi
            ;;
        *)
            echo "  ${YELLOW}Invalid selection${RESET}"
            sleep 1
            ;;
    esac
done
