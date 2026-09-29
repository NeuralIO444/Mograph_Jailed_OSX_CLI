#!/bin/zsh -f
# Uninstall the MographJailed Tier 0 watcher.
#
# Unloads the LaunchAgent for the current user and removes its plist from
# ~/Library/LaunchAgents. Never touches the versions dir or any snapshots.
#
# Usage: watch-uninstall.zsh [--yes]

emulate -R zsh
set -u

LABEL="com.neuralio.mograph-jailed.watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

YES=0
if [[ "${1:-}" == "--yes" ]]; then
    YES=1
fi

uid=$(id -u)

if (( ! YES )); then
    print -r "This will unload $LABEL and remove:"
    print -r "  $PLIST"
    print -r "Your versions dir and snapshots will NOT be touched."
    print -rn "Proceed? [y/N] "
    read -r ans
    if [[ "$ans" != [yY] ]]; then
        print -r "aborted."
        exit 1
    fi
fi

# bootout (modern) with unload -w fallback (legacy).
launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 \
    || launchctl unload -w "$PLIST" >/dev/null 2>&1 \
    || true

if [[ -f "$PLIST" ]]; then
    rm -f "$PLIST" && print -r "removed $PLIST"
else
    print -r "no plist at $PLIST (already gone)"
fi

if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    print -r "warning: agent still listed by launchctl; it may need a logout to fully clear." >&2
else
    print -r "watcher uninstalled."
fi
