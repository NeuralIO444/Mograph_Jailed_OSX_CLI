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
[ -r "$_MJ_CLI_DIR/mj-config.zsh" ] && source "$_MJ_CLI_DIR/mj-config.zsh"

_mj_ui() {
    local ui="${MJ_UI:-$_MJ_CLI_DIR/../terminal/mj_ui.py}"
    [ -r "$ui" ] || { print -u2 "mj: terminal UI not found: $ui"; return 66; }
    MJ_CLI="$(_mj_cli_path)" /usr/bin/python3 "$ui" "$@"
}

_mj_cli_path() {
    # flag > environment (MJ_CLI) > config file (cli=) > the install folder
    if (( $+functions[mj_config_get] )); then mj_config_get cli; else printf '%s\n' "${MJ_CLI:-${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/dist/mograph-jailed.zsh}"; fi
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

# --- human commands ---------------------------------------------------------
_mj_explain() { /usr/bin/python3 "$_MJ_CLI_DIR/../terminal/mj_explain.py" "$@"; }

# Newest file matching a glob in a folder.
_mj_newest() { local d="$1" pat="$2" f; local -a m; m=("$d"/${~pat}(.Nom[1])); [ ${#m} -gt 0 ] && print -r -- "${m[1]}"; }

_mj_need_dir() {   # _mj_need_dir <config key> <what>  -> prints the folder, or explains how to set it
    local d; d=$(mj_config_get "$1")
    [ -d "$d" ] || { print -u2 "mj: your $2 folder was not found${d:+: $d}"; print -u2 "  Set it once:  mj config set $1 <folder>"; return 66; }
    print -r -- "$d"
}

# A project given by path or by name (searched under watch_dir). Prints one .aep path.
_mj_resolve_project() {
    setopt localoptions extendedglob
    local arg="$1" w stem pat h; local -a hits exact
    if [ -f "$arg" ]; then print -r -- "${arg:A}"; return 0; fi
    w=$(mj_config_get watch_dir)
    if [ -d "$w" ]; then
        stem="${arg%.[aA][eE][pP]}"; stem="${stem%.[cC]4[dD]}"
        pat="${stem//(#m)[\[\]*?\\]/\\$MATCH}"           # what you type is a name, never a wildcard
        hits=("${(@f)$(/usr/bin/find "$w" -maxdepth 3 -type f \( -iname "${pat}*.aep" -o -iname "${pat}*.c4d" \) 2>/dev/null | /usr/bin/sort)}")
        hits=(${hits:#})
        for h in $hits; do [[ "${(L)${h:t:r}}" == "${(L)stem}" ]] && exact+=("$h"); done
        if [ ${#exact} -eq 1 ]; then print -r -- "${exact[1]}"; return 0; fi     # an exact name wins over longer names that start with it
        if [ ${#hits} -eq 1 ]; then print -r -- "${hits[1]}"; return 0; fi
        if [ ${#hits} -gt 1 ]; then print -u2 "mj: \"$arg\" matches more than one project; be more specific:"; printf '  %s\n' "${hits[@]}" >&2; return 65; fi
    fi
    print -u2 "mj: no project found for \"$arg\""
    [ -d "$w" ] || print -u2 "  To search by name, set your projects folder once:  mj config set watch_dir <folder>"
    return 66
}

# Newest Cinema 4D scene receipt, or a path.
_mj_resolve_c4d() {
    local arg="${1:-last}" d f
    if [ "$arg" = last ]; then
        d=$(_mj_need_dir receipts_dir receipts) || return $?
        f=$(_mj_newest "$d" '*.c4dscrape.json')
        [ -n "$f" ] || { print -u2 "mj: no Cinema 4D scene receipts in $d yet (run integrations/cinema4d/MographJailed_C4DScraper.py under c4dpy)"; return 66; }
        print -r -- "$f"
    elif [ -f "$arg" ]; then print -r -- "${arg:A}"
    else print -u2 "mj: no such receipt: $arg"; return 66; fi
}

# Newest scrape receipt, or a path.
_mj_resolve_scrape() {
    local arg="${1:-last}" d f
    if [ "$arg" = last ]; then
        d=$(_mj_need_dir receipts_dir receipts) || return $?
        f=$(_mj_newest "$d" '*.scrape.json')
        [ -n "$f" ] || { print -u2 "mj: no scrape receipts in $d yet (run the After Effects scraper first)"; return 66; }
        print -r -- "$f"
    elif [ -f "$arg" ]; then print -r -- "${arg:A}"
    else print -u2 "mj: no such receipt: $arg"; return 66; fi
}

_mj_say() {   # run an operation, print it in plain language, return its exit code
    local out rc
    out=$(_mj_run "$@"); rc=$?
    print -r -- "$out" | _mj_explain - ; return $rc
}

_mj_versions() {
    local d name f when size stem ts; local -a rows
    d=$(_mj_need_dir versions_dir versions) || return $?
    name="${1:-}"
    for f in "$d"/*.(aep|c4d)(.Nom); do
        [[ "${f:t}" =~ '^(.*)\.([0-9]{8}T[0-9]{6}Z)\.([0-9a-f]{12})\.(aep|c4d)$' ]] || continue
        stem="${match[1]}"; ts="${match[2]}"
        [ "${match[4]}" = c4d ] && stem="$stem.c4d"
        [ -z "$name" ] || [[ "${(L)stem}" == *"${(L)name}"* ]] || continue
        zmodload -F zsh/stat b:zstat 2>/dev/null
        zstat -A when -F '%Y-%m-%d %H:%M' +mtime -- "$f"; zstat -A size +size -- "$f"
        local hsize
        if (( ${size[1]} >= 1048576 )); then hsize=$(printf '%.1f MB' $(( ${size[1]} / 1048576.0 )));
        elif (( ${size[1]} >= 1024 )); then hsize=$(printf '%d KB' $(( ${size[1]} / 1024 ))); else hsize="${size[1]} bytes"; fi
        rows+=("$(printf '%-28s %s   %10s   %s' "$stem" "${when[1]}" "$hsize" "${match[3]}")")
    done
    [ ${#rows} -gt 0 ] || { print "No versions${name:+ matching \"$name\"} in $d yet."; return 0; }
    print "Versions in $d (newest first):"; printf '  %s\n' "${rows[@]}"
}

_mj_watch() {
    local tools="$_MJ_CLI_DIR/../../tools" w v label="com.neuralio.mograph-jailed.watcher"
    case "${1:-status}" in
        on)
            w=$(_mj_need_dir watch_dir "projects (watch)") || return $?
            v=$(mj_config_get versions_dir); [ -n "$v" ] || { print -u2 "mj: set a versions folder first:  mj config set versions_dir <folder>"; return 66; }
            /bin/zsh -f "$tools/watch-install.zsh" --yes "$w" "$v" ;;
        off) /bin/zsh -f "$tools/watch-uninstall.zsh" --yes ;;
        status)
            v=$(mj_config_get versions_dir)
            if /bin/launchctl list 2>/dev/null | /usr/bin/grep -q "$label"; then print "Watcher: on  (versioning .aep and .c4d files in $(mj_config_get watch_dir))"; else print "Watcher: off  (turn on with: mj watch on)"; fi
            if [ -r "$v/watcher.log" ]; then print "Recent activity:"; /usr/bin/tail -n 3 "$v/watcher.log" | /usr/bin/sed 's/^/  /'; fi ;;
        *) print -u2 "usage: mj watch on|off|status"; return 64 ;;
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

    [ -z "${MJ_RECIPE_CHECK_ONLY:-}" ] || return 0      # validation only (used by mj batch before it touches any file)

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
        [ -n "${MJ_RECIPE_QUIET:-}" ] || print -u2 "[$step/$total] $op"
        out=$(_mj_run "$op" "${args[@]}")
        rc=$?
        [ -n "${MJ_RECIPE_QUIET:-}" ] || print -r -- "$out" | _mj_print
        (( rc == 0 )) || {
            local ecode; ecode=$(print -r -- "$out" | /usr/bin/jq -r '.error.code // empty' 2>/dev/null)
            print -u2 "mj: step $step ($op) failed with exit $rc${ecode:+ ($ecode)}; recipe stopped"
            [ -n "${MJ_RECIPE_QUIET:-}" ] || { _mj_notify_on && _mj_notify_fire "mj recipe" "stopped at step $step of $total ($op)" bad; }
            return $rc
        }
    done
    [ -n "${MJ_RECIPE_QUIET:-}" ] || { _mj_notify_on && _mj_notify_fire "mj recipe" "finished all $total steps" good; }
    return 0
}

# mj batch <recipe> <folder> [--pattern GLOB] [name=value ...]
# Runs the recipe once per matching file ({{file}} is the path), keeps going after a failure, and ends
# with a summary. Exit status is non-zero if any file failed.
_mj_batch() {
    local recipe="${1:-}" dir="${2:-}" pat="*.scrape.json" i=0 ok=0 bad=0 n=0 f err t0
    local -a files extra
    [ -n "$recipe" ] && [ -n "$dir" ] || { print -u2 "usage: mj batch <recipe> <folder> [--pattern GLOB] [name=value ...]"; return 64; }
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --pattern) [ -n "${2:-}" ] || { print -u2 "mj: --pattern needs a value"; return 64; }; pat="$2"; shift 2 ;;
            *) extra+=("$1"); shift ;;
        esac
    done
    [ -r "$recipe" ] || { print -u2 "mj: recipe not readable: $recipe"; return 66; }
    [ -d "$dir" ] || { print -u2 "mj: folder not found: $dir"; return 66; }
    files=("${(@f)$(/usr/bin/find "$dir" -maxdepth 3 -type f -name "$pat" 2>/dev/null | LC_ALL=C /usr/bin/sort | /usr/bin/head -500)}")
    files=(${files:#})
    [ ${#files} -gt 0 ] || { print "No files matching $pat under $dir."; return 0; }
    # Check the whole recipe against the registry once, before touching any file.
    err=$(MJ_RECIPE_CHECK_ONLY=1 _mj_recipe "$recipe" "file=${files[1]}" "${extra[@]}" 2>&1 >/dev/null) || { print -u2 -r -- "$err"; return 65; }
    n=${#files}
    t0=$EPOCHREALTIME
    for f in "${files[@]}"; do
        i=$((i + 1))
        err=$(MJ_RECIPE_QUIET=1 _mj_recipe "$recipe" "file=$f" "${extra[@]}" 2>&1 >/dev/null)
        if [ $? -eq 0 ]; then
            ok=$((ok + 1)); printf '  ✓ %s\n' "${f#$dir/}"
        else
            bad=$((bad + 1)); printf '  ✗ %s   %s\n' "${f#$dir/}" "${err##*mj: }"
        fi
    done
    printf '\n%d file%s: %d ok, %d failed  (%.0fs)\n' $n "$([ $n -eq 1 ] || print s)" $ok $bad $(( EPOCHREALTIME - t0 ))
    _mj_notify_on && _mj_notify_fire "mj batch" "$ok of $n files ok${bad:+, $bad failed}" "$([ $bad -eq 0 ] && print good || print bad)"
    [ $bad -eq 0 ]
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
mj snapshot <project>              save a verified version of a project (path or name)
mj versions [project]              list saved versions
mj lint [last|<scrape>]            check expressions, in plain language
mj health [last|<scrape>] [--record]  project health score (0-100)
mj scene [last|<c4d scrape>] [--summary]   check a Cinema 4D scene receipt, in plain language
mj bridge <c4d scrape> [<ae scrape>|last] [comp]   does the AE comp match the C4D scene?
mj diff last | <older> <newer>     what changed between two scrapes
mj explain [last|<file>]           any receipt, in plain language
mj watch on|off|status             automatic versioning of your .aep and .c4d files
mj doctor                          is this Mac ready? what is missing?
mj batch <recipe> <folder>         run a recipe over every file in a folder, with a summary
mj last                            show the newest render receipt
mj status                          one-line status (rendering progress, last render)
mj notify on|off|test|status       macOS notifications when renders, golden checks, recipes or long operations finish
mj config [set <key> <value>]      remembered settings (versions_dir, receipts_dir, watch_dir, cli, post_snapshot_hook)
mj open-last                       open the newest render folder in Finder
USAGE
            return 0 ;;
        ops)
            # Required arguments are marked with *.
            _mj_describe | /usr/bin/jq -r '.data.operations | to_entries[] | .value.args as $g
                | "\(.key)\t\(.value.state)\t\($g.allowed | map(. as $a | if ($g.required | index($a)) != null then $a + "*" else $a end) | join(" "))"' 2>/dev/null \
            || { print -u2 "mj: cannot read the operation registry"; return 69; }
            return ;;
        snapshot)
            shift; [ -n "${1:-}" ] || { print -u2 "usage: mj snapshot <project path or name>"; return 64; }
            local v p; v=$(_mj_need_dir versions_dir versions) || return $?
            p=$(_mj_resolve_project "$1") || return $?
            _mj_say project.snapshot "path=$p" "output=$v"; return ;;
        lint)
            shift; local s; s=$(_mj_resolve_scrape "${1:-last}") || return $?
            _mj_say expression.lint "path=$s"; return ;;
        health)
            shift
            local rec=0 tgt="last" a; local -a hargs
            for a in "$@"; do [ "$a" = "--record" ] && rec=1 || tgt="$a"; done
            local hs; hs=$(_mj_resolve_scrape "$tgt") || return $?
            hargs=("path=$hs"); [ -d "$(mj_config_get versions_dir)" ] && hargs+=("input=$(mj_config_get versions_dir)")
            (( rec )) && hargs+=("format=record")
            _mj_say project.health "${hargs[@]}"; return ;;
        diff)
            shift
            local da db
            if [ "${1:-last}" = last ] && [ -z "${2:-}" ]; then
                local rd; rd=$(_mj_need_dir receipts_dir receipts) || return $?
                # The newest scrape, and the newest earlier scrape of the SAME project.
                local -a all; all=("$rd"/*.scrape.json(.Nom)); local pp cand
                [ ${#all} -ge 1 ] || { print -u2 "mj: no scrape receipts in $rd yet"; return 66; }
                db="${all[1]}"; pp=$(/usr/bin/jq -r '.projectPath // empty' "$db" 2>/dev/null); da=""
                for cand in "${all[@]:1}"; do
                    [ "$(/usr/bin/jq -r '.projectPath // empty' "$cand" 2>/dev/null)" = "$pp" ] && { da="$cand"; break; }
                done
                [ -n "$da" ] || { print -u2 "mj: need two scrapes of the same project to compare; the newest is of ${pp:-an unknown project}, and there is no earlier one"; return 66; }
            else
                [ -n "${2:-}" ] || { print -u2 "usage: mj diff last   |   mj diff <older scrape> <newer scrape>"; return 64; }
                da=$(_mj_resolve_scrape "$1") || return $?; db=$(_mj_resolve_scrape "$2") || return $?
            fi
            _mj_say project.diff "path=$da" "input=$db"; return ;;
        scene)
            shift
            local cs; cs=$(_mj_resolve_c4d "${1:-last}") || return $?
            if [ "${2:-}" = --summary ]; then _mj_say c4d.inspect "path=$cs"; else _mj_say c4d.lint "path=$cs"; fi; return ;;
        bridge)
            shift
            local bc ba; bc=$(_mj_resolve_c4d "${1:-last}") || return $?
            ba=$(_mj_resolve_scrape "${2:-last}") || return $?
            if [ -n "${3:-}" ]; then _mj_say bridge.check "path=$bc" "input=$ba" "target=$3"; else _mj_say bridge.check "path=$bc" "input=$ba"; fi; return ;;
        explain)
            shift
            local ef="${1:-last}"
            if [ "$ef" = last ]; then
                local sd; sd=$(_mj_store)
                [ -r "$sd/last-render.json" ] || { print -u2 "mj: nothing to explain yet (no render recorded)"; return 66; }
                ef=$(/usr/bin/jq -r .receiptPath "$sd/last-render.json")
            fi
            _mj_explain "$ef"; return ;;
        versions) shift; _mj_versions "$@"; return ;;
        watch) shift; _mj_watch "$@"; return ;;
        doctor) _mj_say system.doctor; return ;;
        notify)
            shift
            _mj_notify_cmd "$@"
            return ;;
        config)
            shift
            case "${1:-show}" in
                show) mj_config_show ;;
                path) _mj_config_file ;;
                get) [ -n "${2:-}" ] || { print -u2 "usage: mj config get <key>"; return 64; }; mj_config_get "$2" || { print -u2 "mj: unknown setting '$2'"; return 64; } ;;
                set) [ -n "${2:-}" ] && [ -n "${3:-}" ] || { print -u2 "usage: mj config set <key> <value>   (keys: $(_mj_config_keys))"; return 64; }; mj_config_set "$2" "$3" && print "saved: $2" ;;
                unset) [ -n "${2:-}" ] || { print -u2 "usage: mj config unset <key>"; return 64; }; mj_config_unset "$2" && print "removed: $2" ;;
                *) print -u2 "usage: mj config [show|path|get <key>|set <key> <value>|unset <key>]"; return 64 ;;
            esac
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
        batch)
            shift; _mj_batch "$@"; return ;;
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

# Completion. First word: human commands and every operation. After a human command: what it
# takes (project files, "last", config keys, on/off ...). After an operation: its argument
# names (read from system.describe, so they never go stale), then file paths for values.
_mj_complete() {
    local -a items
    local json cmd="${words[2]}"
    local -a verbs; verbs=(snapshot versions lint health diff scene bridge explain watch doctor config notify status last open-last ui home cd ops recipe batch help)
    if (( CURRENT == 2 )); then
        json=$(_mj_describe) || json=""
        items=($verbs ${(f)"$(print -r -- "$json" | /usr/bin/jq -r '.data.operations | keys[]' 2>/dev/null)"})
        compadd -a items
        return
    fi
    case "$cmd" in
        snapshot) _files -g '*.(aep|AEP|c4d|C4D)' ;;
        lint|explain|scene|bridge) items=(last); compadd -a items; _files ;;
        health) items=(last --record); compadd -a items; _files ;;
        diff) items=(last); compadd -a items; _files ;;
        watch) items=(on off status); compadd -a items ;;
        notify) items=(on off test status); compadd -a items ;;
        config)
            if (( CURRENT == 3 )); then items=(show path get set unset); compadd -a items
            elif [[ "${words[3]}" == (get|set|unset) ]] && (( CURRENT == 4 )); then items=(${=$(_mj_config_keys)}); compadd -a items
            elif [[ "${words[3]}" == set ]]; then _files; fi ;;
        ui) items=(--tab --once --plain); compadd -a items ;;
        versions) ;;
        recipe) _files ;;
        batch) if (( CURRENT == 3 )); then _files; elif (( CURRENT == 4 )); then _files -/; else items=(--pattern); compadd -a items; fi ;;
        last|open-last|home|cd|doctor|status|ops|help) ;;
        *)
            json=$(_mj_describe) || return 1
            if [[ "$PREFIX" == *=* ]]; then
                compset -P '*='
                _files
            else
                items=(${(f)"$(print -r -- "$json" | /usr/bin/jq -r --arg op "$cmd" '.data.operations[$op].args.allowed[]?')"})
                compadd -S '=' -q -a items
            fi ;;
    esac
}
(( $+functions[compdef] )) && compdef _mj_complete mj
