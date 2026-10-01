# mj — power-user front end for the MographJailed runtime.
# Safe to source from zsh; it performs no work at source time.
#
#   mj <operation> [name=value ...]   run one allowlisted operation
#   mj ops                            list operations with their arguments
#   mj recipe <file> [name=value ...] run a recipe (one operation per line)
#
# Recipes are data, not scripts: every line is "<operation> name=value ...",
# {{name}} placeholders are filled from the command line, and the whole recipe
# is checked against system.describe before the first step runs.

# An older `mj` alias (cd to the install folder) would shadow this function.
unalias mj 2>/dev/null

_MJ_CLI_DIR=${${(%):-%x}:A:h}

_mj_ui() {
    local ui="${MJ_UI:-$_MJ_CLI_DIR/../terminal/mj_ui.py}"
    [ -r "$ui" ] || { print -u2 "mj: terminal UI not found: $ui"; return 66; }
    MJ_CLI="$(_mj_cli_path)" /usr/bin/python3 "$ui" "$@"
}

_mj_cli_path() {
    printf '%s\n' "${MJ_CLI:-${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/dist/mograph-jailed.zsh}"
}

# Run one request; response JSON on stdout, runtime exit code returned.
_mj_run() {
    local op="$1"; shift
    local req a name rc
    req=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mj-cli-request.XXXXXX") || return 1
    {
        printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=mj-%s-%s\ncommand=%s\n' "$$" "$RANDOM" "$op"
        for a in "$@"; do
            name=${a%%=*}
            printf 'arg.%s=%s\n' "$name" "$(printf '%s' "${a#*=}" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
        done
    } > "$req"
    /bin/zsh -f "$(_mj_cli_path)" --request "$req"
    rc=$?
    /bin/rm -f "$req"
    return $rc
}

# --- notifications --------------------------------------------------------
# Opt-in (`mj notify on`): a marker file in the local store. A notification fires when a
# render, golden check or recipe finishes, or any operation runs for 10 s or more.
# Text reaches osascript as arguments (never spliced into script source), so nothing in a
# path, label or error message can be interpreted as AppleScript.
zmodload -F zsh/datetime b:strftime p:EPOCHREALTIME 2>/dev/null

_mj_store() { print -r -- "${MJ_STORE_DIR:-$HOME/Library/Application Support/MographJailed}"; }

_mj_notify_on() { [ -e "$(_mj_store)/notify.on" ]; }

# _mj_notify_fire <title> <message> <good|bad>
_mj_notify_fire() {
    local osa="${MJ_OSASCRIPT:-/usr/bin/osascript}"
    [ -x "$osa" ] || return 0
    local sound="Glass"
    [ "$3" = good ] || sound="Basso"
    "$osa" -e 'on run argv' \
           -e 'display notification (item 1 of argv) with title (item 2 of argv) sound name (item 3 of argv)' \
           -e 'end run' -- "$2" "$1" "$sound" >/dev/null 2>&1 &!
}

# _mj_notify_op <op> <elapsed seconds> <response json>
_mj_notify_op() {
    _mj_notify_on || return 0
    local op="$1" elapsed="$2" json="$3" msg good
    case "$op" in
        ae.render|c4d.render|golden.check) ;;
        *) (( elapsed >= 10 )) || return 0 ;;
    esac
    msg=$(print -r -- "$json" | /usr/bin/jq -r '
        if .ok != true then "failed: \(.error.code // "error")"
        else .data
          | if .schema == "MJ_RENDER_1" then "\(.status): \(.frames.count) frames in \(.seconds)s"
            elif .schema == "MJ_GOLDEN_CHECK_1" then (if .passed then "golden check passed (\(.framesRecorded) frames)" else "golden check: \(.framesFailed) of \(.framesRecorded) frames changed" end)
            else "done" end
        end' 2>/dev/null) || msg="finished"
    good=$(print -r -- "$json" | /usr/bin/jq -r 'if .ok == true and ((.data.status // "complete") == "complete") and ((.data.passed // true) == true) then "good" else "bad" end' 2>/dev/null) || good=bad
    _mj_notify_fire "mj $op" "$msg" "$good"
}

