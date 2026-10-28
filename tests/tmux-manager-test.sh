#!/usr/bin/env bash
set -eEuo pipefail

report_failure() {
	printf 'tmux-manager-test: failed at line %s (exit %s)\n' "$2" "$1" >&2
	exit "$1"
}
trap 'report_failure "$?" "$LINENO"' ERR

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export HOME="$TEST_TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export TMPDIR="$TEST_TMP/tmp"
export TMUX_PLUGIN_MANAGER_PATH="$TEST_TMP/tmux plugins"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME" "$TMPDIR" "$TMUX_PLUGIN_MANAGER_PATH" "$TEST_TMP/bin"

cat > "$TEST_TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = show-environment ] && [ -n "${TMUX_TEST_SERVER_PATH:-}" ]; then
	printf 'TMUX_PLUGIN_MANAGER_PATH=%s\n' "$TMUX_TEST_SERVER_PATH"
fi
EOF
printf '%s\n' '#!/bin/sh' 'exit 0' > "$TEST_TMP/bin/clear"
chmod +x "$TEST_TMP/bin/tmux" "$TEST_TMP/bin/clear"
export PATH="$TEST_TMP/bin:$PATH"

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/poller.sh"

export TMUX_TEST_SERVER_PATH="$TEST_TMP/server plugins"
[ "$(tmux_plugin_directory)" = "$TMUX_PLUGIN_MANAGER_PATH" ]
[ "$(TMUX_PLUGIN_MANAGER_PATH='' tmux_plugin_directory)" = "$TMUX_TEST_SERVER_PATH" ]
unset TMUX_TEST_SERVER_PATH
mkdir -p "$XDG_CONFIG_HOME/tmux/plugins" "$HOME/.tmux/plugins"
[ "$(TMUX_PLUGIN_MANAGER_PATH='' tmux_plugin_directory)" = "$XDG_CONFIG_HOME/tmux/plugins" ]
rmdir "$XDG_CONFIG_HOME/tmux/plugins"
[ "$(TMUX_PLUGIN_MANAGER_PATH='' tmux_plugin_directory)" = "$HOME/.tmux/plugins" ]
[ "$(TMUX_PLUGIN_MANAGER_PATH=\~/plugins tmux_plugin_directory)" = "$HOME/plugins" ]

remote="$TEST_TMP/remote.git"
seed="$TEST_TMP/seed"
git init --quiet --bare --initial-branch=main "$remote"
git init --quiet --initial-branch=main "$seed"
printf 'initial\n' > "$seed/plugin.tmux"
git -C "$seed" add plugin.tmux
git -C "$seed" commit --quiet -m initial
git -C "$seed" remote add origin "$remote"
git -C "$seed" push --quiet --set-upstream origin main
initial=$(git -C "$seed" rev-parse HEAD)

for plugin in old dirty pinned diverged no-upstream; do
	git clone --quiet "$remote" "$TMUX_PLUGIN_MANAGER_PATH/$plugin"
done
git clone --quiet "$remote" "$TEST_TMP/outside"
ln -s "$TEST_TMP/outside" "$TMUX_PLUGIN_MANAGER_PATH/symlink"
mkdir "$TMUX_PLUGIN_MANAGER_PATH/not-git"
git -C "$TMUX_PLUGIN_MANAGER_PATH/pinned" switch --quiet --detach
git -C "$TMUX_PLUGIN_MANAGER_PATH/no-upstream" branch --unset-upstream
printf 'local edit\n' >> "$TMUX_PLUGIN_MANAGER_PATH/dirty/plugin.tmux"
printf 'local commit\n' > "$TMUX_PLUGIN_MANAGER_PATH/diverged/local.txt"
git -C "$TMUX_PLUGIN_MANAGER_PATH/diverged" add local.txt
git -C "$TMUX_PLUGIN_MANAGER_PATH/diverged" commit --quiet -m local
diverged=$(git -C "$TMUX_PLUGIN_MANAGER_PATH/diverged" rev-parse HEAD)

printf 'upstream update\n' >> "$seed/plugin.tmux"
git -C "$seed" commit --quiet -am update
git -C "$seed" push --quiet origin main
latest=$(git -C "$seed" rev-parse HEAD)
git clone --quiet "$remote" "$TMUX_PLUGIN_MANAGER_PATH/current"
git clone --quiet "$remote" "$TMUX_PLUGIN_MANAGER_PATH/ahead"
printf 'ahead only\n' > "$TMUX_PLUGIN_MANAGER_PATH/ahead/local.txt"
git -C "$TMUX_PLUGIN_MANAGER_PATH/ahead" add local.txt
git -C "$TMUX_PLUGIN_MANAGER_PATH/ahead" commit --quiet -m ahead
ahead=$(git -C "$TMUX_PLUGIN_MANAGER_PATH/ahead" rev-parse HEAD)

git -C "$seed" switch --quiet -c release "$initial"
printf 'release\n' > "$seed/release.txt"
git -C "$seed" add release.txt
git -C "$seed" commit --quiet -m release
git -C "$seed" push --quiet origin release
git clone --quiet --branch release "$remote" "$TMUX_PLUGIN_MANAGER_PATH/release"
release_initial=$(git -C "$seed" rev-parse HEAD)
printf 'release update\n' >> "$seed/release.txt"
git -C "$seed" commit --quiet -am release-update
git -C "$seed" push --quiet origin release
release_latest=$(git -C "$seed" rev-parse HEAD)

