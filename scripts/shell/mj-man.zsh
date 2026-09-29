# MographJailed local terminal help v2. No system-wide man installation.
if ! typeset -f _mj_root >/dev/null 2>&1; then
    _mj_common="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/scripts/shell/mj-terminal.zsh"
    [ -r "$_mj_common" ] && source "$_mj_common"
    unset _mj_common
fi

mj-man() {
    local root
    local manroot
    local topic="${1:-overview}"
    local file=""
    local renderer
    local color=0
    root=$(_mj_root)
    manroot="$root/docs/man"
    renderer="$root/scripts/terminal/mj-md-render.awk"

    case "$topic" in
        help|overview) file="$manroot/overview.md" ;;
        commands|command) file="$manroot/commands.md" ;;
        protocol) file="$manroot/protocol.md" ;;
        safety|security) file="$manroot/safety.md" ;;
        looper) file="$manroot/looper.md" ;;
        organize|organise) file="$manroot/organize.md" ;;
        terminal|top) file="$manroot/terminal.md" ;;
        troubleshooting|trouble|debug) file="$manroot/troubleshooting.md" ;;
        recovery|rollback) file="$manroot/recovery.md" ;;
        list)
            /bin/cat <<'LIST'
MographJailed help topics
-----------------------
overview
commands
protocol
safety
looper
organize
terminal
troubleshooting
recovery
LIST
            return 0
            ;;
        *)
            /bin/echo "Unknown MJ help topic: $topic" >&2
            /bin/echo "Run: mj-man list" >&2
            return 64
            ;;
    esac

    [ -r "$file" ] || { /bin/echo "MJ help file not found: $file" >&2; return 66; }
    [ -r "$renderer" ] || { /bin/echo "MJ help renderer not found: $renderer" >&2; return 66; }
    _mj_color_enabled && color=1

    if [ -t 1 ] && [ -x /usr/bin/less ]; then
        /usr/bin/awk -v color="$color" -f "$renderer" "$file" | /usr/bin/less -R
    else
        /usr/bin/awk -v color=0 -f "$renderer" "$file"
    fi
}
