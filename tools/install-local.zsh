#!/bin/zsh -f
# MographJailed install core: put a downloaded, unpacked copy into its home and connect it to Terminal.
#
#   zsh -f install-local.zsh <unpacked folder> <install folder>
#
# Used by "Install MographJailed.command" (from the release zip) and by install-designer.zsh (from the web).
# No sudo, nothing outside your home folder, no network. The steps, in order:
#   1. verify  - every file matches SHA256SUMS and nothing extra is present (when the list is shipped)
#   2. stage   - copy to <install folder>.installing (tests, research and CI files are left out)
#   3. test    - run the staged copy's first command before touching anything that exists
#   4. swap    - move the old install aside, put the new one in place; a MographJailed folder is removed once
#                the new one runs, any other folder is kept as <install folder>.previous
#   5. connect - one marked block in ~/.zshrc (backed up first) that loads the `mj` command
#   6. setup   - `mj setup` chooses your folders
# Environment: MJ_YES=1 (never ask), MJ_INSTALL_ZSHRC=1|0 (default: ask; 0 when MJ_YES), MJ_ZSHRC=<file>,
#              MJ_INSTALL_SETUP=1|0 (default: ask; 0 when MJ_YES), MJ_INSTALL_ALLOW_NONMAC=1 (tests).

emulate -R zsh
set -u
SRC="${1:-}"; ROOT="${2:-}"
YES="${MJ_YES:-${MJ_INSTALL_YES:-0}}"
RC="${MJ_ZSHRC:-$HOME/.zshrc}"
B="# >>> MographJailed (added by the installer; the uninstaller removes exactly this block) >>>"
E="# <<< MographJailed <<<"

say()  { /bin/echo ""; /bin/echo "$*"; }
step() { /bin/echo ""; /bin/echo "── $*"; }
ok()   { /bin/echo "   ✓ $*"; }
warn() { /bin/echo "   ! $*"; }
die()  { /bin/echo ""; /bin/echo "   ✗ $*"; /bin/echo ""; exit 1; }
# State of the MographJailed block in a shell startup file: none (no markers), ok (complete, in order, never nested) or bad
# (a lone opening or closing marker, reversed, or nested). Only "ok" blocks are ever removed; anything else is left alone.
block_state() {
  [ -f "$1" ] || { /bin/echo none; return; }
  /usr/bin/awk -v b="$B" -v e="$E" 'BEGIN{st=0;n=0;bad=0} $0==b{if(st==1)bad=1; st=1; n++; next} $0==e{if(st==0)bad=1; st=0; n++; next} END{if(bad||st==1)print "bad"; else if(n==0)print "none"; else print "ok"}' "$1"
}

