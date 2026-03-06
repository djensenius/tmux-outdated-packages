#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

# Collect outdated managers into arrays
declare -a manager_names=()
declare -a manager_counts=()
declare -a manager_commands=()

check_manager() {
    local name="$1" count_file="$2" command="$3"
    if [ -f "$CACHE_DIR/$count_file" ]; then
        local count
        count=$(cat "$CACHE_DIR/$count_file")
        if [ "$count" -gt 0 ]; then
            manager_names+=("$name")
            manager_counts+=("$count")
            manager_commands+=("$command")
        fi
    fi
}

check_manager "Homebrew"  "brew.count"     "brew upgrade"
check_manager "npm"       "npm.count"      "npm update -g"
check_manager "Cargo"     "cargo.count"    "cargo install-update -a"
check_manager "Composer"  "composer.count"  "composer global update"
check_manager "Go"        "go.count"       "go-global-update"
check_manager "apt"       "apt.count"      "sudo apt upgrade"
check_manager "DNF"       "dnf.count"      "sudo dnf upgrade"
check_manager "Mise"      "mise.count"     "mise upgrade"
check_manager "pip"       "pip.count"      "echo 'Run: pip3 install --upgrade <package> for each package'"

total=${#manager_names[@]}

if [ "$total" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✨ All packages are up to date!${RESET}"
    sleep 2
    exit 0
fi

while true; do
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║              📦 Update Outdated Packages                 ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    for i in $(seq 0 $((total - 1))); do
        local_count="${manager_counts[$i]}"
        echo -e "  ${YELLOW}$((i + 1)))${RESET} ${BOLD}${manager_names[$i]}${RESET} ${DIM}(${local_count} outdated)${RESET}"
        echo -e "     ${DIM}${manager_commands[$i]}${RESET}"
        echo ""
    done

    if [ "$total" -gt 1 ]; then
        echo -e "  ${YELLOW}a)${RESET} ${BOLD}Update all${RESET} ${DIM}(runs each sequentially)${RESET}"
        echo ""
    fi

    echo -e "  ${YELLOW}q)${RESET} ${DIM}Quit${RESET}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -ne "${BOLD}Select an option: ${RESET}"

    read -r choice

    case "$choice" in
        q|Q)
            exit 0
            ;;
        a|A)
            if [ "$total" -gt 1 ]; then
                for i in $(seq 0 $((total - 1))); do
                    echo ""
                    echo -e "${BOLD}${CYAN}▶ Updating ${manager_names[$i]}...${RESET}"
                    echo -e "${DIM}Running: ${manager_commands[$i]}${RESET}"
                    echo ""
                    eval "${manager_commands[$i]}"
                    echo ""
                    echo -e "${GREEN}✓ ${manager_names[$i]} done${RESET}"
                done
                echo ""
                echo -e "${GREEN}${BOLD}✨ All updates complete!${RESET}"
                # Trigger a refresh of the cache
                "$CURRENT_DIR/trigger-refresh.sh" 2>/dev/null
                echo -e "${DIM}Press any key to continue...${RESET}"
                read -r -n 1
            fi
            ;;
        [1-9]*)
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "$total" ]; then
                echo ""
                echo -e "${BOLD}${CYAN}▶ Updating ${manager_names[$idx]}...${RESET}"
                echo -e "${DIM}Running: ${manager_commands[$idx]}${RESET}"
                echo ""
                eval "${manager_commands[$idx]}"
                echo ""
                echo -e "${GREEN}✓ ${manager_names[$idx]} done${RESET}"
                # Trigger a refresh of the cache
                "$CURRENT_DIR/trigger-refresh.sh" 2>/dev/null
                echo -e "${DIM}Press any key to continue...${RESET}"
                read -r -n 1
            else
                echo -e "${RED}Invalid selection${RESET}"
                sleep 1
            fi
            ;;
        *)
            echo -e "${RED}Invalid selection${RESET}"
            sleep 1
            ;;
    esac
done