_mj_notify_cmd() {
    local store flag
    store=$(_mj_store); flag="$store/notify.on"
    case "${1:-status}" in
        on)
            [ -d "$store" ] || { /bin/mkdir -p "$store" && /bin/chmod 700 "$store"; } || { print -u2 "mj: cannot create $store"; return 73; }
            : > "$flag" && print "notifications on"
            ;;
        off) /bin/rm -f "$flag"; print "notifications off" ;;
        test)
            local osa="${MJ_OSASCRIPT:-/usr/bin/osascript}"
            [ -x "$osa" ] || { print -u2 "mj: osascript not available"; return 69; }
            _mj_notify_fire "mj" "Notifications are working." good
            print "sent a test notification (macOS may ask for permission the first time)"
            ;;
        status) if [ -e "$flag" ]; then print "notifications on"; else print "notifications off  (mj notify on)"; fi ;;
        *) print -u2 "usage: mj notify on|off|test|status"; return 64 ;;
    esac
}

_mj_print() {
    if [ -t 1 ] && [ -x /usr/bin/jq ]; then /usr/bin/jq .; else /bin/cat; fi
}

_MJ_DESCRIBE=""
_mj_describe() {
    [ -n "$_MJ_DESCRIBE" ] || _MJ_DESCRIBE=$(_mj_run system.describe 2>/dev/null) || { _MJ_DESCRIBE=""; return 1; }
    print -r -- "$_MJ_DESCRIBE"
}

_mj_check_args() {
    local a
    for a in "$@"; do
        case "$a" in
            [A-Za-z]*=*) case "${a%%=*}" in *[!A-Za-z0-9]*) print -u2 "mj: bad argument name: ${a%%=*}"; return 64 ;; esac ;;
            *) print -u2 "mj: arguments must be name=value: $a"; return 64 ;;
        esac
    done
}

_mj_recipe() {
    local file="$1"; shift
    local -a lines steps toks vars
    local line tok op step=0 total=0 rc v name rest allowed out
    local -a args
    local -A params
    [ -r "$file" ] || { print -u2 "mj: recipe not readable: $file"; return 66; }
    _mj_check_args "$@" || return
    for v in "$@"; do params[${v%%=*}]="${v#*=}"; done
    allowed=$(_mj_describe | /usr/bin/jq -c '.data.operations | map_values(.args.allowed)') || { print -u2 "mj: cannot read the operation registry"; return 69; }

    # Pass 1: validate every step before running anything.
    lines=("${(@f)$(<"$file")}")
    for line in "${lines[@]}"; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        toks=("${(@Q)${(z)line}}")
        op="${toks[1]}"
        print -r -- "$allowed" | /usr/bin/jq -e --arg op "$op" 'has($op)' >/dev/null || { print -u2 "mj: recipe step uses unknown operation: $op"; return 65; }
        for tok in "${toks[@]:1}"; do
            _mj_check_args "$tok" || return
            print -r -- "$allowed" | /usr/bin/jq -e --arg op "$op" --arg n "${tok%%=*}" '.[$op] | index($n) != null' >/dev/null \
                || { print -u2 "mj: $op does not accept argument: ${tok%%=*}"; return 65; }
            rest="$tok"
            while [[ "$rest" == *'{{'*'}}'* ]]; do
                name="${rest#*\{\{}"; name="${name%%\}\}*}"
                (( ${+params[$name]} )) || { print -u2 "mj: recipe needs $name=<value>"; return 64; }
                rest="${rest#*\}\}}"
            done
        done
        steps+=("$line")
    done
    total=${#steps}
    (( total > 0 )) || { print -u2 "mj: recipe has no steps"; return 65; }

    # Pass 2: run, stopping at the first failure.
    for line in "${steps[@]}"; do
        step=$((step + 1))
        toks=("${(@Q)${(z)line}}")
        op="${toks[1]}"
        args=()
        for tok in "${toks[@]:1}"; do
            for name in ${(k)params}; do tok="${tok//\{\{$name\}\}/${params[$name]}}"; done
            args+=("$tok")
        done
        print -u2 "[$step/$total] $op"
        out=$(_mj_run "$op" "${args[@]}")
        rc=$?
        print -r -- "$out" | _mj_print
        (( rc == 0 )) || {
            print -u2 "mj: step $step ($op) failed with exit $rc; recipe stopped"
            _mj_notify_on && _mj_notify_fire "mj recipe" "stopped at step $step of $total ($op)" bad
            return $rc
        }
    done
    _mj_notify_on && _mj_notify_fire "mj recipe" "finished all $total steps" good
    return 0
}

mj() {
    case "${1:-}" in
        ""|home)
            _mj_ui home
            return ;;
        ui)
            shift
            _mj_ui ui "$@"
            return ;;
        cd)
            local root="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}"
            if [ -d "$root" ]; then cd "$root"; else print -u2 "mj: $root not found"; return 66; fi
            return ;;
        -h|--help|help)
            /bin/cat <<'USAGE'