ask_yes() {   # ask_yes <question> <default y|n>
  local ans=""
  if [ "$YES" = 1 ]; then [ "$2" = y ]; return; fi
  if [ ! -r /dev/tty ]; then [ "$2" = y ]; return; fi
  /bin/echo -n "   $1 [$2]: " >&2
  { IFS= read -r ans < /dev/tty; } 2>/dev/null || ans=""
  [ -n "$ans" ] || ans="$2"
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

[ -n "$SRC" ] && [ -n "$ROOT" ] || die "usage: install-local.zsh <unpacked folder> <install folder>"
SRC="${SRC:A}"
case "$ROOT" in "~"*) ROOT="$HOME${ROOT#\~}" ;; esac
case "$ROOT" in /*) ;; *) die "The install folder must be a full path starting with / (got: $ROOT)" ;; esac
case "$ROOT" in *[\"\\\$\`]*|*$'\n'*) die "The install folder name contains a character that cannot be used safely in a shell startup file (quotes, backslash, \$, backtick). Choose another folder." ;; esac
ROOT="${ROOT%/}"
[ "$ROOT" != "$HOME" ] && [ "$ROOT" != "/" ] && [ "$ROOT" != "$SRC" ] || die "Please choose a folder of its own, not $ROOT."
[ -f "$SRC/dist/mograph-jailed.zsh" ] || die "The download looks wrong (no dist/mograph-jailed.zsh) - nothing installed."
if [ "$(/usr/bin/uname -s)" != "Darwin" ] && [ "${MJ_INSTALL_ALLOW_NONMAC:-}" != "1" ]; then die "This installer needs a Mac."; fi

# ---- 1. verify
step "Checking the files"
if [ "${MJ_INSTALL_VERIFIED:-0}" = 1 ]; then
  ok "files were already checked against their checksums"
elif [ -f "$SRC/SHA256SUMS" ]; then
  BAD=$(cd "$SRC" && /usr/bin/shasum -a 256 -c SHA256SUMS 2>&1 | /usr/bin/grep -v ': OK$' | /usr/bin/head -5)
  [ -z "$BAD" ] || die "Some files do not match their checksums - nothing installed. ($(/bin/echo "$BAD" | /usr/bin/head -1))"
  # shasum -c only checks the files the list names; an extra file would ride along unchecked.
  # Finder and Archive Utility may add .DS_Store and ._name files (resource-fork shadows); they hold no code and are not copied.
  PRESENT=$(cd "$SRC" && /usr/bin/find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig ! -name .DS_Store ! -name '._*' | /usr/bin/sed 's|^\./||' | LC_ALL=C /usr/bin/sort)
  LISTED=$(/usr/bin/sed 's/^[0-9a-f]*  //' "$SRC/SHA256SUMS" | LC_ALL=C /usr/bin/sort)
  EXTRA=$(LC_ALL=C /usr/bin/comm -23 <(/bin/echo "$PRESENT") <(/bin/echo "$LISTED") | /usr/bin/head -3)
  [ -z "$EXTRA" ] || die "There are files that are not in the checksum list - nothing installed. (for example $(/bin/echo "$EXTRA" | /usr/bin/head -1))"
  ok "every file matches its checksum, and nothing extra is included"
else
  warn "no checksum list in this download (older release); file check skipped"
fi

# ---- 2. stage
step "Preparing the new copy"
STAGE="$ROOT.installing.$$"
/bin/rm -rf "$STAGE"
/bin/mkdir -p "$(/usr/bin/dirname "$ROOT")" "$STAGE" || die "Cannot create $STAGE."
trap '/bin/rm -rf "$STAGE"' EXIT
(cd "$SRC" && /usr/bin/tar -cf - --exclude=./tests --exclude=./research --exclude=./.github --exclude=./.git --exclude=./.gitignore --exclude=.DS_Store --exclude='._*' --exclude=__MACOSX .) \
  | (cd "$STAGE" && /usr/bin/tar -xf -) || die "Copy failed."
/usr/bin/xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null     # your own copy of files you chose to install; no sudo needed
ok "copied (the tests and developer files stay out of your install)"

# ---- 3. test the staged copy before touching anything that exists
smoke() {
  local out
  out=$(/bin/zsh -f "$1/dist/mograph-jailed.zsh" --request - 2>/dev/null <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=installer-check
command=system.probe
REQ
  ) || return 1
  case "$out" in *'"ok":true'*) return 0 ;; *) return 1 ;; esac
}
smoke "$STAGE" || die "The new copy would not start - nothing was changed. Please report this."
ok "the new copy runs"

# ---- 4. swap
step "Putting it in place"
OLD=""
if [ -e "$ROOT" ]; then
  OLD="$ROOT.previous.$$"
  /bin/mv "$ROOT" "$OLD" || die "Cannot move the existing folder aside - nothing was changed."
fi
if ! /bin/mv "$STAGE" "$ROOT"; then
  [ -z "$OLD" ] || /bin/mv "$OLD" "$ROOT"
  die "Could not put the new copy in place - your previous folder is back as it was."
fi
if ! smoke "$ROOT"; then
  /bin/rm -rf "$ROOT"; [ -z "$OLD" ] || /bin/mv "$OLD" "$ROOT"
  die "The installed copy would not start - your previous folder is back as it was."
fi
if [ -n "$OLD" ]; then
  if [ -f "$OLD/dist/mograph-jailed.zsh" ]; then /bin/rm -rf "$OLD"; ok "replaced the older MographJailed (no old files left behind)"
  else KEPT="${ROOT}.previous"; /bin/rm -rf "$KEPT"; /bin/mv "$OLD" "$KEPT"; warn "that folder held other files; they are kept in $KEPT"; fi
fi
ok "installed to $ROOT"

# ---- 5. connect to Terminal
step "Connecting Terminal"
WIRE=0
if [ -n "${MJ_INSTALL_ZSHRC:-}" ]; then [ "$MJ_INSTALL_ZSHRC" = 1 ] && WIRE=1
elif [ "$YES" = 1 ]; then WIRE=0
else
  /bin/echo "   To type  mj  in Terminal, one line is added to your Terminal startup file ($RC)."
  /bin/echo "   Your file is backed up first, and the uninstaller removes exactly that line."
  ask_yes "Add it?" y && WIRE=1
fi
if [ "$WIRE" = 1 ] && [ "$(block_state "$RC")" = bad ]; then
  # Never edit a file we cannot read safely: removing "our" lines between a lone marker and the end of the file
  # would delete the person's own settings.
  WIRE=0
  /bin/echo "   ! Your Terminal startup file ($RC) has a MographJailed section that is incomplete"
  /bin/echo "     (a start or end line is missing, out of order, or repeated). I left that file exactly as it is."
  /bin/echo "     To connect Terminal, delete any line that starts with  # >>> MographJailed  or  # <<< MographJailed,"
  /bin/echo "     then run this installer again, or add the two lines below by hand."
fi
if [ "$WIRE" = 1 ]; then
  if [ -f "$RC" ]; then BK="$RC.mj-backup-$(/bin/date +%Y%m%d-%H%M%S)"; /bin/cp "$RC" "$BK" && ok "backed up $RC to $BK"; fi
  TMPRC=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mj-zshrc.XXXXXX") || die "Cannot create a temporary file."
  [ -f "$RC" ] && /usr/bin/awk -v b="$B" -v e="$E" '$0==b{skip=1;next} $0==e{skip=0;next} !skip{print}' "$RC" > "$TMPRC"
  { [ -s "$TMPRC" ] && [ "$(/usr/bin/tail -c1 "$TMPRC" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 0 ] && /bin/echo ""
    /bin/echo "$B"
    /bin/echo "export MOGRAPHJAILED_ROOT=\"$ROOT\""
    /bin/echo '[ -r "$MOGRAPHJAILED_ROOT/scripts/shell/mj-init.zsh" ] && source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-init.zsh"'
    /bin/echo "$E"; } >> "$TMPRC"
  /bin/cat "$TMPRC" > "$RC" || die "Could not write $RC."
  /bin/rm -f "$TMPRC"
  ok "added to $RC"
else
  warn "Terminal not connected. To do it later, add this to $RC:"
  /bin/echo "       export MOGRAPHJAILED_ROOT=\"$ROOT\"; source \"\$MOGRAPHJAILED_ROOT/scripts/shell/mj-init.zsh\""
fi

# ---- 6. setup
SETUP=0
if [ -n "${MJ_INSTALL_SETUP:-}" ]; then [ "$MJ_INSTALL_SETUP" = 1 ] && SETUP=1
elif [ "$YES" != 1 ] && [ "$WIRE" = 1 ]; then SETUP=1; fi
if [ "$SETUP" = 1 ]; then
  step "Choosing your folders"
  MOGRAPHJAILED_ROOT="$ROOT" MJ_CLI="$ROOT/dist/mograph-jailed.zsh" /bin/zsh -f -c 'source "$1/scripts/shell/mj-cli.zsh"; mj setup' _ "$ROOT" || warn "setup did not finish; run  mj setup  in a new Terminal window"
fi

/bin/echo ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  MographJailed is installed.                 │"
/bin/echo "  └──────────────────────────────────────────────┘"
/bin/echo ""
if [ "$WIRE" = 1 ]; then
  /bin/echo "   Open a NEW Terminal window and type:   mj"
else
  /bin/echo "   Connect Terminal (see above), then type:   mj"
fi
/bin/echo "   First time? type:   mj setup      Questions? type:   mj help"
/bin/echo ""
exit 0
