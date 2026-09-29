#!/bin/zsh -f
# Foreground-only MographJailed snapshot dashboard worker.
# This script is intentionally executed with /bin/zsh -f to avoid inheriting
# interactive Terminal session hooks while retaining reliable EXIT cleanup.

ROOT="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}"
COMMON="$ROOT/scripts/shell/mj-terminal.zsh"
[ -r "$COMMON" ] || { /bin/echo "MJ terminal helper not found: $COMMON" >&2; exit 66; }
source "$COMMON"

local_doctor=""
local_describe=""
local_verify=""
local_storage=""
local_req=""

cleanup_top_files() {
    [ -n "$local_req" ] && /bin/rm -f "$local_req"
    [ -n "$local_doctor" ] && /bin/rm -f "$local_doctor"
    [ -n "$local_describe" ] && /bin/rm -f "$local_describe"
    [ -n "$local_verify" ] && /bin/rm -f "$local_verify"
    [ -n "$local_storage" ] && /bin/rm -f "$local_storage"
}
trap cleanup_top_files EXIT HUP INT TERM

renderer="$ROOT/scripts/terminal/mj-top-render.js"
mode=$(_mj_terminal_mode)
color=0
_mj_color_enabled && color=1
cols="${COLUMNS:-80}"

case "${1:-}" in
    --plain) mode=plain; color=0 ;;
    --ascii) mode=ascii ;;
    "") ;;
    *) /bin/echo "Usage: mj-top [--plain|--ascii]" >&2; exit 64 ;;
esac

[ -r "$renderer" ] || { /bin/echo "MJ dashboard renderer not found: $renderer" >&2; exit 66; }
[ -x /usr/bin/osascript ] || { /bin/echo "mj-top requires stock macOS /usr/bin/osascript for JSON rendering." >&2; exit 69; }

local_doctor=$(/usr/bin/mktemp "/tmp/mj-top-doctor.XXXXXX") || exit 1
local_describe=$(/usr/bin/mktemp "/tmp/mj-top-describe.XXXXXX") || exit 1
local_verify=$(/usr/bin/mktemp "/tmp/mj-top-verify.XXXXXX") || exit 1
local_storage=$(/usr/bin/mktemp "/tmp/mj-top-storage.XXXXXX") || exit 1

_mj_request_noargs "$local_doctor" "top-doctor" "system.doctor" || { /bin/cat "$local_doctor"; exit 1; }
_mj_request_noargs "$local_describe" "top-describe" "system.describe" || { /bin/cat "$local_describe"; exit 1; }

version=$(/usr/bin/sed -n '1s/^MographJailed //p' "$ROOT/VERSION")
protocol=$(/usr/bin/sed -n '2s/^Protocol //p' "$ROOT/VERSION")
filename="mograph-jailed.zsh"
[ -n "$version" ] && [ -n "$protocol" ] || { /bin/echo "MJ VERSION metadata is incomplete." >&2; exit 66; }

local_req=$(/usr/bin/mktemp "/tmp/mj-top-request.XXXXXX") || exit 1
/bin/cat > "$local_req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=top-runtime-verify
command=runtime.verify
arg.expectedCliVersion=$(_mj_b64 "$version")
arg.expectedProtocolVersion=$(_mj_b64 "$protocol")
arg.expectedFilename=$(_mj_b64 "$filename")
REQ
/bin/zsh -f "$(_mj_cli)" --request "$local_req" > "$local_verify"
verify_rc=$?
/bin/rm -f "$local_req"
local_req=""
[ "$verify_rc" -eq 0 ] || { /bin/cat "$local_verify"; exit "$verify_rc"; }

_mj_request_path "$local_storage" "top-storage" "storage.preflight" "$ROOT" || { /bin/cat "$local_storage"; exit 1; }

/usr/bin/osascript -l JavaScript "$renderer" "$local_doctor" "$local_describe" "$local_verify" "$local_storage" "$mode" "$color" "$cols"
exit $?
