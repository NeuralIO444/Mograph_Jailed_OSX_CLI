#!/bin/zsh -f
# Double-click me. Installs MographJailed into your Documents folder. No password, no internet needed.
cd "${0:A:h}" || exit 1
emulate -R zsh
clear 2>/dev/null
/bin/echo ""
/bin/echo "  ┌──────────────────────────────────────────────┐"
/bin/echo "  │  MographJailed - install                     │"
/bin/echo "  │  Look at everything. Change nothing.         │"
/bin/echo "  └──────────────────────────────────────────────┘"
finish() { /bin/echo ""; /bin/echo -n "  Press Return to close this window. "; { read -r _x </dev/tty; } 2>/dev/null; /bin/echo ""; exit "${1:-0}"; }
[ -d payload ] && [ -f payload/tools/install-local.zsh ] || { /bin/echo ""; /bin/echo "   ✗ This file must stay next to the 'payload' folder it came with. Unzip the whole download and try again."; finish 1; }

# Optional authenticity check: if the download is signed, the signature must match the key shipped with it.
if [ -f payload/SHA256SUMS.sig ] && [ -f allowed_signers ]; then
  if /usr/bin/ssh-keygen -Y verify -f allowed_signers -I release@mographjailed -n file -s payload/SHA256SUMS.sig < payload/SHA256SUMS >/dev/null 2>&1; then
    /bin/echo ""; /bin/echo "   ✓ the checksum list is signed by the MographJailed release key"
  else
    /bin/echo ""; /bin/echo "   ✗ The signature on this download does not match - it may have been changed. Nothing was installed."; finish 1
  fi
fi

DEFAULT="$HOME/Documents/MographJailed"
ROOT="${MOGRAPHJAILED_INSTALL_ROOT:-$DEFAULT}"
/bin/echo ""
/bin/echo "   It will be installed to:  $ROOT"
/bin/echo -n "   Press Return to continue, or type another folder: "
{ IFS= read -r ANS </dev/tty; } 2>/dev/null || ANS=""
/bin/echo ""
[ -n "$ANS" ] && ROOT="${ANS/#\~/$HOME}"

/bin/zsh -f payload/tools/install-local.zsh "${0:A:h}/payload" "$ROOT"
finish $?
