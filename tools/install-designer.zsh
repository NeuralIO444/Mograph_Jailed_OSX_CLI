#!/bin/zsh -f
# MographJailed — designer-friendly installer.
#
# Guided setup for people who don't live in the terminal. No git needed,
# no sudo, no admin password. Everything lands inside one folder you choose.
#
# Run it straight from the web (macOS Terminal):
#   curl -fsSL https://raw.githubusercontent.com/NeuralIO444/Mograph_Jailed_OSX_CLI/main/tools/install-designer.zsh | zsh
# Or download it first and run:  zsh install-designer.zsh   (reading it first is the safest way)
#
# Integrity: the download is unpacked into a temp folder and every file is checked against the
# SHA256SUMS list shipped inside it before anything is copied into place, and the download's
# own SHA-256 is printed. To pin an exact release, set MJ_INSTALL_REF (a tag, e.g. 0.4.0) and
# MJ_INSTALL_SHA256 (the zip's hash from a source you trust); the install refuses on a mismatch.
# Scripted installs: MJ_INSTALL_YES=1 MJ_INSTALL_ROOT=/path [MJ_INSTALL_REPLACE=1].

emulate -R zsh
set -u

MJ_INSTALL_REF="${MJ_INSTALL_REF:-}"
if [ -n "$MJ_INSTALL_REF" ]; then
  REPO_ZIP_URL="https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/archive/refs/tags/$MJ_INSTALL_REF.zip"
else
  REPO_ZIP_URL="https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/archive/refs/heads/main.zip"
fi
REPO_ZIP_URL="${MJ_INSTALL_ZIP_URL:-$REPO_ZIP_URL}"   # tests and mirrors
YES="${MJ_INSTALL_YES:-0}"
DEFAULT_ROOT="$HOME/Documents/MographJailed"

# --- little UI helpers (plain language, no jargon) ---
say()    { /bin/echo ""; /bin/echo "$*"; }
step()   { /bin/echo ""; /bin/echo "── $*"; }
ok()     { /bin/echo "   ✓ $*"; }
warn()   { /bin/echo "   ! $*"; }
die()    { /bin/echo ""; /bin/echo "   ✗ $*"; /bin/echo ""; exit 1; }

# Read answers from the real terminal even when this script is piped via curl.
# The prompt goes to stderr so $(ask ...) captures only the answer.
ask() {
  local _prompt="$1" _default="$2" _ans=""
  if [ "$YES" = 1 ]; then /bin/echo "$_default"; return; fi
  if [ -n "$_default" ]; then
    /bin/echo -n "   $_prompt [$_default]: " >&2
  else
    /bin/echo -n "   $_prompt: " >&2
  fi
  IFS= read -r _ans < /dev/tty 2>/dev/null || _ans=""
  [ -z "$_ans" ] && _ans="$_default"
  /bin/echo "$_ans"
}
confirm() {
  local _ans
  if [ "$YES" = 1 ]; then return 1; fi      # scripted installs never accept optional extras or replacements by default
  _ans=$(ask "$1" "y")
  case "$_ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

/bin/echo ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  MographJailed — easy install                │"
/bin/echo "  │  Look at everything. Change nothing.         │"
/bin/echo "  └──────────────────────────────────────────────┘"

# --- 1. preflight ---
step "Step 1 of 4 — Checking your Mac"
if [ "$(/usr/bin/uname -s)" != "Darwin" ] && [ "${MJ_INSTALL_ALLOW_NONMAC:-}" != "1" ]; then
  die "This installer needs a Mac (found $(/usr/bin/uname -s))."
fi
if [ "$YES" != 1 ] && [ ! -c /dev/tty ] && [ ! -t 0 ]; then
  die "This installer is interactive — please run it in a Terminal, not through automation."
fi
ok "macOS detected"
[ -x /bin/zsh ] || die "Can't find /bin/zsh — this Mac looks unusual."
ok "zsh present"
command -v curl >/dev/null 2>&1 || die "Can't find curl — this Mac looks unusual."
ok "download tool present"
if [ -x /usr/bin/python3 ]; then
  ok "system Python 3 present (needed for project reports)"
else
  warn "no /usr/bin/python3 — project reports (ingest/lint/snapshot) will not work until it exists"
fi

# --- 2. choose a home for it ---
step "Step 2 of 4 — Where should it live?"
/bin/echo "   Everything goes inside one folder. Nothing is installed anywhere else."
ROOT=$(ask "Install folder" "${MJ_INSTALL_ROOT:-$DEFAULT_ROOT}")
# expand a leading ~ the way a human means it
case "$ROOT" in
  "~"*) ROOT="$HOME${ROOT#\~}" ;;
