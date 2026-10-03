#!/bin/zsh -f
# Remove MographJailed: the Terminal startup block, the watcher, and the install folder.
#
#   zsh -f uninstall-local.zsh <install folder>
#
# Your projects, your saved versions and your project reports are never touched. The settings file and the
# private index are removed only if you say yes. Environment: MJ_YES=1 (never ask; keeps settings), MJ_ZSHRC.
emulate -R zsh
set -u
ROOT="${1:-}"; YES="${MJ_YES:-0}"; RC="${MJ_ZSHRC:-$HOME/.zshrc}"
B="# >>> MographJailed (added by the installer; the uninstaller removes exactly this block) >>>"
E="# <<< MographJailed <<<"
say()  { /bin/echo ""; /bin/echo "$*"; }
ok()   { /bin/echo "   ✓ $*"; }
die()  { /bin/echo ""; /bin/echo "   ✗ $*"; /bin/echo ""; exit 1; }
ask_yes() { local a=""; if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then [ "$2" = y ]; return; fi; /bin/echo -n "   $1 [$2]: " >&2; { IFS= read -r a < /dev/tty; } 2>/dev/null || a=""; [ -n "$a" ] || a="$2"; case "$a" in y|Y|yes) return 0 ;; *) return 1 ;; esac; }
case "$ROOT" in /*) ;; *) die "usage: uninstall-local.zsh <install folder> (a full path)" ;; esac
ROOT="${ROOT%/}"
[ -f "$ROOT/dist/mograph-jailed.zsh" ] || die "$ROOT does not look like a MographJailed install - nothing removed."

say "Removing MographJailed from $ROOT"
if [ -f "$RC" ] && /usr/bin/grep -qxF "$B" "$RC"; then
  BK="$RC.mj-backup-$(/bin/date +%Y%m%d-%H%M%S)"; /bin/cp "$RC" "$BK" && ok "backed up $RC to $BK"
  T=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mj-zshrc.XXXXXX") && /usr/bin/awk -v b="$B" -v e="$E" '$0==b{skip=1;next} $0==e{skip=0;next} !skip{print}' "$RC" > "$T" && /bin/cat "$T" > "$RC" && /bin/rm -f "$T"
  ok "removed the MographJailed lines from $RC"
else ok "nothing to remove from $RC"; fi
if [ -f "$ROOT/tools/watch-uninstall.zsh" ]; then /bin/zsh -f "$ROOT/tools/watch-uninstall.zsh" --yes >/dev/null 2>&1 && ok "automatic versioning turned off"; fi
/bin/rm -rf "$ROOT" && ok "removed $ROOT"
CFG="$HOME/.config/mograph-jailed"; STORE="${MJ_STORE_DIR:-$HOME/Library/Application Support/MographJailed}"
if [ -e "$CFG" ] || [ -e "$STORE" ]; then
  if ask_yes "Also remove your MographJailed settings and search index? (your projects, versions and reports stay)" n; then
    /bin/rm -rf "$CFG" "$STORE"; ok "removed settings and index"
  else ok "kept your settings and index (a later install picks them up)"; fi
fi
/bin/echo ""
/bin/echo "   Your projects, saved versions and project reports were not touched."
/bin/echo "   Open a new Terminal window for the change to take effect."
/bin/echo ""
