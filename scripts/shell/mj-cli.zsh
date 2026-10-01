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
        (( rc == 0 )) || { print -u2 "mj: step $step ($op) failed with exit $rc; recipe stopped"; return $rc; }
    done
}

mj() {
    case "${1:-}" in
        ""|-h|--help|help)
            /bin/cat <<'USAGE'
mj <operation> [name=value ...]    run one allowlisted operation
mj ops                             list operations and their arguments
mj recipe <file> [name=value ...]  run a recipe file, stopping at the first failure
mj last                            show the newest render receipt
mj open-last                       open the newest render folder in Finder
USAGE
            return 0 ;;
        ops)
            # Required arguments are marked with *.
            _mj_describe | /usr/bin/jq -r '.data.operations | to_entries[] | .value.args as $g
                | "\(.key)\t\(.value.state)\t\($g.allowed | map(. as $a | if ($g.required | index($a)) != null then $a + "*" else $a end) | join(" "))"' 2>/dev/null \
            || { print -u2 "mj: cannot read the operation registry"; return 69; }
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
    out=$(_mj_run "$op" "$@")
    rc=$?
    print -r -- "$out" | _mj_print
    return $rc
}

# Completion: operations, then each operation's argument names (from
# system.describe), then file paths for values.
_mj_complete() {
    local -a items
    local json
    json=$(_mj_describe) || return 1
    if (( CURRENT == 2 )); then
        items=(${(f)"$(print -r -- "$json" | /usr/bin/jq -r '.data.operations | keys[]')"} ops recipe last open-last)
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
