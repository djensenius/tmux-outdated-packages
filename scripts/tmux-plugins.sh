#!/usr/bin/env bash

tmux_plugin_directory() {
	local plugin_dir="${TMUX_PLUGIN_MANAGER_PATH:-}" configured
	if [ -z "$plugin_dir" ] && command -v tmux >/dev/null 2>&1; then
		configured=$(tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null) || configured=''
		case "$configured" in
			TMUX_PLUGIN_MANAGER_PATH=*) plugin_dir=${configured#*=} ;;
		esac
	fi
	if [ -z "$plugin_dir" ]; then
		if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins" ]; then
			plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins"
		else
			plugin_dir="$HOME/.tmux/plugins"
		fi
	fi
	case "$plugin_dir" in
		\~/*) plugin_dir="$HOME/${plugin_dir#\~/}" ;;
	esac
	printf '%s\n' "$plugin_dir"
}

tmux_plugin_upstream() {
	local repo=$1 branch upstream remote ref
	[ ! -L "$repo" ] && [ -e "$repo/.git" ] || return 1
	branch=$(git --no-pager -C "$repo" symbolic-ref --quiet HEAD) || return
	upstream=$(git --no-pager -C "$repo" for-each-ref \
		--format='%(upstream:remotename)%09%(upstream:remoteref)' "$branch") || return
	IFS=$'\t' read -r remote ref <<< "$upstream"
	[ -n "$remote" ] && [ "$remote" != . ] && [[ "$ref" == refs/heads/* ]] || return 1
	printf '%s\t%s\n' "$remote" "$ref"
}

tmux_check_plugins() {
	local plugin_dir=$1 repo plugin upstream remote ref installed latest behind
	for repo in "$plugin_dir"/*; do
		[ -d "$repo" ] || continue
		plugin=${repo##*/}
		[[ "$plugin" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
		upstream=$(tmux_plugin_upstream "$repo") || continue
		IFS=$'\t' read -r remote ref <<< "$upstream"
		installed=$(git --no-pager -C "$repo" rev-parse --verify HEAD) || return
		GIT_TERMINAL_PROMPT=0 git --no-pager -C "$repo" fetch --quiet --no-tags -- "$remote" "$ref" || return
		latest=$(git --no-pager -C "$repo" rev-parse --verify FETCH_HEAD) || return
		behind=$(git --no-pager -C "$repo" rev-list --count "HEAD..$latest") || return
		[ "$behind" -gt 0 ] || continue
		printf '%s %s -> %s\n' "$plugin" "$installed" "$latest"
	done
	return 0
}

tmux_update_outdated_plugins() {
	local list_file="$CACHE_DIR/tmux.list" plugin_dir plugin rest repo upstream remote ref status
	local found=0 failed=0
	if [ ! -f "$list_file" ]; then
		echo "No tmux plugin list found"
		return 1
	fi
	plugin_dir=$(tmux_plugin_directory) || return
	while read -r plugin rest; do
		[ -n "$plugin" ] || continue
		found=1
		if [[ ! "$plugin" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
			echo "Skipping invalid tmux plugin name: $plugin"
			failed=1
			continue
		fi
		repo="$plugin_dir/$plugin"
		if ! upstream=$(tmux_plugin_upstream "$repo"); then
			echo "Skipping $plugin: missing, symlinked, pinned, or no tracked remote branch"
			failed=1
			continue
		fi
		if ! status=$(git --no-pager -C "$repo" status --porcelain); then
			failed=1
			continue
		fi
		if [ -n "$status" ]; then
			echo "Skipping $plugin: local changes"
			failed=1
			continue
		fi
		IFS=$'\t' read -r remote ref <<< "$upstream"
		echo "${BOLD:-}Updating ${plugin}...${RESET:-}"
		GIT_TERMINAL_PROMPT=0 git --no-pager -C "$repo" pull \
			--ff-only --no-rebase --no-autostash -- "$remote" "$ref" </dev/null || failed=1
	done < "$list_file"
	if [ "$found" -eq 0 ]; then
		echo "No plugins to update"
	fi
	return "$failed"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	tmux_check_plugins "${1:-$(tmux_plugin_directory)}"
fi
