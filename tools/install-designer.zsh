#!/bin/zsh -f
# MographJailed — designer-friendly installer.
#
# Guided setup for people who don't live in the terminal. No git needed,
# no sudo, no admin password. Everything lands inside one folder you choose.
#
# Run it straight from the web (macOS Terminal):
#   curl -fsSL https://raw.githubusercontent.com/NeuralIO444/Mograph_Jailed_OSX_CLI/main/tools/install-designer.zsh | zsh
# Or download it first and run:  zsh install-designer.zsh

emulate -R zsh
set -u

REPO_ZIP_URL="https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/archive/refs/heads/main.zip"
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
if [ ! -c /dev/tty ] && [ ! -t 0 ]; then
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
ROOT=$(ask "Install folder" "$DEFAULT_ROOT")
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
    confirm "Replace its MographJailed contents with a fresh download? (your snapshots elsewhere are not touched)" || die "Quitting — nothing was changed."
  fi
  step "Step 3 of 4 — Downloading MographJailed"
  /bin/echo "   From: github.com/NeuralIO444/Mograph_Jailed_OSX_CLI"
  TMPD=$(/usr/bin/mktemp -d /tmp/mj-install.XXXXXX) || die "Can't create a temp folder."
  trap '/bin/rm -rf "$TMPD"' EXIT
  /usr/bin/curl -fsSL -o "$TMPD/mj.zip" "$REPO_ZIP_URL" || die "Download failed — check your internet and try again."
  ok "downloaded"
  if command -v ditto >/dev/null 2>&1; then
    /usr/bin/ditto -x -k "$TMPD/mj.zip" "$TMPD" || die "Couldn't unpack the download."
  else
    /usr/bin/unzip -q "$TMPD/mj.zip" -d "$TMPD" || die "Couldn't unpack the download."
  fi
  SRC="$TMPD/Mograph_Jailed_OSX_CLI-main"
  [ -f "$SRC/dist/mograph-jailed.zsh" ] || die "Download looks wrong (missing dist/mograph-jailed.zsh) — nothing installed."
  /bin/mkdir -p "$ROOT" || die "Can't create $ROOT."
  # copy contents (not the wrapper dir) into place
  /bin/cp -R "$SRC/." "$ROOT/" || die "Copy failed."
  ok "installed to $ROOT"
  FRESH_ROOT="$ROOT"
fi

# --- 3. smoke test ---
step "Step 4 of 4 — Making sure it works"
CLI="$FRESH_ROOT/dist/mograph-jailed.zsh"
[ -f "$CLI" ] || die "The installed copy looks broken (no dist/mograph-jailed.zsh)."
PROBE_OUT=$(/bin/zsh -f "$CLI" --request /dev/stdin <<'REQ' 2>/dev/null
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

if confirm "Add terminal helpers (mj-man help pages, mj-top dashboard)?"; then
  MOGRAPHJAILED_ROOT="$FRESH_ROOT" /bin/bash "$FRESH_ROOT/scripts/shell/install-terminal-ux.sh" \
    && ok "terminal helpers installed — open a new Terminal and type:  mj-man"
fi

if confirm "Auto-version your After Effects projects when they change? (the watcher)"; then
  WATCH_DIR=$(ask "Folder with your .aep projects" "$HOME/Movies")
  VERSIONS_DIR=$(ask "Folder to keep versions in" "$HOME/AE_Versions")
  case "$WATCH_DIR" in "~"*) WATCH_DIR="$HOME${WATCH_DIR#\~}" ;; esac
  case "$VERSIONS_DIR" in "~"*) VERSIONS_DIR="$HOME${VERSIONS_DIR#\~}" ;; esac
  /bin/zsh -f "$FRESH_ROOT/tools/watch-install.zsh" --yes "$WATCH_DIR" "$VERSIONS_DIR" \
    && ok "watcher installed — snapshots appear in $VERSIONS_DIR"
fi

# --- farewell ---
/bin/echo ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  You're in. Here's what you've got:          │"
/bin/echo "  └──────────────────────────────────────────────┘"
/bin/echo ""
/bin/echo "  • Project scraper (run inside After Effects):"
/bin/echo "      File → Scripts → Run Script File, then pick:"
/bin/echo "      $FRESH_ROOT/integrations/after-effects/MographJailed_ProjectScraper.jsx"
/bin/echo ""
/bin/echo "  • Live dashboard (Terminal):"
/bin/echo "      zsh -f $FRESH_ROOT/tools/mj-observe-dash.zsh --versions \$HOME/AE_Versions --receipts \$HOME/AE_Receipts"
/bin/echo ""
/bin/echo "  • Help any time:  mj-man   (if you installed terminal helpers)"
/bin/echo "  • Guides: https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/wiki"
/bin/echo ""
/bin/echo "  It can look at everything and change nothing."
/bin/echo ""