mj                                 launch screen: status of hosts, library, audit log, renders
mj ui [--tab renders|library|audit]  live dashboard (q quits, 1-4 or Tab switches)
mj cd                              go to the MographJailed folder
mj <operation> [name=value ...]    run one allowlisted operation
mj ops                             list operations and their arguments
mj recipe <file> [name=value ...]  run a recipe file, stopping at the first failure
mj last                            show the newest render receipt
mj status                          one-line status (rendering progress, last render)
mj notify on|off|test|status       macOS notifications when renders, golden checks, recipes or long operations finish
mj open-last                       open the newest render folder in Finder
USAGE
            return 0 ;;
        ops)
            # Required arguments are marked with *.
            _mj_describe | /usr/bin/jq -r '.data.operations | to_entries[] | .value.args as $g
                | "\(.key)\t\(.value.state)\t\($g.allowed | map(. as $a | if ($g.required | index($a)) != null then $a + "*" else $a end) | join(" "))"' 2>/dev/null \
            || { print -u2 "mj: cannot read the operation registry"; return 69; }
            return ;;
        notify)
            shift
            _mj_notify_cmd "$@"
            return ;;
        status)
            shift
            _mj_ui status "$@"
            return ;;
        last|open-last)
            local store="${MJ_STORE_DIR:-$HOME/Library/Application Support/MographJailed}" dir
            [ -r "$store/last-render.json" ] || { print -u2 "mj: no render yet"; return 66; }
            if [ "$1" = last ]; then
                /bin/cat "$(/usr/bin/jq -r .receiptPath "$store/last-render.json")" | _mj_print
            else
                dir=$(/usr/bin/jq -r .outputDir "$store/last-render.json")
                [ -d "$dir" ] || { print -u2 "mj: render folder is gone: $dir"; return 66; }
                /usr/bin/open "$dir"
            fi
            return ;;
        recipe)
            shift
            [ -n "${1:-}" ] || { print -u2 "usage: mj recipe <file> [name=value ...]"; return 64; }
            _mj_recipe "$@"
            return ;;
    esac
    local op="$1" out rc
    shift
    _mj_check_args "$@" || return
    local t0=$EPOCHREALTIME
    out=$(_mj_run "$op" "$@")
    rc=$?
    print -r -- "$out" | _mj_print
    _mj_notify_op "$op" $(( EPOCHREALTIME - t0 )) "$out"
    return $rc
}

# Completion: operations, then each operation's argument names (from
# system.describe), then file paths for values.
_mj_complete() {
    local -a items
    local json
    json=$(_mj_describe) || return 1
    if (( CURRENT == 2 )); then
        items=(${(f)"$(print -r -- "$json" | /usr/bin/jq -r '.data.operations | keys[]')"} ops recipe last open-last ui home cd status notify)
        compadd -a items
    elif [[ "${words[2]}" == recipe ]]; then
        _files
    elif [[ "$PREFIX" == *=* ]]; then
        compset -P '*='
        _files
    else
        items=(${(f)"$(print -r -- "$json" | /usr/bin/jq -r --arg op "${words[2]}" '.data.operations[$op].args.allowed[]?')"})
        compadd -S '=' -q -a items
    fi
}
(( $+functions[compdef] )) && compdef _mj_complete mj
