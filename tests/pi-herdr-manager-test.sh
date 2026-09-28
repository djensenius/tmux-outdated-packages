#!/usr/bin/env bash
set -eEuo pipefail

report_failure() {
	printf 'pi-herdr-manager-test: failed at line %s (exit %s)\n' "$2" "$1" >&2
	exit "$1"
}
trap 'report_failure "$?" "$LINENO"' ERR

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POLLER="$ROOT_DIR/scripts/poller.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

REAL_NODE=$(command -v node || true)
if [ -z "$REAL_NODE" ]; then
	printf '%s\n' 'pi-herdr-manager-test: real node is required for Pi parser coverage' >&2
	exit 1
fi

export PI_CODING_AGENT_DIR="$TEST_TMP/pi-agent"
export HERDR_CONFIG_DIR="$TEST_TMP/herdr"
mkdir -p \
	"$PI_CODING_AGENT_DIR/npm" \
	"$TEST_TMP/cache" \
	"$TEST_TMP/bin" \
	"$TEST_TMP/herdr/plugins"

cat >"$TEST_TMP/timeout" <<'EOF'
#!/usr/bin/env bash
if [ "${TIMEOUT_MODE:-}" = timeout ]; then
	exit 124
fi
shift
exec "$@"
EOF
chmod +x "$TEST_TMP/timeout"

cat >"$TEST_TMP/bin/pi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$TEST_TMP/bin/npm" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = config ] && [ "${2:-}" = get ] && [ "${3:-}" = prefix ]; then
	printf '\n'
	exit 0
fi
if [ "${1:-}" = outdated ] && [ "${2:-}" = --json ]; then
	case "${NPM_OUTDATED_MODE:-outdated}" in
		outdated)
			printf '%s\n' '{"pi-web-access":{"current":"0.32.0","wanted":"0.33.0","latest":"0.33.0"},"pi-subagents":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0"},"metadata":{"latest":"9.9.9"},"missing-latest":{"current":"1.0.0"}}'
			exit 1
			;;
		empty)
			printf '%s\n' '{}'
			exit 0
			;;
		error)
			printf '%s\n' '{"error":{"code":"ENOTFOUND","summary":"network failed"}}'
			exit 1
			;;
		package-named-error)
			printf '%s\n' '{"error":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0"}}'
			exit 1
			;;
		invalid)
			printf '%s\n' '{not json}'
			exit 1
			;;
	esac
fi
exit 2
EOF

cat >"$TEST_TMP/bin/node" <<EOF
#!/usr/bin/env bash
exec "$REAL_NODE" "\$@"
EOF

cat >"$TEST_TMP/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = plugin ] && [ "${2:-}" = list ]; then
	case "${HERDR_LIST_MODE:-mixed}" in
		mixed)
			printf '%s\n' \
				'- old-plugin (Old Plugin) enabled [github:owner/old-plugin@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]' \
				'- current-plugin (Current Plugin) enabled [github:owner/current-plugin@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb]' \
				'- failing-plugin (Failing Plugin) enabled [github:owner/failing-plugin@dddddddddddddddddddddddddddddddddddddddd]' \
				'- bad-head (Bad Head) enabled [github:owner/bad-head@eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee]' \
				'- not-github (Ignored) enabled [local:not-github@ffffffffffffffffffffffffffffffffffffffff]' \
				'- no-sha (Ignored) enabled [github:owner/no-sha@not-a-sha]'
			;;
		empty)
			:
			;;
		fail)
			exit 1
			;;
	esac
	exit 0
fi
exit 2
EOF

cat >"$TEST_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = ls-remote ] && [ "${3:-}" = HEAD ]; then
	case "$2" in
		https://github.com/owner/old-plugin)
			printf '%s\tHEAD\n' cccccccccccccccccccccccccccccccccccccccc
			;;
		https://github.com/owner/current-plugin)
			printf '%s\tHEAD\n' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
			;;
		https://github.com/owner/bad-head)
			printf '%s\tHEAD\n' not-a-sha
			;;
		https://github.com/owner/failing-plugin)
			exit 1
			;;
		*)
			exit 1
			;;
	esac
	exit 0