CYCLE_CACHE_DIR="$TEST_TMP/stage"
LOG_FILE="$CACHE_DIR/poller.log"
# shellcheck disable=SC2034 # Consumed by the sourced poller functions.
DEBUG_MODE=1
mkdir -p "$CACHE_DIR" "$CYCLE_CACHE_DIR"
resolve_timeout_command
check_tmux
[ "$(cat "$CYCLE_CACHE_DIR/tmux.count")" = 4 ]
grep -Fxq "old $initial -> $latest" "$CYCLE_CACHE_DIR/tmux.list"
grep -Fxq "dirty $initial -> $latest" "$CYCLE_CACHE_DIR/tmux.list"
grep -Fxq "diverged $diverged -> $latest" "$CYCLE_CACHE_DIR/tmux.list"
grep -Fxq "release $release_initial -> $release_latest" "$CYCLE_CACHE_DIR/tmux.list"
[ ! -e "$CACHE_DIR/tmux.count" ]
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/old" rev-parse HEAD)" = "$initial" ]
cp "$CYCLE_CACHE_DIR/tmux.list" "$TEST_TMP/detected.list"
printf '%s\n' 'tmux detection: tracked branches, ahead-only, pinned, and symlink cases passed'

rm -f "$CYCLE_CACHE_DIR/tmux.count" "$CYCLE_CACHE_DIR/tmux.list"
printf '7\n' > "$CACHE_DIR/tmux.count"
printf 'previous result\n' > "$CACHE_DIR/tmux.list"
git -C "$TMUX_PLUGIN_MANAGER_PATH/old" remote set-url origin "$TEST_TMP/missing.git"
if CURRENT_FORCE_UPDATE=1 check_tmux; then
	printf '%s\n' 'A failed tmux fetch was accepted' >&2
	exit 1
fi
git -C "$TMUX_PLUGIN_MANAGER_PATH/old" remote set-url origin "$remote"
[ "$(cat "$CACHE_DIR/tmux.count")" = 7 ]
[ "$(cat "$CACHE_DIR/tmux.list")" = 'previous result' ]
[ ! -e "$CYCLE_CACHE_DIR/tmux.count" ]
[ ! -e "$CYCLE_CACHE_DIR/tmux.list" ]
grep -q 'tmux: Check command failed' "$LOG_FILE"
mkdir "$TEST_TMP/empty-plugins"
TMUX_PLUGIN_MANAGER_PATH="$TEST_TMP/empty-plugins" CURRENT_FORCE_UPDATE=1 check_tmux
[ "$(cat "$CYCLE_CACHE_DIR/tmux.count")" = 0 ]
[ -z "$(tr -d '[:space:]' < "$CYCLE_CACHE_DIR/tmux.list")" ]
printf '%s\n' 'tmux cache: failed fetch preserves published results; empty directory clears counts'

cp "$TEST_TMP/detected.list" "$CACHE_DIR/tmux.list"
printf '%s\n' \
	"../outside $initial -> $latest" \
	"symlink $initial -> $latest" \
	"pinned $initial -> $latest" \
	"bad;name $initial -> $latest" \
	". $initial -> $latest" >> "$CACHE_DIR/tmux.list"
if tmux_update_outdated_plugins > "$TEST_TMP/update.out" 2>&1; then
	printf '%s\n' 'tmux updates ignored unsafe, dirty, or divergent plugins' >&2
	exit 1
fi
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/old" rev-parse HEAD)" = "$latest" ]
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/release" rev-parse HEAD)" = "$release_latest" ]
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/dirty" rev-parse HEAD)" = "$initial" ]
grep -q 'local edit' "$TMUX_PLUGIN_MANAGER_PATH/dirty/plugin.tmux"
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/diverged" rev-parse HEAD)" = "$diverged" ]
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/ahead" rev-parse HEAD)" = "$ahead" ]
[ "$(git -C "$TMUX_PLUGIN_MANAGER_PATH/pinned" rev-parse HEAD)" = "$initial" ]
[ "$(git -C "$TEST_TMP/outside" rev-parse HEAD)" = "$initial" ]
grep -q 'Skipping dirty: local changes' "$TEST_TMP/update.out"
grep -q 'Skipping invalid tmux plugin name: ../outside' "$TEST_TMP/update.out"
printf 'old %s -> %s\n' "$initial" "$latest" > "$CACHE_DIR/tmux.list"
tmux_update_outdated_plugins > "$TEST_TMP/current-update.out" 2>&1
printf '%s\n' 'tmux updates: fast-forwards succeed; pins, local edits, local commits, and paths are preserved'

printf '1\n' > "$CACHE_DIR/pi.count"
printf '2\n' > "$CACHE_DIR/herdr.count"
printf '3\n' > "$CACHE_DIR/tmux.count"
status_output=$(bash "$ROOT_DIR/scripts/outdated-packages.sh")
[[ "$status_output" == *"$(printf '\u03c0') 1"* ]]
[[ "$status_output" == *'H 2'* ]]
[[ "$status_output" == *"$(printf '\uebc8') 3"* ]]
[ "$(bash "$ROOT_DIR/scripts/counts-only.sh")" = ' 6' ]
rm -f "$CACHE_DIR/pi.count" "$CACHE_DIR/herdr.count"
for script in show-popup.sh update-packages.sh; do
	menu_output=$(printf 'q\n' | bash "$ROOT_DIR/scripts/$script")
	grep -q 'tmux_update_outdated_plugins' <<< "$menu_output"
done
printf '%s\n' 'tmux interfaces: status icons, aggregate counts, popup, and update menu passed'
