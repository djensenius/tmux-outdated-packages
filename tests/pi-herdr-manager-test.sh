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

export PI_CODING_AGENT_DIR="$TEST_TMP/pi-agent"
mkdir -p "$PI_CODING_AGENT_DIR/npm" "$TEST_TMP/cache" "$TEST_TMP/bin" "$TEST_TMP/herdr/plugins"

cat >"$TEST_TMP/timeout" <<'EOF'
#!/usr/bin/env bash
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
	printf '%s\n' '{"pi-web-access":{"current":"0.32.0","wanted":"0.33.0","latest":"0.33.0"},"pi-subagents":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0"}}'
	exit 1
fi
exit 2
EOF

cat >"$TEST_TMP/bin/node" <<'EOF'
#!/usr/bin/env bash
script=${2:-}
cat >/dev/null
case "$script" in
	*'Object.keys'*)
		printf '%s\n' 2
		;;
	*)
		printf '%s\n' \
			'pi-web-access 0.32.0 -> 0.33.0' \
			'pi-subagents 1.0.0 -> 1.1.0'
		;;
esac
EOF

cat >"$TEST_TMP/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = plugin ] && [ "${2:-}" = list ]; then
	printf '%s\n' \
		'- old-plugin (Old Plugin) enabled [github:owner/old-plugin@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]' \
		'- current-plugin (Current Plugin) enabled [github:owner/current-plugin@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb]'
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
export HERDR_CONFIG_DIR="$TEST_TMP/herdr"
# shellcheck source=/dev/null
source "$POLLER"

CACHE_DIR="$TEST_TMP/cache"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
LOG_FILE="$CACHE_DIR/poller.log"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
CYCLE_CACHE_DIR="$CACHE_DIR"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
TIMEOUT_COMMAND="$TEST_TMP/timeout"
# shellcheck disable=SC2034 # Consumed by functions sourced from poller.sh.
DEBUG_MODE=1

check_pi
[ "$(cat "$CACHE_DIR/pi.count")" = 2 ]
grep -q '^pi-web-access 0.32.0 -> 0.33.0$' "$CACHE_DIR/pi.list"
grep -q '^pi-subagents 1.0.0 -> 1.1.0$' "$CACHE_DIR/pi.list"

check_herdr
[ "$(cat "$CACHE_DIR/herdr.count")" = 1 ]
[ "$(cat "$CACHE_DIR/herdr.list")" = 'owner/old-plugin aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -> cccccccccccccccccccccccccccccccccccccccc' ]

printf '%s\n' 'Pi and Herdr manager checks passed'