esac
[ -n "$ROOT" ] || die "No folder given — quitting, nothing was changed."
case "$ROOT" in
  /*) ;;
  *) die "Please use a full path starting with / (for example $DEFAULT_ROOT)." ;;
esac

if [ -d "$ROOT/.git" ]; then
  say "   That folder already has MographJailed (installed with git)."
  confirm "Update it in place with git pull?" && {
    /usr/bin/git -C "$ROOT" pull --ff-only || die "git pull failed — your folder is untouched."
    ok "updated"
  }
  FRESH_ROOT="$ROOT"
else
  if [ -e "$ROOT" ]; then
    say "   That folder already exists."
    if [ "$YES" = 1 ] && [ "${MJ_INSTALL_REPLACE:-0}" = 1 ]; then :; else
      confirm "Replace its MographJailed contents with a fresh download? (your snapshots elsewhere are not touched)" || die "Quitting — nothing was changed."
    fi
  fi
  step "Step 3 of 4 — Downloading MographJailed"
  /bin/echo "   From: github.com/NeuralIO444/Mograph_Jailed_OSX_CLI"
  TMPD=$(/usr/bin/mktemp -d /tmp/mj-install.XXXXXX) || die "Can't create a temp folder."
  trap '/bin/rm -rf "$TMPD"' EXIT
  /usr/bin/curl -fsSL -o "$TMPD/mj.zip" "$REPO_ZIP_URL" || die "Download failed — check your internet and try again."
  ok "downloaded"
  ZIP_SHA=$(/usr/bin/shasum -a 256 "$TMPD/mj.zip" | /usr/bin/awk '{print $1}')
  /bin/echo "   download SHA-256: $ZIP_SHA"
  if [ -n "${MJ_INSTALL_SHA256:-}" ]; then
    [ "$ZIP_SHA" = "${MJ_INSTALL_SHA256}" ] || die "The download does not match the SHA-256 you pinned (expected ${MJ_INSTALL_SHA256}) — nothing installed."
    ok "matches the SHA-256 you pinned"
  fi
  if command -v ditto >/dev/null 2>&1; then
    /usr/bin/ditto -x -k "$TMPD/mj.zip" "$TMPD/unpacked" || die "Couldn't unpack the download."
  else
    /usr/bin/unzip -q "$TMPD/mj.zip" -d "$TMPD/unpacked" || die "Couldn't unpack the download."
  fi
  # GitHub wraps the files in one folder named after the repo and ref.
  SRC=$(/bin/ls -d "$TMPD"/unpacked/*/ 2>/dev/null | /usr/bin/head -1)
  SRC="${SRC%/}"
  [ -n "$SRC" ] && [ -f "$SRC/dist/mograph-jailed.zsh" ] || die "Download looks wrong (missing dist/mograph-jailed.zsh) — nothing installed."
  if [ -f "$SRC/SHA256SUMS" ]; then
    BAD=$(cd "$SRC" && /usr/bin/shasum -a 256 -c SHA256SUMS 2>&1 | /usr/bin/grep -v ': OK$' | /usr/bin/head -5)
    [ -z "$BAD" ] || die "Some files in the download do not match their checksums — nothing installed.${BAD:+ ($(/bin/echo "$BAD" | /usr/bin/head -1))}"
    # shasum -c only checks the files the list names; an extra file would ride along unchecked.
    (cd "$SRC" && /usr/bin/find . -type f ! -name SHA256SUMS | /usr/bin/sed 's|^\./||' | LC_ALL=C /usr/bin/sort) > "$TMPD/present.txt"
    /usr/bin/sed 's/^[0-9a-f]*  //' "$SRC/SHA256SUMS" | LC_ALL=C /usr/bin/sort > "$TMPD/listed.txt"
    EXTRA=$(/usr/bin/comm -23 "$TMPD/present.txt" "$TMPD/listed.txt" | /usr/bin/head -3)
    [ -z "$EXTRA" ] || die "The download contains files that are not in its checksum list — nothing installed. (e.g. $(/bin/echo "$EXTRA" | /usr/bin/head -1))"
    ok "every file matches its checksum, and nothing extra is included"
  else
    warn "this download has no checksum list (older release); file check skipped"
  fi
  # The shared install core stages the copy, tests it, swaps it in cleanly (no stale files), connects Terminal and
  # offers `mj setup`. The files were verified just above, so it does not repeat that.
  MJ_YES="$YES" MJ_INSTALL_VERIFIED=1 /bin/zsh -f "$SRC/tools/install-local.zsh" "$SRC" "$ROOT" || die "The install did not finish - see above. Your previous folder (if any) is unchanged."
  FRESH_ROOT="$ROOT"
