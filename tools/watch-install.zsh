#!/bin/zsh -f
# Install the MographJailed Tier 0 watcher.
#
# Renders watcher/com.neuralio.mograph-jailed.watcher.plist and
# watcher/watch-fire.zsh into <versions-dir>/.watcher/, copies the plist
# into the user's own ~/Library/LaunchAgents (never /Library, never sudo),
# and loads it for the current user.
#
# The watcher may ONLY trigger Tier 0 (observe) operations. It runs as the
# installing user, with that user's permissions, and is visible/killable in
# System Settings > General > Login Items ("Background Items").
#
# Usage: watch-install.zsh [--yes] <watch-dir> <versions-dir>

emulate -R zsh
set -u

LABEL="com.neuralio.mograph-jailed.watcher"

usage() {
    print -r "usage: watch-install.zsh [--yes] <watch-dir> <versions-dir>" >&2
    exit 2
}

YES=0
if [[ "${1:-}" == "--yes" ]]; then
    YES=1
    shift
fi
[[ $# -eq 2 ]] || usage

WATCH_DIR=${1:A}
VERSIONS_DIR=${2:A}

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
CLI_PATH="$ROOT/dist/mograph-jailed.zsh"
TPL_PLIST="$ROOT/watcher/com.neuralio.mograph-jailed.watcher.plist"
TPL_FIRE="$ROOT/watcher/watch-fire.zsh"
STAGE_DIR="$VERSIONS_DIR/.watcher"
FIRE_SCRIPT="$STAGE_DIR/watch-fire.zsh"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

# ---- validation (before touching anything) ----
[[ -x "$CLI_PATH" ]] || { print -r "error: CLI not found at $CLI_PATH" >&2; exit 1; }
[[ -f "$TPL_PLIST" ]] || { print -r "error: missing template $TPL_PLIST" >&2; exit 1; }
[[ -f "$TPL_FIRE" ]] || { print -r "error: missing template $TPL_FIRE" >&2; exit 1; }
[[ -d "$WATCH_DIR" ]] || { print -r "error: watch dir does not exist: $WATCH_DIR" >&2; exit 1; }
[[ -r "$WATCH_DIR" ]] || { print -r "error: watch dir not readable: $WATCH_DIR" >&2; exit 1; }
mkdir -p "$VERSIONS_DIR" 2>/dev/null || { print -r "error: cannot create versions dir: $VERSIONS_DIR" >&2; exit 1; }
mkdir -p "$STAGE_DIR" "$HOME/Library/LaunchAgents" 2>/dev/null || {
    print -r "error: cannot create staging dirs" >&2; exit 1
}

uid=$(id -u)

# ---- plan ----
print -r "MographJailed Tier 0 watcher install plan:"
print -r "  label:        $LABEL"
print -r "  watch dir:    $WATCH_DIR"
print -r "  versions dir: $VERSIONS_DIR"
print -r "  CLI:          $CLI_PATH"
print -r "  plist:        $PLIST_DEST"
print -r "  fire script:  $FIRE_SCRIPT"
print -r ""
print -r "This will:"
print -r "  - copy a LaunchAgent plist into your own ~/Library/LaunchAgents (no sudo, no /Library)"
print -r "  - load it for your user only (gui/$uid)"
print -r "  - on .aep changes under the watch dir, fire Tier 0 project.snapshot requests"
print -r "It will NOT: run as root, use the network, modify any .aep, or trigger renders/builds."

if (( ! YES )); then
    print -rn "Proceed? [y/N] "
    read -r ans
    if [[ "$ans" != [yY] ]]; then
        print -r "aborted."
        exit 1
    fi
fi

# ---- render templates ----
render_template() {
    local src=$1
    local s
    s=$(<"$src")
    s=${s//__WATCH_DIR__/$WATCH_DIR}
    s=${s//__VERSIONS_DIR__/$VERSIONS_DIR}
    s=${s//__CLI_PATH__/$CLI_PATH}
    s=${s//__FIRE_SCRIPT__/$FIRE_SCRIPT}
    print -r -- "$s"
}

render_template "$TPL_PLIST" > "$STAGE_DIR/$LABEL.plist" || {
    print -r "error: failed to render plist template" >&2; exit 1
}
render_template "$TPL_FIRE" > "$FIRE_SCRIPT" || {
    print -r "error: failed to render fire script template" >&2; exit 1
}
chmod +x "$FIRE_SCRIPT"

cp "$STAGE_DIR/$LABEL.plist" "$PLIST_DEST" || {
    print -r "error: cannot write $PLIST_DEST" >&2; exit 1
}

# ---- (re)load: bootout any stale copy first, ignore its failure ----
launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1

errlog=$(mktemp)
if launchctl bootstrap "gui/$uid" "$PLIST_DEST" 2>"$errlog"; then
    loaded=1
elif launchctl load "$PLIST_DEST" 2>"$errlog"; then
    loaded=1
else
    print -r "error: could not load the LaunchAgent." >&2
    print -r "launchctl said:" >&2
    cat "$errlog" >&2
    print -r "" >&2
    print -r "On managed Macs this usually means MDM blocks background items." >&2
    print -r "The plist is staged at $PLIST_DEST but is NOT running." >&2
    rm -f "$errlog"
    exit 1
fi
rm -f "$errlog"

if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    print -r "watcher installed and running ($LABEL)."
else
    print -r "warning: loaded but not visible via launchctl print; check Console for errors." >&2
fi
print -r "Log: $VERSIONS_DIR/watcher.log"
print -r "Uninstall: $ROOT/tools/watch-uninstall.zsh"
