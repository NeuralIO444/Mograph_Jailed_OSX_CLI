# MographJailed snapshot dashboard wrapper.
# Runs the dashboard in a clean child zsh so macOS Terminal session-exit hooks
# from the interactive parent shell are not inherited by the dashboard worker.
if ! typeset -f _mj_root >/dev/null 2>&1; then
    _mj_common="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}/scripts/shell/mj-terminal.zsh"
    [ -r "$_mj_common" ] && source "$_mj_common"
    unset _mj_common
fi

mj-top() {
    local root runner
    root=$(_mj_root) || return 1
    runner="$root/scripts/terminal/mj-top-run.zsh"
    [ -r "$runner" ] || { /bin/echo "MJ dashboard runner not found: $runner" >&2; return 66; }
    /bin/zsh -f "$runner" "$@"
}
