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
zmodload -F zsh/datetime b:strftime p:EPOCHREALTIME p:EPOCHSECONDS 2>/dev/null

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

# Newest scrape report of a project, by name (exact, else prefix, any case), or last / a report path.
_mj_find() { /usr/bin/python3 "$_MJ_CLI_DIR/../terminal/mj_find.py" "$@"; }

_mj_scrape_for() {
    local arg="${1:-last}" d f rc
    if [ "$arg" = last ] || [ -f "$arg" ]; then _mj_resolve_scrape "$arg"; return; fi
    d=$(_mj_need_dir receipts_dir receipts) || return $?
    f=$(_mj_find "$d" name "$arg" 1 2>"${TMPDIR:-/tmp}/mj-find.$$"); rc=$?
    if [ $rc -eq 0 ]; then /bin/rm -f "${TMPDIR:-/tmp}/mj-find.$$"; print -r -- "$f"; return 0; fi
    if [ $rc -eq 65 ]; then print -u2 "mj: \"$arg\" matches more than one project; be more specific:"; /bin/cat "${TMPDIR:-/tmp}/mj-find.$$" >&2; /bin/rm -f "${TMPDIR:-/tmp}/mj-find.$$"; return 65; fi
    /bin/rm -f "${TMPDIR:-/tmp}/mj-find.$$"
    print -u2 "mj: no project report for \"$arg\" in $d yet."
    print -u2 "  In After Effects run the MographJailed scraper on it first (File > Scripts > Run Script File)."
    return 66
}

# The newest report made from exactly this .aep (full path), so two clients' Main.aep never get mixed up.
_mj_scrape_for_aep() {
    local d f; d=$(_mj_need_dir receipts_dir receipts) || return $?
    f=$(_mj_find "$d" path "$1" 1 2>/dev/null) && { print -r -- "$f"; return 0; }
    print -u2 "mj: there is no project report for $1 yet."
    print -u2 "  In After Effects, open it and run the MographJailed scraper (File > Scripts > Run Script File), then try again."
    return 66
}

# Comp names (from the project's newest scrape) to comp ids: "12,40". Exact names; a name used by two
# comps is refused (the scrape cannot tell them apart by name; pass the id with #12 instead).
_mj_comp_ids() {
    local scrape="$1" name id; shift; local -a ids
    for name in "$@"; do
        if [[ "$name" == \#<-> ]]; then ids+=("${name#\#}"); continue; fi
        id=$(/usr/bin/jq -r --arg n "$name" '[.comps[] | select(.name == $n) | .id] | if length == 1 then .[0] elif length == 0 then "none" else "many" end' "$scrape")
        case "$id" in
            none) print -u2 "mj: no comp named \"$name\" in $(/usr/bin/jq -r .projectName "$scrape")"; print -u2 "  comps: $(/usr/bin/jq -r '[.comps[].name] | join(", ")' "$scrape")"; return 66 ;;
            many) print -u2 "mj: more than one comp is named \"$name\"; give its id instead: $(/usr/bin/jq -r --arg n "$name" '[.comps[] | select(.name == $n) | "#\(.id)"] | join(" ")' "$scrape")"; return 65 ;;
        esac
        ids+=("$id")
    done
    print -r -- "${(j:,:)ids}"
}

# The installed After Effects to send jobs to: the newest complete, supported one.
_mj_ae_app() {
    local app; app=$(_mj_run host.detect | /usr/bin/jq -r '[.data.afterEffects[]? | select(.complete and .supported)] | sort_by(.year) | last | .app // empty')
    [ -n "$app" ] || { print -u2 "mj: no supported After Effects found in /Applications"; return 69; }
    print -r -- "$app"
}

