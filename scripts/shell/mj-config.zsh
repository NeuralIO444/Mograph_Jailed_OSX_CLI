# MographJailed settings: one small file, set once, remembered by every tool.
#
#   file:  ${MJ_CONFIG:-~/.config/mograph-jailed/config}     key=value lines, # comments
#   keys:  versions_dir  receipts_dir  watch_dir  cli  post_snapshot_hook  qc_spec  studio_spec
#   env:   MJ_VERSIONS_DIR MJ_RECEIPTS_DIR MJ_WATCH_DIR MJ_CLI MJ_POST_SNAPSHOT_HOOK MJ_QC_SPEC MJ_STUDIO_SPEC  (win over the file)
#
# Precedence everywhere: command-line flag > environment > config file > built-in default.
# The file is parsed, never sourced, so a setting can never run code. Safe to source; it
# performs no work at source time.

_mj_config_file() { print -r -- "${MJ_CONFIG:-$HOME/.config/mograph-jailed/config}"; }

_mj_config_keys() { print -r -- "versions_dir receipts_dir watch_dir cli post_snapshot_hook qc_spec studio_spec"; }

_mj_config_env_name() {
    case "$1" in
        versions_dir) print -r -- MJ_VERSIONS_DIR ;;
        receipts_dir) print -r -- MJ_RECEIPTS_DIR ;;
        watch_dir) print -r -- MJ_WATCH_DIR ;;
        cli) print -r -- MJ_CLI ;;
        post_snapshot_hook) print -r -- MJ_POST_SNAPSHOT_HOOK ;;
        qc_spec) print -r -- MJ_QC_SPEC ;;
        studio_spec) print -r -- MJ_STUDIO_SPEC ;;
        *) return 1 ;;
    esac
}

_mj_config_default() {
    case "$1" in
        cli) print -r -- "${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/dist/mograph-jailed.zsh" ;;
        versions_dir) print -r -- "$HOME/AE_Versions" ;;
        receipts_dir) print -r -- "$HOME/AE_Receipts" ;;
        *) print -r -- "" ;;
    esac
}

# Value from the file only (last assignment wins). Prints nothing if unset.
_mj_config_file_value() {
    setopt localoptions extendedglob      # the [[:space:]]# trim below needs it; scripts run under zsh -f
    local f key="$1" line k v val=""
    f=$(_mj_config_file)
    [ -r "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        k=${line%%=*}; v=${line#*=}
        k=${k//[[:space:]]/}
        v=${v##[[:space:]]#}; v=${v%%[[:space:]]#}      # trim both ends (a CRLF file leaves a CR)
        [ "$k" = "$key" ] && val="$v"
    done < "$f"
    print -r -- "$val"
}

# Effective value and where it came from: prints "value<TAB>source" (env|file|default|unset).
_mj_config_resolve() {
    local key="$1" envn val
    envn=$(_mj_config_env_name "$key") || return 1
    val="${(P)envn:-}"
    if [ -n "$val" ]; then print -r -- "$val	env"; return 0; fi
    val=$(_mj_config_file_value "$key")
    if [ -n "$val" ]; then print -r -- "$val	file"; return 0; fi
    val=$(_mj_config_default "$key")
    if [ -n "$val" ]; then print -r -- "$val	default"; else print -r -- "	unset"; fi
}

mj_config_get() { local r; r=$(_mj_config_resolve "$1") || return 1; print -r -- "${r%%	*}"; }

# Validate and normalise a value for a key. Prints the value; returns non-zero with a message on stderr.
_mj_config_check() {
    local key="$1" val="$2"
    case "$val" in *$'\n'*|*$'\r'*) print -u2 "mj: a setting cannot contain a line break"; return 1 ;; esac
    case "$val" in "~"*) val="$HOME${val#\~}" ;; esac
    case "$key" in
        versions_dir|receipts_dir|watch_dir|cli|post_snapshot_hook|studio_spec)
            case "$val" in /*) ;; *) print -u2 "mj: $key must be a full path starting with / (got: $val)"; return 1 ;; esac ;;
        qc_spec)
            case "$val" in /*|broadcast-us|broadcast-eu|web|social-vertical|prores-master) ;; *) print -u2 "mj: qc_spec must be a built-in spec (broadcast-us broadcast-eu web social-vertical prores-master) or a full path to a spec file"; return 1 ;; esac ;;
    esac
    print -r -- "$val"
}

mj_config_set() {
    local key="$1" val f tmp line
    case " $(_mj_config_keys) " in *" $key "*) ;; *) print -u2 "mj: unknown setting '$key' (known: $(_mj_config_keys))"; return 64 ;; esac
    val=$(_mj_config_check "$key" "${2:-}") || return 64
    f=$(_mj_config_file)
    /bin/mkdir -p "${f:h}" || return 73
    tmp=$(/usr/bin/mktemp "${f}.XXXXXX") || return 73
    {
        [ -r "$f" ] && while IFS= read -r line || [ -n "$line" ]; do
            [ "${${line%%=*}//[[:space:]]/}" = "$key" ] || print -r -- "$line"
        done < "$f"
        print -r -- "$key=$val"
    } > "$tmp" && /bin/mv "$tmp" "$f" || { /bin/rm -f "$tmp"; return 73; }
}

mj_config_unset() {
    local key="$1" f tmp line
    f=$(_mj_config_file)
    [ -r "$f" ] || return 0
    tmp=$(/usr/bin/mktemp "${f}.XXXXXX") || return 73
    while IFS= read -r line || [ -n "$line" ]; do
        [ "${${line%%=*}//[[:space:]]/}" = "$key" ] || print -r -- "$line"
    done < "$f" > "$tmp" && /bin/mv "$tmp" "$f" || { /bin/rm -f "$tmp"; return 73; }
}

mj_config_show() {
    local key r val src
    print -r -- "config file: $(_mj_config_file)$([ -r "$(_mj_config_file)" ] || print '  (not created yet)')"
    for key in ${=$(_mj_config_keys)}; do
        r=$(_mj_config_resolve "$key"); val=${r%%	*}; src=${r##*	}
        printf '  %-20s %-9s %s\n' "$key" "($src)" "${val:--}"
    done
}
