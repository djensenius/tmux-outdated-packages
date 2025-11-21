#!/usr/bin/env bash

CACHE_DIR="${TMPDIR:-/tmp}/tmux-outdated-packages"
CHECKING_FILE="$CACHE_DIR/checking"

# Spinner frames
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

if [ -f "$CHECKING_FILE" ]; then
    # Get spinner index - use milliseconds by reading epoch time twice
    # This creates faster animation since tmux status updates every second
    EPOCH=$(date +%s)
    # Use last digit of epoch and multiply by a random-ish number for variation
    INDEX=$(( ($EPOCH * 3) % ${#SPINNER[@]} ))
    echo " ${SPINNER[$INDEX]} "
else
    # Not checking, show the actual counts by calling the script
    # This will output nothing if there are no outdated packages
    "$(dirname "$0")/outdated-packages.sh"
fi
