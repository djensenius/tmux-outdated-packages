#!/usr/bin/env bash

# Shared icon definitions for all scripts
# These are used in both the status bar and the popup

# Icons using nerdfonts - using printf to ensure proper encoding
export BREW_ICON
BREW_ICON=$(printf '\ue7fd')  # Homebrew nerdfonts icon (nf-dev-homebrew)
export NPM_ICON
NPM_ICON=$(printf '\ue71e')   # Nerdfonts npm icon
export PIP_ICON
PIP_ICON=$(printf '\ue73c')   # Python icon
export CARGO_ICON
CARGO_ICON=$(printf '\ue7a8') # Rust icon
export COMPOSER_ICON
COMPOSER_ICON=$(printf '\ue608') # PHP icon
export GO_ICON
GO_ICON=$(printf '\ue626')    # Go gopher
export APT_ICON
APT_ICON=$(printf '\uf306')   # Debian icon
export DNF_ICON
DNF_ICON=$(printf '\uf30d')   # Fedora icon
export MISE_ICON
MISE_ICON=$(printf '\uf0ad')  # Wrench icon for mise
export PI_ICON
PI_ICON=$(printf '\uf315')    # Raspberry Pi icon
export HERDR_ICON
HERDR_ICON=$(printf '\uf0c0') # Users icon for Herdr plugins

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
# export PI_ICON="🥧"
# export HERDR_ICON="🐑"
