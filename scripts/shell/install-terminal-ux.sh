#!/bin/bash
# Install/update MographJailed local terminal UX without system-wide changes.
set -eu

ROOT="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}"
HELPER="$ROOT/scripts/shell/mj-shell.zsh"
STAMP=$(/bin/date +%Y%m%d-%H%M%S)
BACKUP="$ROOT/config/shell/terminal-ux-$STAMP"

fail() { /bin/echo "ERROR: $*" >&2; exit 1; }
[ -d "$ROOT" ] || fail "MographJailed root not found: $ROOT"
[ -r "$ROOT/scripts/shell/mj-terminal.zsh" ] || fail "Terminal common helper is missing."
[ -r "$ROOT/scripts/shell/mj-man.zsh" ] || fail "mj-man helper is missing."
[ -r "$ROOT/scripts/shell/mj-top.zsh" ] || fail "mj-top helper is missing."
[ -r "$ROOT/scripts/shell/mj-cli.zsh" ] || fail "mj front end is missing."
[ -r "$ROOT/scripts/terminal/mj-md-render.awk" ] || fail "Markdown renderer is missing."
[ -r "$ROOT/scripts/terminal/mj-top-render.js" ] || fail "Dashboard renderer is missing."
[ -r "$ROOT/scripts/terminal/mj-top-run.zsh" ] || fail "Dashboard worker is missing."

/bin/mkdir -p "$BACKUP" "$(/usr/bin/dirname "$HELPER")"
if [ -f "$HELPER" ]; then
    /bin/cp "$HELPER" "$BACKUP/mj-shell.zsh"
else
    /bin/cat > "$HELPER" <<'SHELL'
# MographJailed local shell helper loader.
SHELL
fi

append_source() {
    local needle="$1"
    local line="$2"
    if ! /usr/bin/grep -Fq "$needle" "$HELPER"; then
        printf '\n%s\n' "$line" >> "$HELPER"
    fi
}

append_source 'scripts/shell/mj-terminal.zsh' 'if [ -r "$HOME/Documents/MographJailed/scripts/shell/mj-terminal.zsh" ]; then source "$HOME/Documents/MographJailed/scripts/shell/mj-terminal.zsh"; fi'
append_source 'scripts/shell/mj-man.zsh' 'if [ -r "$HOME/Documents/MographJailed/scripts/shell/mj-man.zsh" ]; then source "$HOME/Documents/MographJailed/scripts/shell/mj-man.zsh"; fi'
append_source 'scripts/shell/mj-top.zsh' 'if [ -r "$HOME/Documents/MographJailed/scripts/shell/mj-top.zsh" ]; then source "$HOME/Documents/MographJailed/scripts/shell/mj-top.zsh"; fi'
append_source 'scripts/shell/mj-cli.zsh' 'if [ -r "$HOME/Documents/MographJailed/scripts/shell/mj-cli.zsh" ]; then source "$HOME/Documents/MographJailed/scripts/shell/mj-cli.zsh"; fi'

/bin/cat <<EOF2
SUCCESS
-------
MJ terminal UX is installed locally.
Backup: $BACKUP

Activate current Terminal:
  source ~/.zshrc

Commands:
  mj-man
  mj-man terminal
  mj-top
  mj ops
  mj <operation> name=value ...
  mj recipe <file> name=value ...
EOF2