fi

# --- 3. smoke test ---
step "Step 4 of 4 — Making sure it works"
CLI="$FRESH_ROOT/dist/mograph-jailed.zsh"
[ -f "$CLI" ] || die "The installed copy looks broken (no dist/mograph-jailed.zsh)."
PROBE_OUT=$(/bin/zsh -f "$CLI" --request - <<'REQ' 2>/dev/null
MOGRAPHJAILED_REQUEST 1
requestId=designer-install-check
command=system.probe
REQ
) || die "The tool wouldn't start — please report this."
case "$PROBE_OUT" in
  *'"ok":true'*) ok "it runs — your Mac answered its first command" ;;
  *) die "The tool started but answered oddly — please report this." ;;
esac

# --- optional extras ---
say ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  Optional extras                             │"
/bin/echo "  └──────────────────────────────────────────────┘"

if confirm "Auto-version your After Effects projects when they change? (the watcher)"; then
  WATCH_DIR=$(ask "Folder with your .aep projects" "$HOME/Movies")
  VERSIONS_DIR=$(ask "Folder to keep versions in" "$HOME/AE_Versions")
  case "$WATCH_DIR" in "~"*) WATCH_DIR="$HOME${WATCH_DIR#\~}" ;; esac
  case "$VERSIONS_DIR" in "~"*) VERSIONS_DIR="$HOME${VERSIONS_DIR#\~}" ;; esac
  /bin/zsh -f "$FRESH_ROOT/tools/watch-install.zsh" --yes "$WATCH_DIR" "$VERSIONS_DIR" \
    && ok "watcher installed — snapshots appear in $VERSIONS_DIR"
  # Remember the folders so every tool (mj, the dashboard) knows them without flags.
  if [ -r "$FRESH_ROOT/scripts/shell/mj-config.zsh" ]; then
    /bin/zsh -f -c 'source "$1"; mj_config_set watch_dir "$2" && mj_config_set versions_dir "$3"' _ \
      "$FRESH_ROOT/scripts/shell/mj-config.zsh" "$WATCH_DIR" "$VERSIONS_DIR" >/dev/null 2>&1 \
      && ok "remembered your folders (change them any time with: mj config)"
  fi
fi

# --- farewell ---
/bin/echo ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  You're in. Here's what you've got:          │"
/bin/echo "  └──────────────────────────────────────────────┘"
/bin/echo ""
/bin/echo "  • Everyday commands (open a new Terminal first):"
/bin/echo "      mj setup        choose your folders (first time)"
/bin/echo "      mj check X      is project X ready? expressions, fonts, footage"
/bin/echo "      mj snapshot X   save a verified version of a project"
/bin/echo "      mj doctor       is everything set up?"
/bin/echo "      mj help         every command, in plain language"
/bin/echo ""
/bin/echo "  • Project scraper (run inside After Effects):"
/bin/echo "      File → Scripts → Run Script File, then pick:"
/bin/echo "      $FRESH_ROOT/integrations/after-effects/MographJailed_ProjectScraper.jsx"
/bin/echo ""
/bin/echo "  • Help any time:  mj help      (full pages: mj-man)"
/bin/echo "  • Guides: https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/wiki"
/bin/echo ""
/bin/echo "  It can look at everything and change nothing."
/bin/echo ""

# --- the front door: offer the dashboard (shown on every install and re-install) ---
if [ "$YES" != 1 ] && [ -r "$FRESH_ROOT/scripts/terminal/mj_ui.py" ] && [ -x /usr/bin/python3 ]; then
  if confirm "Open the live dashboard now? (press q inside it to come back)"; then
    MOGRAPHJAILED_ROOT="$FRESH_ROOT" MJ_CLI="$CLI" /usr/bin/python3 "$FRESH_ROOT/scripts/terminal/mj_ui.py" home < /dev/tty
    MOGRAPHJAILED_ROOT="$FRESH_ROOT" MJ_CLI="$CLI" /usr/bin/python3 "$FRESH_ROOT/scripts/terminal/mj_ui.py" ui < /dev/tty
  fi
fi