_mj_ae() {
    local sub="${1:-}" job="${2:-}" app name
    case "$sub" in
        run)
            [ -d "$job" ] && [ -f "$job/run.jsx" ] || { print -u2 "usage: mj ae run <job folder>   (made by mj extract or mj conform --apply)"; return 64; }
            app=$(_mj_ae_app) || return $?
            name="${${app:t}%.app}"
            [[ "$name" =~ '^Adobe After Effects 20[0-9][0-9]( \(Beta\))?$' ]] || { print -u2 "mj: unexpected After Effects name: $name"; return 69; }
            print "Sending the job to $name. It asks to close your open project (you can save it), then works on the job's copy."
            print "If macOS asks whether Terminal may control After Effects, allow it; or run ${job:A}/run.jsx from File > Scripts > Run Script File."
            # The app name is checked above; the job path reaches AppleScript as an argument, never as script text.
            : > "${job:A}/quiet"        # the runner then finishes without an alert nobody is there to click
            "${MJ_OSASCRIPT:-/usr/bin/osascript}" -e 'on run argv' -e 'with timeout of 3600 seconds' -e "tell application \"$name\" to DoScriptFile (item 1 of argv)" -e 'end timeout' -e 'end run' -- "${job:A}/run.jsx" >/dev/null || {
                print -u2 "mj: After Effects did not take the job; run ${job:A}/run.jsx from File > Scripts > Run Script File."; return 69; }
            _mj_say project.jobcheck "path=${job:A}"; return ;;
        verify)
            [ -d "$job" ] || { print -u2 "usage: mj ae verify <job folder>"; return 64; }
            _mj_say project.jobcheck "path=${job:A}"; return ;;
        *) print -u2 "usage: mj ae run|verify <job folder>"; return 64 ;;
    esac
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

# The operation registry (system.describe) costs about half a second, and recipes, batches, tab completion and
# `mj ops` all want it. It is kept on disk, keyed on the runtime file's size and modification time, so a new
# build gets a new copy and a stale one is never used; it is also refreshed daily. Safe to delete at any time.
_MJ_DESCRIBE=""
_mj_describe() {
    if [ -z "$_MJ_DESCRIBE" ]; then
        local cli f store out; local -a st sz
        zmodload -F zsh/stat b:zstat 2>/dev/null
        cli=$(_mj_cli_path); store=$(_mj_store)
        if zstat -A st +mtime -- "$cli" 2>/dev/null && zstat -A sz +size -- "$cli" 2>/dev/null; then
            f="$store/describe-${st[1]}-${sz[1]}.json"
            if [ -r "$f" ] && [ -z "$(print -r -- $f(N.mm+1440))" ]; then _MJ_DESCRIBE=$(<"$f"); fi
        fi
        if [ -z "$_MJ_DESCRIBE" ]; then
            out=$(_mj_run system.describe 2>/dev/null) || return 1
            _MJ_DESCRIBE="$out"
            if [ -n "$f" ] && [ -d "$store" ]; then
                print -r -- "$out" > "$f.$$" 2>/dev/null && /bin/mv -f "$f.$$" "$f" 2>/dev/null
                /bin/rm -f ${store}/describe-*.json(N.e:'[[ $REPLY != "'"$f"'" ]]':) 2>/dev/null
            fi
        fi
    fi
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
    _mj_describe >/dev/null; allowed=$(print -r -- "$_MJ_DESCRIBE" | /usr/bin/jq -c '.data.operations | map_values(.args.allowed)') || { print -u2 "mj: cannot read the operation registry"; return 69; }

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

# --- first-run setup, health checklist, typo help -------------------------------------------------------------
_mj_ask() {   # _mj_ask <prompt> <default> -> the answer (Enter takes the default; no terminal means the default)
    local ans=""
    if [ "${MJ_YES:-0}" = 1 ] || [ ! -r /dev/tty ] || [ ! -t 0 ]; then print -r -- "$2"; return; fi
    printf '   %s [%s]: ' "$1" "$2" >&2
    IFS= read -r ans < /dev/tty || ans=""
    case "$ans" in "~"*) ans="$HOME${ans#\~}" ;; esac
    print -r -- "${ans:-$2}"
}

# The projects folder most likely to hold After Effects work: the usual places, the one with the most projects.
_mj_guess_projects_dir() {
    local d n best="" bn=0
    for d in "$HOME/Movies" "$HOME/Documents" "$HOME/Desktop" "$HOME/Creative Cloud Files" "$HOME/Library/CloudStorage"; do
        [ -d "$d" ] || continue
        n=$(/usr/bin/find "$d" -maxdepth 3 -type f \( -iname '*.aep' -o -iname '*.c4d' \) 2>/dev/null | /usr/bin/head -200 | /usr/bin/wc -l)
        (( n > bn )) && { bn=$n; best="$d"; }
    done
    [ -n "$best" ] || { [ -d "$HOME/Documents" ] && best="$HOME/Documents" || best="$HOME"; }
    print -r -- "$best"
}

