# Shared local terminal UX helpers for MographJailed.
# This file is safe to source from zsh; it performs no work at source time.
_mj_root() {
    printf '%s\n' "${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}"
}

_mj_terminal_mode() {
    if [ "${MJ_PLAIN:-0}" = "1" ] || [ ! -t 1 ] || [ "${TERM:-dumb}" = "dumb" ]; then
        printf 'plain\n'
    elif [ "${MJ_ASCII:-0}" = "1" ]; then
        printf 'ascii\n'
    else
        printf 'modern\n'
    fi
}

_mj_color_enabled() {
    [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ] && [ "${MJ_PLAIN:-0}" != "1" ]
}

_mj_b64() {
    printf '%s' "$1" | /usr/bin/base64
}

_mj_cli() {
    local root
    root=$(_mj_root)
    printf '%s\n' "$root/dist/mograph-jailed.zsh"
}

_mj_request_noargs() {
    local out="$1"
    local id="$2"
    local command="$3"
    local req
    req=$(/usr/bin/mktemp "/tmp/mj-terminal-request.XXXXXX") || return 1
    /bin/cat > "$req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=$id
command=$command
REQ
    /bin/zsh -f "$(_mj_cli)" --request "$req" > "$out"
    local rc=$?
    /bin/rm -f "$req"
    return $rc
}

_mj_request_path() {
    local out="$1"
    local id="$2"
    local command="$3"
    local path="$4"
    local req
    local encoded
    req=$(/usr/bin/mktemp "/tmp/mj-terminal-request.XXXXXX") || return 1
    encoded=$(_mj_b64 "$path") || { /bin/rm -f "$req"; return 1; }
    /bin/cat > "$req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=$id
command=$command
arg.path=$encoded
REQ
    /bin/zsh -f "$(_mj_cli)" --request "$req" > "$out"
    local rc=$?
    /bin/rm -f "$req"
    return $rc
}
