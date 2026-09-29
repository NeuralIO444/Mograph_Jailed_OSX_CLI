#!/bin/zsh -f
# MographJailed Tier 0 watcher fire script.
#
# This is a TEMPLATE: tools/watch-install.zsh substitutes the __PLACEHOLDERS__
# and writes the rendered copy next to the versions dir. Never hand-edit the
# rendered copy; re-run watch-install.zsh instead.
#
# On every launchd WatchPaths trigger, scans for *.aep files (max 2 levels
# under the watch dir) and fires one project.snapshot request per file.
# Tier 0 only: the watcher may never trigger renders, builds, or any
# Tier 1 operation. Per-file failures are logged and skipped (continue).

emulate -R zsh
set -u

WATCH_DIR="__WATCH_DIR__"
VERSIONS_DIR="__VERSIONS_DIR__"
CLI_PATH="__CLI_PATH__"
LOG_FILE="$VERSIONS_DIR/watcher.log"
STAGE_DIR="$VERSIONS_DIR/.watcher"

mkdir -p "$STAGE_DIR" 2>/dev/null
mkdir -p "$VERSIONS_DIR" 2>/dev/null

# Hygiene: drop stale staged requests (older than a day) so the stage dir
# cannot grow without bound across triggers.
find "$STAGE_DIR" -maxdepth 1 -name 'req-*.txt' -mtime +1 -delete 2>/dev/null

epoch=$(date +%s)

if [[ ! -d "$WATCH_DIR" ]]; then
    print -r "$(date '+%F %T') watch dir missing, nothing to do: $WATCH_DIR" >> "$LOG_FILE"
    exit 0
fi

n=0
find "$WATCH_DIR" -maxdepth 2 -type f -name '*.aep' -print 2>/dev/null | while IFS= read -r aep; do
    [[ -n "$aep" ]] || continue
    n=$((n + 1))
    req="$STAGE_DIR/req-$epoch-$n.txt"
    b64path=$(printf '%s' "$aep" | /usr/bin/base64 | tr -d '\n')
    b64out=$(printf '%s' "$VERSIONS_DIR" | /usr/bin/base64 | tr -d '\n')
    {
        print -r "MOGRAPHJAILED_REQUEST 1"
        print -r "requestId=watcher-$epoch-$n"
        print -r "command=project.snapshot"
        print -r "arg.path=$b64path"
        print -r "arg.output=$b64out"
    } > "$req"
    if "$CLI_PATH" --request "$req" >/dev/null 2>&1; then
        print -r "$(date '+%F %T') snapshot ok: $aep" >> "$LOG_FILE"
    else
        print -r "$(date '+%F %T') snapshot FAILED (continuing): $aep" >> "$LOG_FILE"
    fi
    /bin/rm -f "$req" 2>/dev/null
done

# Cap the log: keep the tail so a busy project folder cannot fill the disk.
if [[ -f "$LOG_FILE" ]]; then
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [[ "$lines" -gt 2000 ]]; then
        tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

exit 0
