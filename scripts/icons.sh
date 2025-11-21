#!/usr/bin/env bash

# Shared icon definitions for all scripts
# These are used in both the status bar and the popup

# Icons using nerdfonts - using printf to ensure proper encoding
export BREW_ICON=$(printf '\ue7fd')  # Homebrew nerdfonts icon (nf-dev-homebrew)
export NPM_ICON=$(printf '\ue71e')   # Nerdfonts npm icon
export PIP_ICON=$(printf '\uf487')   # Python icon
export CARGO_ICON=$(printf '\ue7a8') # Rust icon
export COMPOSER_ICON=$(printf '\ue608') # PHP icon
export GO_ICON=$(printf '\ue626')    # Go gopher
export APT_ICON=$(printf '\uf306')   # Debian icon
export DNF_ICON=$(printf '\uf30d')   # Fedora icon

# Alternative: Use emojis instead (uncomment to use)
# export BREW_ICON="🍺"
# export NPM_ICON="📦"
# export PIP_ICON="🐍"
# export GEM_ICON="💎"
# export CARGO_ICON="🦀"
# export COMPOSER_ICON="🎼"
# export GO_ICON="🐹"
# export APT_ICON="📦"
# export DNF_ICON="📦"