_mj_scraper_path() { print -r -- "${_MJ_CLI_DIR:A}/../../integrations/after-effects/MographJailed_ProjectScraper.jsx"(:A); }

_mj_setup() {
    local a rec ver w scraper
    for a in "$@"; do [ "$a" = --yes ] && export MJ_YES=1; done
    print "Setting up MographJailed. Press Enter to accept the suggestion in [brackets]."
    print
    w=$(mj_config_get watch_dir); { [ -n "$w" ] && [ -d "$w" ]; } || w=$(_mj_guess_projects_dir)
    print "Where do you keep your project files? (.aep and .c4d are looked for in here)"
    w=$(_mj_ask "Projects folder" "$w")
    rec=$(mj_config_get receipts_dir); ver=$(mj_config_get versions_dir)
    print "Where should project reports (the checks you run) be kept?"
    rec=$(_mj_ask "Reports folder" "$rec")
    print "Where should saved versions of your projects go?"
    ver=$(_mj_ask "Versions folder" "$ver")
    [ -d "$w" ] || { print -u2 "mj: the projects folder does not exist: $w"; return 66; }
    /bin/mkdir -p "$rec" "$ver" || { print -u2 "mj: could not create the folders"; return 73; }
    mj_config_set watch_dir "$w" >/dev/null && mj_config_set receipts_dir "$rec" >/dev/null && mj_config_set versions_dir "$ver" >/dev/null || return 73
    print
    print "  Saved. Projects: $w"
    print "         Reports:  $rec"
    print "         Versions: $ver"
    scraper=$(_mj_scraper_path)
    print
    print "One thing is left, and it happens in After Effects:"
    print "  1. Open a project, then choose  File > Scripts > Run Script File..."
    print "  2. Pick this file:  $scraper"
    print "  3. When it asks where to save, choose:  $rec"
    print "Then come back here and type:  mj check"
    if [ "${MJ_YES:-0}" != 1 ] && [ -t 0 ] && [ "$(_mj_ask "Show that file in Finder now? (y/n)" "y")" = y ]; then /usr/bin/open -R "$scraper" 2>/dev/null; fi
    return 0
}

