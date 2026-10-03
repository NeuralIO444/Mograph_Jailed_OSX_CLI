#!/bin/zsh -f
# Double-click me to remove MographJailed. Your projects, saved versions and project reports are not touched.
cd "${0:A:h}" || exit 1
ROOT="${MOGRAPHJAILED_ROOT:-$HOME/Documents/MographJailed}"
/bin/echo ""
/bin/echo "  MographJailed - uninstall"
/bin/echo "   This removes:  $ROOT   and the lines it added to your Terminal startup file."
/bin/echo -n "   Press Return to continue, or close this window to cancel. "
{ read -r _x </dev/tty; } 2>/dev/null
SCRIPT="$ROOT/tools/uninstall-local.zsh"
[ -f "$SCRIPT" ] || SCRIPT="${0:A:h}/payload/tools/uninstall-local.zsh"
/bin/zsh -f "$SCRIPT" "$ROOT"
/bin/echo -n "  Press Return to close this window. "; { read -r _x </dev/tty; } 2>/dev/null
