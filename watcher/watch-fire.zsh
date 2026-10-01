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
find "$STAGE_DIR" -maxdepth 1 \( -name 'req-*.txt' -o -name 'req.*' \) -mtime +1 -delete 2>/dev/null

epoch=$(date +%s)

# --- optional user hook (post_snapshot_hook in the config file, or MJ_POST_SNAPSHOT_HOOK) ---
# Runs after a NEW snapshot is safely saved, with the receipt path as its argument. It is the
# user's own script, so it is held to the same rules as anything that runs unattended: an
# absolute path, a regular file owned by this user and executable, not writable by anyone else;
# run directly (no shell), stdin closed, output to hook.log, killed after a timeout. A hook can
# never fail or delay a snapshot: every problem is logged and the watcher carries on.
CONFIG_FILE="${MJ_CONFIG:-$HOME/.config/mograph-jailed/config}"
HOOK="${MJ_POST_SNAPSHOT_HOOK:-}"
if [[ -z "$HOOK" && -r "$CONFIG_FILE" ]]; then
    # Same reading rules as mj-config.zsh: trim whitespace (including a CR from CRLF files) at both ends.
    HOOK=$(sed -n 's/^[[:space:]]*post_snapshot_hook[[:space:]]*=//p' "$CONFIG_FILE" | tail -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
fi
HOOK_TIMEOUT="${MJ_HOOK_TIMEOUT:-30}"
HOOK_LOG="$VERSIONS_DIR/hook.log"
zmodload zsh/stat 2>/dev/null

run_hook() {   # run_hook <receipt> <snapshot> <source> <sha256>
    [[ -n "$HOOK" ]] || return 0
    local real="${HOOK:A}" uid mode why="" me d
    me=$(id -u)
    if [[ "$HOOK" != /* ]]; then why="path is not absolute"
    elif [[ ! -f "$real" ]]; then why="not a file"
    elif [[ ! -x "$real" ]]; then why="not executable"
    else
        uid=$(zstat +uid "$real" 2>/dev/null); mode=$(zstat +mode "$real" 2>/dev/null)
        if [[ "$uid" != "$me" ]]; then why="not owned by you"
        elif (( mode & 8#022 )); then why="writable by others"
        else
            # Every folder above the script must also be safe: someone who can write a folder on the
            # path can swap the script. Each must belong to you or root and not be writable by group
            # or others (a sticky bit, as on /tmp, stops others replacing your files, so it is allowed).
            d="${real:h}"
            while true; do
                uid=$(zstat +uid "$d" 2>/dev/null); mode=$(zstat +mode "$d" 2>/dev/null)
                if [[ "$uid" != "$me" && "$uid" != 0 ]]; then why="a folder above it is owned by someone else ($d)"; break; fi
                if (( mode & 8#022 )) && ! (( mode & 8#1000 )); then why="a folder above it is writable by others ($d)"; break; fi
                [[ "$d" == "/" ]] && break
                d="${d:h}"
            done
        fi
    fi
    if [[ -n "$why" ]]; then
        print -r "$(date '+%F %T') hook refused ($why): $HOOK" >> "$LOG_FILE"
        return 0
    fi
    print -r "$(date '+%F %T') --- $HOOK $1" >> "$HOOK_LOG"
    # The hook gets its own process group (perl's setpgrp), so a timeout can stop everything it
    # started, grandchildren included, not just the script itself.
    local pgrp=0
    local -a runner
    if [[ -x /usr/bin/perl ]]; then runner=(/usr/bin/perl -e 'setpgrp(0,0); exec { $ARGV[0] } @ARGV'); pgrp=1; else runner=(); fi
    ( MJ_SNAPSHOT_RECEIPT="$1" MJ_SNAPSHOT_PATH="$2" MJ_SOURCE_PATH="$3" MJ_SNAPSHOT_SHA256="$4" \
        exec "${runner[@]}" "$real" "$1" </dev/null >> "$HOOK_LOG" 2>&1 ) &
    local pid=$! waited=0 rc
    while kill -0 "$pid" 2>/dev/null; do
        if (( waited >= HOOK_TIMEOUT )); then
            if (( pgrp )); then kill -TERM -- "-$pid" 2>/dev/null; else /usr/bin/pkill -TERM -P "$pid" 2>/dev/null; fi
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            if (( pgrp )); then kill -KILL -- "-$pid" 2>/dev/null; else /usr/bin/pkill -KILL -P "$pid" 2>/dev/null; fi
            kill -KILL "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            print -r "$(date '+%F %T') hook timed out after ${HOOK_TIMEOUT}s (stopped): $HOOK" >> "$LOG_FILE"
            return 0
        fi
        sleep 1; waited=$((waited + 1))
    done
    wait "$pid"; rc=$?
    if (( rc == 0 )); then
        print -r "$(date '+%F %T') hook ok: ${HOOK:t}" >> "$LOG_FILE"
    else
        print -r "$(date '+%F %T') hook FAILED (exit $rc) (snapshot is safe): ${HOOK:t}" >> "$LOG_FILE"
    fi
    return 0
}

if [[ ! -d "$WATCH_DIR" ]]; then
    print -r "$(date '+%F %T') watch dir missing, nothing to do: $WATCH_DIR" >> "$LOG_FILE"
    exit 0
fi

n=0
# -iname: Windows-originated projects are often Foo.AEP.
find "$WATCH_DIR" -maxdepth 2 -type f -iname '*.aep' -print 2>/dev/null | while IFS= read -r aep; do
    [[ -n "$aep" ]] || continue
    n=$((n + 1))
    # mktemp gives every request its own file, so overlapping launchd runs cannot collide.
    req=$(/usr/bin/mktemp "$STAGE_DIR/req.XXXXXX") || { print -r "$(date '+%F %T') snapshot FAILED (NO_STAGE_FILE) (continuing): $aep" >> "$LOG_FILE"; continue; }
    b64path=$(printf '%s' "$aep" | /usr/bin/base64 | tr -d '\n')
    b64out=$(printf '%s' "$VERSIONS_DIR" | /usr/bin/base64 | tr -d '\n')
    {
        print -r "MOGRAPHJAILED_REQUEST 1"
        print -r "requestId=watcher-$epoch-$$-$n"
        print -r "command=project.snapshot"
        print -r "arg.path=$b64path"
        print -r "arg.output=$b64out"
    } > "$req"
    out=$("$CLI_PATH" --request "$req" 2>&1)
    rc=$?
    # Read the receipt so the log says what actually happened, not just pass/fail.
    code=$(print -r -- "$out" | /usr/bin/jq -r '.error.code // empty' 2>/dev/null)
    created=$(print -r -- "$out" | /usr/bin/jq -r 'if .data.snapshotCreated == null then empty else (.data.snapshotCreated | tostring) end' 2>/dev/null)
    if [[ "$rc" -eq 0 && "$created" == "false" ]]; then
        print -r "$(date '+%F %T') unchanged, skipped: $aep" >> "$LOG_FILE"
    elif [[ "$rc" -eq 0 ]]; then
        print -r "$(date '+%F %T') snapshot ok: $aep" >> "$LOG_FILE"
        run_hook "$(print -r -- "$out" | /usr/bin/jq -r '.data.receiptPath // empty' 2>/dev/null)" \
                 "$(print -r -- "$out" | /usr/bin/jq -r '.data.snapshotPath // empty' 2>/dev/null)" \
                 "$aep" "$(print -r -- "$out" | /usr/bin/jq -r '.data.sha256 // empty' 2>/dev/null)"
    elif [[ "$code" == "OUTPUT_EXISTS" ]]; then
        print -r "$(date '+%F %T') already saved by a concurrent run: $aep" >> "$LOG_FILE"
    elif [[ "$code" == "SNAPSHOT_UNSTABLE" ]]; then
        print -r "$(date '+%F %T') busy, project was changing (will retry on the next save): $aep" >> "$LOG_FILE"
    else
        print -r "$(date '+%F %T') snapshot FAILED (${code:-exit $rc}) (continuing): $aep" >> "$LOG_FILE"
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