# A plain checklist of what this Mac and this setup can do, with one fix per line.
_mj_doctor() {
    local out rc=0 ae c4d w rec ver tick="  ok " cross="  !! " n
    out=$(_mj_run system.doctor); rc=$?
    print -r -- "$out" | _mj_explain - || true
    print
    print "Your setup:"
    local hosts; hosts=$(_mj_run host.detect 2>/dev/null)
    ae=$(print -r -- "$hosts" | /usr/bin/jq -r '[.data.afterEffects[]? | select(.supported)] | sort_by(.year) | last | .year // empty' 2>/dev/null)
    c4d=$(print -r -- "$hosts" | /usr/bin/jq -r '[.data.cinema4d[]? | select(.supported)] | sort_by(.year) | last | .year // empty' 2>/dev/null)
    if [ -n "$ae" ]; then print "${tick}After Effects $ae found"; else print "${cross}After Effects 2024 or newer was not found in /Applications. Checks on saved reports still work; rendering and project jobs need it."; fi
    if [ -n "$c4d" ]; then print "${tick}Cinema 4D $c4d found"; else print "     Cinema 4D 2024 or newer was not found (only needed for Cinema 4D scene checks and renders)"; fi
    w=$(mj_config_get watch_dir); rec=$(mj_config_get receipts_dir); ver=$(mj_config_get versions_dir)
    if [ -n "$w" ] && [ -d "$w" ]; then print "${tick}Projects folder: $w"; else print "${cross}No projects folder set. Fix:  mj setup"; fi
    if [ -d "$rec" ]; then
        local -a rf; rf=("$rec"/*.scrape.json(N)); n=${#rf}
        if [ "$n" -gt 0 ]; then print "${tick}Reports folder: $rec ($n report$([ "$n" = 1 ] || print s))"; else print "${cross}No project reports yet in $rec. Fix: in After Effects run the MographJailed script (mj scraper shows how)"; fi
    else print "${cross}Reports folder not found: $rec. Fix:  mj setup"; fi
    if [ -d "$ver" ]; then print "${tick}Versions folder: $ver"; else print "${cross}Versions folder not found: $ver. Fix:  mj setup"; fi
    if /bin/launchctl list 2>/dev/null | /usr/bin/grep -q com.neuralio.mograph-jailed.watcher; then print "${tick}Automatic versioning is on"; else print "     Automatic versioning is off (optional):  mj watch on"; fi
    return $rc
}

# "mj frobnicate": the nearest command, if there is one.
_mj_suggest() {
    local word="$1" cands
    cands="snapshot versions lint health check timeline space qc extract conform scene bridge diff explain watch doctor setup scraper config notify status last ui help"
    /usr/bin/python3 -c '
import difflib, sys
w, c = sys.argv[1], sys.argv[2].split()
m = difflib.get_close_matches(w, c, n=1, cutoff=0.6)
print(m[0] if m else "")' "$word" "$cands"
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
mj  -  look at, check and protect your After Effects and Cinema 4D work. It never changes your projects.

First time:
  mj setup                           choose your folders (takes a minute); then run the After Effects script once
  mj scraper                         show the After Effects script that makes a project report

Every day:
  mj check <project>                 is this project ready? expressions, fonts, footage, health score
  mj snapshot <project>              save a safe, verified copy of a project
  mj versions [project]              see the saved copies
  mj timeline <project>              the history of a project: what changed, when
  mj qc <movie> [spec]               check a render against a delivery spec (broadcast, web, social)
  mj space                           see what is filling your disk (caches); `mj space clean ...` empties one safely
  mj doctor                          is everything set up? shows what to fix

Fix and tidy (these work on a copy and never touch your original):
  mj extract <project> <comp> ...    keep just some comps, as a new project
  mj conform <project>               apply your studio naming, labels and folders (shows a plan first)
  mj ae run|verify <job>             send one of those jobs to After Effects / check the result

Look closer:
  mj lint [project]                  check expressions, in plain language
  mj health [project] [--record]     health score out of 100
  mj diff last                       what changed since the previous report
  mj scene / mj bridge               Cinema 4D scene checks, and Cinema 4D against an After Effects comp
  mj explain <file>                  turn any result file into plain language
  mj watch on|off|status             save a version automatically whenever a project is saved
  mj notify on|off                   a Mac notification when a long job finishes
  mj config                          show or change your folders and settings
  mj status | mj last | mj open-last | mj ui | mj batch ...

For scripts and pros:
  mj ops                             every operation and its arguments
  mj <operation> [name=value ...]    run one operation (prints JSON when not on a terminal)
  mj recipe <file> | mj batch <recipe> <folder>
  mj-man                             full help pages (mj-man list)
USAGE
            return 0 ;;
        ops)
            # Required arguments are marked with *.
            _mj_describe >/dev/null
            print -r -- "$_MJ_DESCRIBE" | /usr/bin/jq -r '.data.operations | to_entries[] | .value.args as $g
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
        check)
            shift
            local cks det=0 a ckt="last" ckd rc1 rc2 rc3
            for a in "$@"; do [ "$a" = --details ] && det=1 || ckt="$a"; done
            cks=$(_mj_scrape_for "$ckt") || return $?
            ckd=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mj-check.XXXXXX") || return 73
            local -a hargs; hargs=("path=$cks"); [ -d "$(mj_config_get versions_dir)" ] && hargs+=("input=$(mj_config_get versions_dir)")
            _mj_run expression.lint "path=$cks" > "$ckd/lint.json" &
            _mj_run project.health "${hargs[@]}" > "$ckd/health.json" &
            _mj_run project.preflight "path=$cks" > "$ckd/pre.json" &
            wait
            _mj_explain --check "$ckd/lint.json" "$ckd/health.json" "$ckd/pre.json"; rc1=$?
            if (( det )); then
                for a in lint pre health; do print; _mj_explain "$ckd/$a.json"; done
            fi
            /bin/rm -rf "$ckd"
            return $rc1 ;;
        extract)
            shift
            local ep="" eo="" el="" erun=0 a; local -a ecomps
            while [ $# -gt 0 ]; do
                case "$1" in
                    --label) [ $# -ge 2 ] || { print -u2 "mj: --label needs a value"; return 64; }; el="${2:-}"; shift 2 ;;
                    --out) [ $# -ge 2 ] || { print -u2 "mj: --out needs a value"; return 64; }; eo="${2:-}"; shift 2 ;;
                    --run) erun=1; shift ;;
                    *) if [ -z "$ep" ]; then ep="$1"; else ecomps+=("$1"); fi; shift ;;
                esac
            done
            [ -n "$ep" ] && [ ${#ecomps} -gt 0 ] || { print -u2 "usage: mj extract <project> <comp> [<comp> ...] [--label NAME] [--out FOLDER] [--run]"; return 64; }
            local eaep escr eids erc
            eaep=$(_mj_resolve_project "$ep") || return $?
            escr=$(_mj_scrape_for_aep "$eaep") || return $?
            eids=$(_mj_comp_ids "$escr" "${ecomps[@]}") || return $?
            [ -n "$eo" ] || eo=$(_mj_need_dir versions_dir versions) || return $?
            [ -n "$el" ] || el="${${${${eaep:t}%.[aA][eE][pP]}//[^A-Za-z0-9._-]/_}[1,40]}-extract-$(strftime %Y%m%d-%H%M%S $EPOCHSECONDS)"
            local eout; eout=$(_mj_run project.extract "path=$eaep" "input=$escr" "target=$eids" "output=${eo:A}" "label=$el"); erc=$?
            [ $erc -eq 0 ] || { print -r -- "$eout" | _mj_explain -; return $erc; }
            print -r -- "$eout" | _mj_explain -
            (( erun )) && { print; _mj_ae run "$(print -r -- "$eout" | /usr/bin/jq -r .data.job)"; }
            return 0 ;;
        conform)
            shift
            local cp="" cspec="" capply=0 crun=0 cl="" co=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --spec) [ $# -ge 2 ] || { print -u2 "mj: --spec needs a value"; return 64; }; cspec="${2:-}"; shift 2 ;;
                    --apply) capply=1; shift ;;
                    --run) capply=1; crun=1; shift ;;
                    --label) [ $# -ge 2 ] || { print -u2 "mj: --label needs a value"; return 64; }; cl="${2:-}"; shift 2 ;;
                    --out) [ $# -ge 2 ] || { print -u2 "mj: --out needs a value"; return 64; }; co="${2:-}"; shift 2 ;;
                    *) cp="$1"; shift ;;
                esac
            done
            [ -n "$cp" ] || { print -u2 "usage: mj conform <project> [--spec FILE] [--apply | --run] [--label NAME] [--out FOLDER]"; return 64; }
            [ -n "$cspec" ] || cspec=$(mj_config_get studio_spec)
            local caep cscr; local -a cargs
            caep=$(_mj_resolve_project "$cp") || return $?
            cscr=$(_mj_scrape_for_aep "$caep") || return $?
            cargs=("input=$cscr"); [ -n "$cspec" ] && cargs+=("spec=${cspec:A}")
            if (( capply )); then
                [ -n "$co" ] || co=$(_mj_need_dir versions_dir versions) || return $?
                [ -n "$cl" ] || cl="${${${${caep:t}%.[aA][eE][pP]}//[^A-Za-z0-9._-]/_}[1,40]}-conform-$(strftime %Y%m%d-%H%M%S $EPOCHSECONDS)"
                cargs+=(format=job "path=$caep" "output=${co:A}" "label=$cl")
            fi
            local cout crc; cout=$(_mj_run project.conform "${cargs[@]}"); crc=$?
            [ $crc -eq 0 ] || { print -r -- "$cout" | _mj_explain -; return $crc; }
            print -r -- "$cout" | _mj_explain -
            (( crun )) && [ "$(print -r -- "$cout" | /usr/bin/jq -r '.data.job.folder // empty')" != "" ] && { print; _mj_ae run "$(print -r -- "$cout" | /usr/bin/jq -r .data.job.folder)"; }
            return 0 ;;
        ae)
            shift; _mj_ae "$@"; return ;;
        qc)
            shift
            [ -n "${1:-}" ] || { print -u2 "usage: mj qc <movie> [spec]   (specs: broadcast-us broadcast-eu web social-vertical prores-master, or a spec file; default: the qc_spec setting, else web)"; return 64; }
            local qm="${1:A}" qs="${2:-$(mj_config_get qc_spec)}"
            [ -n "$qs" ] || qs=web
            local qout qrc
            if [ -f "$qs" ]; then qout=$(_mj_run media.qc "path=$qm" "input=${qs:A}"); else qout=$(_mj_run media.qc "path=$qm" "format=$qs"); fi
            qrc=$?
            print -r -- "$qout" | _mj_explain -
            (( qrc == 0 )) && [ "$(print -r -- "$qout" | /usr/bin/jq -r '.data.passed')" = false ] && return 1     # a failed check fails the command, so batches and scripts can gate on it
            return $qrc ;;
        space)
            shift
            case "${1:-}" in
                "") _mj_say cache.inspect; return ;;
                clean)
                    [ -n "${2:-}" ] || { print -u2 "usage: mj space clean <id>|leftovers [--yes]"; return 64; }
                    local sid="$2" syes=0 srs=0; local -a sids
                    [ "${3:-}" = --yes ] && syes=1
                    if [ "$sid" = leftovers ]; then
                        sids=(${(f)"$(_mj_run cache.inspect | /usr/bin/jq -r '.data.caches[]? | select(.leftOver and .cleanable and .bytes > 0) | .id')"})
                        [ ${#sids} -gt 0 ] || { print "Nothing left over from old versions."; return 0; }
                    else
                        sids=("$sid")
                    fi
                    for sid in "${sids[@]}"; do
                        if (( syes )); then _mj_say cache.clean "target=$sid" format=delete || srs=$?; else _mj_say cache.clean "target=$sid" || srs=$?; fi
                    done
                    return $srs ;;
                *) print -u2 "usage: mj space   |   mj space clean <id>|leftovers [--yes]"; return 64 ;;
            esac ;;
        timeline)
            shift
            [ -n "${1:-}" ] || { print -u2 "usage: mj timeline <project name> [--all]"; return 64; }
            local td tn tf prev="" i=0 max=10 vd tstem tname trd tout; local -a trs
            [ "${2:-}" = --all ] && max=50
            trd=$(_mj_need_dir receipts_dir receipts) || return $?
            tout=$(_mj_find "$trd" name "$1" $max 2>"${TMPDIR:-/tmp}/mj-find.$$"); i=$?
            if [ $i -eq 65 ]; then print -u2 "mj: \"$1\" matches more than one project; be more specific:"; /bin/cat "${TMPDIR:-/tmp}/mj-find.$$" >&2; /bin/rm -f "${TMPDIR:-/tmp}/mj-find.$$"; return 65; fi
            /bin/rm -f "${TMPDIR:-/tmp}/mj-find.$$"
            if [ $i -ne 0 ]; then print "Nothing recorded for \"$1\" yet. Run the MographJailed scraper on it in After Effects first."; return 0; fi
            trs=("${(@f)tout}"); i=0
            tname=$(/usr/bin/jq -r '.projectName // empty' "${trs[1]}" 2>/dev/null); tstem="${(L)tname%.[aA][eE][pP]}"
            td=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mj-timeline.XXXXXX") || return 73
            vd=$(mj_config_get versions_dir)
            for tf in "${(Oa)trs[@]}"; do     # oldest first; every report's health and diff run side by side
                tn=$(printf '%s/%03d' "$td" $i)
                /usr/bin/jq -c '{at: (.scrapedAt // ""), name: .projectName}' "$tf" > "$tn.scrape"
                if [ -d "$vd" ]; then _mj_run project.health "path=$tf" "input=$vd" > "$tn.health.json" & else _mj_run project.health "path=$tf" > "$tn.health.json" & fi
                [ -n "$prev" ] && { _mj_run project.diff "path=$prev" "input=$tf" > "$tn.diff.json" & }
                prev="$tf"; i=$((i + 1))
            done
            wait
            if [ -d "$vd" ]; then
                local sf sb; for sf in "$vd"/*.(aep|c4d)(.N); do sb=${${sf:t}%.<->T<->Z.*}; [[ "${(L)sb}" == "$tstem" ]] && print -r -- "$sf"; done > "$td/snapshots.txt"
            fi
            _mj_explain --timeline "$td"; i=$?
            /bin/rm -rf "$td"
            return $i ;;
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
        doctor) _mj_doctor; return ;;
        setup) shift; _mj_setup "$@"; return ;;
        scraper)
            local sp; sp=$(_mj_scraper_path); print "The After Effects script that makes a project report is here:"; print "  $sp"
            print "In After Effects: File > Scripts > Run Script File..., pick that file, and choose your reports folder: $(mj_config_get receipts_dir)"
            [ -t 1 ] && /usr/bin/open -R "$sp" 2>/dev/null; return 0 ;;
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
    case "$op" in
        *.*) ;;                                              # an operation name: handled below
        *) local near; near=$(_mj_suggest "$op")
           print -u2 "mj: \"$op\" is not a command.${near:+ Did you mean \"mj $near\"?}"
           print -u2 "  See the list with:  mj help"; return 64 ;;
    esac
    _mj_check_args "$@" || return
    local t0=$EPOCHREALTIME
    out=$(_mj_run "$op" "$@")
    rc=$?
    if [ $rc -ne 0 ] && [ -t 1 ]; then print -r -- "$out" | _mj_explain - ; else print -r -- "$out" | _mj_print; fi   # a failure on a terminal is explained; scripts still get JSON
    _mj_notify_op "$op" $(( EPOCHREALTIME - t0 )) "$out"
    return $rc
}

# Completion. First word: human commands and every operation. After a human command: what it
# takes (project files, "last", config keys, on/off ...). After an operation: its argument
# names (read from system.describe, so they never go stale), then file paths for values.
_mj_complete() {
    local -a items
    local json cmd="${words[2]}"
    local -a verbs; verbs=(snapshot versions lint health check timeline space qc extract conform ae setup scraper diff scene bridge explain watch doctor config notify status last open-last ui home cd ops recipe batch help)
    if (( CURRENT == 2 )); then
        json=$(_mj_describe) || json=""
        items=($verbs ${(f)"$(print -r -- "$json" | /usr/bin/jq -r '.data.operations | keys[]' 2>/dev/null)"})
        compadd -a items
        return
    fi
    case "$cmd" in
        snapshot) _files -g '*.(aep|AEP|c4d|C4D)' ;;
        check) items=(last --details); compadd -a items; _files ;;
        lint|explain|scene|bridge) items=(last); compadd -a items; _files ;;
        health) items=(last --record); compadd -a items; _files ;;
        diff) items=(last); compadd -a items; _files ;;
        watch) items=(on off status); compadd -a items ;;
        extract|conform) _files -g '*.(aep|AEP)' ;;
        ae) if (( CURRENT == 3 )); then items=(run verify); compadd -a items; else _files -/; fi ;;
        qc) if (( CURRENT == 3 )); then _files -g '*.(mov|mp4|m4v|MOV|MP4)'; else items=(broadcast-us broadcast-eu web social-vertical prores-master); compadd -a items; _files; fi ;;
        space) if (( CURRENT == 3 )); then items=(clean); compadd -a items; elif (( CURRENT == 4 )); then items=(leftovers ${(f)"$(_mj_run cache.inspect 2>/dev/null | /usr/bin/jq -r '.data.caches[]? | select(.cleanable) | .id')"}); compadd -a items; else items=(--yes); compadd -a items; fi ;;
        notify) items=(on off test status); compadd -a items ;;
        config)
            if (( CURRENT == 3 )); then items=(show path get set unset); compadd -a items
            elif [[ "${words[3]}" == (get|set|unset) ]] && (( CURRENT == 4 )); then items=(${=$(_mj_config_keys)}); compadd -a items
            elif [[ "${words[3]}" == set ]]; then _files; fi ;;
        ui) items=(--tab --once --plain); compadd -a items ;;
        versions) ;;
        recipe) _files ;;
        batch) if (( CURRENT == 3 )); then _files; elif (( CURRENT == 4 )); then _files -/; else items=(--pattern); compadd -a items; fi ;;
        last|open-last|home|cd|doctor|setup|scraper|status|ops|help) ;;
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