fi
exit 2
EOF
chmod +x "$TEST_TMP/bin"/*

PATH="$TEST_TMP/bin:/usr/bin:/bin"
export PATH
# shellcheck source=/dev/null
source "$POLLER"

CACHE_DIR="$TEST_TMP/cache"
LOG_FILE="$CACHE_DIR/poller.log"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
CYCLE_CACHE_DIR="$CACHE_DIR"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
TIMEOUT_COMMAND="$TEST_TMP/timeout"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
DEBUG_MODE=1

reset_cache() {
	rm -f "$CACHE_DIR"/*
	mkdir -p "$CACHE_DIR"
	# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
	CYCLE_CACHE_DIR="$CACHE_DIR"
	LOG_FILE="$CACHE_DIR/poller.log"
}

assert_no_cache_files() {
	local manager=$1
	[ ! -e "$CACHE_DIR/$manager.count" ]
	[ ! -e "$CACHE_DIR/$manager.list" ]
}

reset_cache
check_pi
[ "$(cat "$CACHE_DIR/pi.count")" = 2 ]
grep -q '^pi-web-access 0.32.0 -> 0.33.0$' "$CACHE_DIR/pi.list"
grep -q '^pi-subagents 1.0.0 -> 1.1.0$' "$CACHE_DIR/pi.list"
if grep -q '^metadata\|^missing-latest' "$CACHE_DIR/pi.list"; then
	printf '%s\n' 'Pi parser included incomplete npm JSON entries' >&2
	exit 1
fi

reset_cache
export NPM_OUTDATED_MODE=empty
check_pi
unset NPM_OUTDATED_MODE
[ "$(cat "$CACHE_DIR/pi.count")" = 0 ]
if grep -q '[^[:space:]]' "$CACHE_DIR/pi.list"; then
	printf '%s\n' 'Empty Pi npm output produced a non-empty list' >&2
	exit 1
fi

reset_cache
export NPM_OUTDATED_MODE=error
if check_pi; then
	printf '%s\n' 'Pi npm error JSON was accepted as package data' >&2
	exit 1
fi
unset NPM_OUTDATED_MODE
assert_no_cache_files pi

reset_cache
export NPM_OUTDATED_MODE=invalid
if check_pi; then
	printf '%s\n' 'Malformed Pi npm output was accepted' >&2
	exit 1
fi
unset NPM_OUTDATED_MODE
assert_no_cache_files pi

reset_cache
export NPM_OUTDATED_MODE=package-named-error
check_pi
unset NPM_OUTDATED_MODE
[ "$(cat "$CACHE_DIR/pi.count")" = 1 ] || {
	printf '%s\n' 'An outdated package named "error" was dropped' >&2
	exit 1
}
grep -Fxq 'error 1.0.0 -> 1.1.0' "$CACHE_DIR/pi.list"

reset_cache
mkdir -p "$TEST_TMP/missing-pi-bin"
PATH="$TEST_TMP/missing-pi-bin" check_pi
assert_no_cache_files pi

reset_cache
missing_npm_bin="$TEST_TMP/missing-npm-bin"
mkdir -p "$missing_npm_bin"
cp "$TEST_TMP/bin/pi" "$missing_npm_bin/pi"
cp "$TEST_TMP/bin/node" "$missing_npm_bin/node"
PATH="$missing_npm_bin" check_pi
assert_no_cache_files pi

reset_cache
missing_node_bin="$TEST_TMP/missing-node-bin"
mkdir -p "$missing_node_bin"
cp "$TEST_TMP/bin/pi" "$missing_node_bin/pi"
cp "$TEST_TMP/bin/npm" "$missing_node_bin/npm"
PATH="$missing_node_bin" check_pi
assert_no_cache_files pi

reset_cache
rmdir "$PI_NPM_PREFIX"
check_pi
assert_no_cache_files pi
mkdir -p "$PI_NPM_PREFIX"

reset_cache
check_herdr
[ "$(cat "$CACHE_DIR/herdr.count")" = 1 ]
[ "$(cat "$CACHE_DIR/herdr.list")" = 'owner/old-plugin aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' ]
grep -q 'Skipping owner/failing-plugin because git ls-remote failed' "$LOG_FILE"
grep -q 'Skipping owner/bad-head because git ls-remote returned an unexpected HEAD' "$LOG_FILE"

reset_cache
export HERDR_LIST_MODE=empty
check_herdr
unset HERDR_LIST_MODE
[ "$(cat "$CACHE_DIR/herdr.count")" = 0 ]
if grep -q '[^[:space:]]' "$CACHE_DIR/herdr.list"; then
	printf '%s\n' 'Empty Herdr plugin output produced a non-empty list' >&2
	exit 1
fi

reset_cache
export HERDR_LIST_MODE=fail
if check_herdr; then
	printf '%s\n' 'Herdr plugin list failure was accepted' >&2
	exit 1
fi
unset HERDR_LIST_MODE
assert_no_cache_files herdr

reset_cache
export TIMEOUT_MODE=timeout
if check_herdr; then
	printf '%s\n' 'Herdr timeout was accepted' >&2
	exit 1
fi
unset TIMEOUT_MODE
assert_no_cache_files herdr

reset_cache
mkdir -p "$TEST_TMP/missing-herdr-bin"
PATH="$TEST_TMP/missing-herdr-bin" check_herdr
assert_no_cache_files herdr

reset_cache
missing_git_bin="$TEST_TMP/missing-git-bin"
mkdir -p "$missing_git_bin"
cp "$TEST_TMP/bin/herdr" "$missing_git_bin/herdr"
PATH="$missing_git_bin" check_herdr
assert_no_cache_files herdr

update_cache="$TEST_TMP/update-cache"
update_bin="$TEST_TMP/update-bin"
update_log="$TEST_TMP/update.log"
mkdir -p "$update_cache" "$update_bin"
cat >"$update_bin/herdr" <<'EOF'
#!/usr/bin/env bash
printf 'herdr %s\n' "$*" >>"$UPDATE_LOG"
cat >/dev/null
case "$3" in
	owner/fail-plugin) exit 1 ;;
esac
EOF
chmod +x "$update_bin/herdr"
PATH="$update_bin:/usr/bin:/bin"
export UPDATE_LOG="$update_log"
printf '%s\n' \
	'owner/old-plugin aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' \
	'bad;name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' \
	'../escape aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' \
	'owner/.. aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' \
	'-flag/repo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' \
	'owner/fail-plugin dddddddddddddddddddddddddddddddddddddddd -> eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' \
	'owner/new-plugin ffffffffffffffffffffffffffffffffffffffff -> 1111111111111111111111111111111111111111' \
	>"$update_cache/herdr.list"
# shellcheck disable=SC2034 # Consumed by herdr_update_outdated_plugins extracted below.
BOLD=''
# shellcheck disable=SC2034 # Consumed by herdr_update_outdated_plugins extracted below.
RESET=''
CACHE_DIR="$update_cache"
# shellcheck disable=SC1090
source <(sed -n '/^herdr_update_outdated_plugins()/,/^}/p' "$ROOT_DIR/scripts/update-packages.sh")
if herdr_update_outdated_plugins; then
	printf '%s\n' 'Herdr update helper ignored a failed plugin install' >&2
	exit 1
fi
grep -q '^herdr plugin install owner/old-plugin --yes$' "$update_log"
grep -q '^herdr plugin install owner/fail-plugin --yes$' "$update_log"
grep -q '^herdr plugin install owner/new-plugin --yes$' "$update_log"
if grep -q -e 'bad;name' -e 'install \.\./escape' -e 'install owner/\.\. ' -e 'install -flag' "$update_log"; then
	printf '%s\n' 'Herdr update helper installed an invalid plugin name' >&2
	exit 1
fi

printf '%s\n' 'Pi and Herdr manager checks passed'
