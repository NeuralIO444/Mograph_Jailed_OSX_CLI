#!/usr/bin/env bash
# The installer core (tools/install-local.zsh), the uninstaller, the shell hookup, the release zip and mj setup.
# Everything runs against a scratch HOME: no real ~/.zshrc, config or Terminal is touched.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
export HOME="$TMP/home"; mkdir -p "$HOME"
RC="$HOME/.zshrc"; export MJ_ZSHRC="$RC" MJ_INSTALL_ALLOW_NONMAC=1

# A source folder the way the release zip lays it out: tracked files only, with their checksum list.
git -C "$ROOT" ls-files -z | (cd "$ROOT" && xargs -0 -I{} sh -c 'mkdir -p "$1/$(dirname "$2")" && cp "$2" "$1/$2"' _ "$TMP/src" {})
(cd "$TMP/src" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done > SHA256SUMS)
inst(){ env MJ_YES=1 "$@" zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/Mograph Jailed" </dev/null; }

# ---- scripted install: nothing but the folder
inst > "$TMP/o1.txt" 2>&1; check test $? = 0
check test -f "$TMP/Mograph Jailed/dist/mograph-jailed.zsh"
check test ! -e "$RC"                                             # scripted installs do not touch the startup file
check test ! -d "$TMP/Mograph Jailed/tests" -a ! -d "$TMP/Mograph Jailed/research" -a ! -d "$TMP/Mograph Jailed/.github"
check test -f "$TMP/Mograph Jailed/tools/install-local.zsh"
check has "$TMP/o1.txt" "the new copy runs"
check test -z "$(ls -d "$TMP"/Mograph\ Jailed.* 2>/dev/null)"      # no staging or backup folders left behind

# ---- connect Terminal: one marked block, backed up, idempotent, and it really loads mj
printf '# my own settings\nexport FOO=1' > "$RC"                      # no trailing newline on purpose
inst MJ_INSTALL_ZSHRC=1 > "$TMP/o2.txt" 2>&1; check test $? = 0
check test "$(grep -c '^# >>> MographJailed' "$RC")" = 1
check test "$(grep -c '^# <<< MographJailed' "$RC")" = 1
check has "$RC" "export MOGRAPHJAILED_ROOT=\"$TMP/Mograph Jailed\""
check has "$RC" "# my own settings"
check test -n "$(ls "$RC".mj-backup-* 2>/dev/null)"
inst MJ_INSTALL_ZSHRC=1 > "$TMP/o3.txt" 2>&1; check test $? = 0
check test "$(grep -c '^# >>> MographJailed' "$RC")" = 1           # re-running does not stack blocks
check test "$(grep -c 'FOO=1' "$RC")" = 1
printf 'mj_type=$(whence -w mj); print -r -- "$mj_type"\n' > "$TMP/t.zsh"
env -i HOME="$HOME" PATH=/usr/bin:/bin ZDOTDIR="$HOME" /bin/zsh -i -c 'source "$HOME/.zshrc"; whence -w mj; mj help | head -1' > "$TMP/o4.txt" 2>&1
check has "$TMP/o4.txt" "mj: function"
check has "$TMP/o4.txt" "mj  -  look at, check and protect"

# ---- an install folder with a quote or $ in the name is refused (it could not be written safely)
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/bad\$(x)" </dev/null > "$TMP/o5.txt" 2>&1; rc=$?
check test $rc -ne 0; check test ! -e "$TMP/bad\$(x)"
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$HOME" </dev/null > "$TMP/o6.txt" 2>&1; rc=$?
check test $rc -ne 0

# ---- a changed file, or an extra file, stops the install before anything exists
cp -R "$TMP/src" "$TMP/src-bad"; echo "# tampered" >> "$TMP/src-bad/src/core/constants.zsh"
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src-bad" "$TMP/bad-install" </dev/null > "$TMP/o7.txt" 2>&1; rc=$?
check test $rc -ne 0; check test ! -e "$TMP/bad-install"; check has "$TMP/o7.txt" "do not match their checksums"
rm -rf "$TMP/src-bad"; cp -R "$TMP/src" "$TMP/src-extra"; echo hi > "$TMP/src-extra/EXTRA.sh"
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src-extra" "$TMP/extra-install" </dev/null > "$TMP/o8.txt" 2>&1; rc=$?
check test $rc -ne 0; check test ! -e "$TMP/extra-install"; check has "$TMP/o8.txt" "not in the checksum list"

# ---- reinstall replaces cleanly: a file from an older version is gone
echo old > "$TMP/Mograph Jailed/leftover-from-old-version.txt"
inst > "$TMP/o9.txt" 2>&1; check test $? = 0
check test ! -e "$TMP/Mograph Jailed/leftover-from-old-version.txt"
check has "$TMP/o9.txt" "no old files left behind"
# a folder that is not MographJailed is kept, not deleted
mkdir -p "$TMP/other"; echo mine > "$TMP/other/keep.txt"
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/other" </dev/null > "$TMP/o10.txt" 2>&1
check test "$(cat "$TMP/other.previous/keep.txt")" = mine
# an install that cannot start leaves the previous one in place
cp -R "$TMP/src" "$TMP/src-broken"; printf 'exit 1\n' > "$TMP/src-broken/dist/mograph-jailed.zsh"
(cd "$TMP/src-broken" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done > SHA256SUMS)
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src-broken" "$TMP/Mograph Jailed" </dev/null > "$TMP/o11.txt" 2>&1; rc=$?
check test $rc -ne 0; check test -f "$TMP/Mograph Jailed/tools/install-local.zsh"; check has "$TMP/o11.txt" "would not start"

# ---- uninstall: removes exactly the block and the folder; versions and reports stay
mkdir -p "$HOME/AE_Versions" "$HOME/AE_Receipts"; echo v > "$HOME/AE_Versions/keep.aep"; echo r > "$HOME/AE_Receipts/keep.scrape.json"
printf 'export BAR=2\n' >> "$RC"
env MJ_YES=1 zsh -f "$ROOT/tools/uninstall-local.zsh" "$TMP/Mograph Jailed" > "$TMP/u1.txt" 2>&1; check test $? = 0
check test ! -e "$TMP/Mograph Jailed"
check test "$(grep -c 'MographJailed' "$RC")" = 0
check has "$RC" "FOO=1"; check has "$RC" "BAR=2"
check test -f "$HOME/AE_Versions/keep.aep" -a -f "$HOME/AE_Receipts/keep.scrape.json"
env MJ_YES=1 zsh -f "$ROOT/tools/uninstall-local.zsh" "$TMP/does-not-exist" > "$TMP/u2.txt" 2>&1; check test $? -ne 0
mkdir "$TMP/notmj"; env MJ_YES=1 zsh -f "$ROOT/tools/uninstall-local.zsh" "$TMP/notmj" > "$TMP/u3.txt" 2>&1; check test $? -ne 0; check test -d "$TMP/notmj"

# ---- mj setup, with its folders chosen non-interactively
export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store"
mkdir -p "$HOME/Movies/Client/Spot" "$HOME/Documents"; : > "$HOME/Movies/Client/Spot/Spot.aep"
mjz(){ MJ_CLI="$ROOT/dist/mograph-jailed.zsh" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1; echo $? > "$TMP/rc"; }
mjz "mj setup --yes"
check test "$(cat "$TMP/rc")" = 0
check has "$TMP/out.txt" "Projects: $HOME/Movies"                   # the folder that actually holds projects is suggested
check test -d "$HOME/AE_Receipts" -a -d "$HOME/AE_Versions"
mjz "mj config get watch_dir"; check has "$TMP/out.txt" "$HOME/Movies"
check has "$TMP/out.txt" "$HOME/Movies"
mjz "mj setup --yes"; check has "$TMP/out.txt" "Saved."               # safe to run again
mjz "mj scraper"; check has "$TMP/out.txt" "MographJailed_ProjectScraper.jsx"

# ---- mj doctor checklist, mj help, typos
mjz "mj doctor"; check has "$TMP/out.txt" "Your setup:"; check has "$TMP/out.txt" "Reports folder: $HOME/AE_Receipts (1 report)"
mjz "mj help"; check has "$TMP/out.txt" "First time:"; check has "$TMP/out.txt" "mj setup"
mjz "mj chekc"; check has "$TMP/out.txt" 'Did you mean "mj check"?'; check test "$(cat "$TMP/rc")" = 64
mjz "mj zzzzzz"; check has "$TMP/out.txt" '"zzzzzz" is not a command'

# ---- the release zip: build, unpack, double-click install (run as the .command), signed and unsigned
git -C "$ROOT" add -A >/dev/null 2>&1                                   # the build packs tracked files
sh "$ROOT/scripts/make-release.sh" "$TMP/rel" > "$TMP/rel.txt" 2>&1; check test $? = 0
ZIP=$(ls "$TMP"/rel/MographJailed-*.zip 2>/dev/null | head -1); check test -f "$ZIP"
check has "$TMP/rel.txt" "SHA-256:"
mkdir -p "$TMP/unz" && (cd "$TMP/unz" && unzip -q "$ZIP"); REL=$(ls -d "$TMP"/unz/MographJailed-*)
check test -x "$REL/Install MographJailed.command" -a -x "$REL/Uninstall MographJailed.command"
check test -f "$REL/README-FIRST.txt" -a -f "$REL/payload/dist/mograph-jailed.zsh"
check test ! -d "$REL/payload/tests" -a ! -d "$REL/payload/research" -a ! -d "$REL/payload/.github"
check bash -c "cd '$REL/payload' && shasum -a 256 -c SHA256SUMS >/dev/null"
rm -rf "$HOME/Documents"; unset MJ_ZSHRC; rm -f "$RC"
MJ_YES=1 MJ_INSTALL_ZSHRC=1 MOGRAPHJAILED_INSTALL_ROOT="$TMP/Double Click" "$REL/Install MographJailed.command" </dev/null > "$TMP/dc.txt" 2>&1
check test -f "$TMP/Double Click/dist/mograph-jailed.zsh"; check has "$HOME/.zshrc" "MographJailed"; check has "$TMP/dc.txt" "MographJailed is installed."
MOGRAPHJAILED_ROOT="$TMP/Double Click" MJ_YES=1 "$REL/Uninstall MographJailed.command" </dev/null > "$TMP/dcu.txt" 2>&1
check test ! -e "$TMP/Double Click"; check test "$(grep -c MographJailed "$HOME/.zshrc")" = 0
# tampered payload refuses
echo "# x" >> "$REL/payload/src/core/constants.zsh"
MJ_YES=1 MOGRAPHJAILED_INSTALL_ROOT="$TMP/Tampered" "$REL/Install MographJailed.command" </dev/null > "$TMP/dt.txt" 2>&1
check test ! -e "$TMP/Tampered"; check has "$TMP/dt.txt" "do not match their checksums"
# signed release: verifies; a changed checksum list is refused even if the files were changed to match
ssh-keygen -q -t ed25519 -N '' -f "$TMP/relkey" -C test >/dev/null
MJ_RELEASE_KEY="$TMP/relkey" sh "$ROOT/scripts/make-release.sh" "$TMP/rel2" > "$TMP/rel2.txt" 2>&1; check has "$TMP/rel2.txt" "signed with"
mkdir -p "$TMP/unz2" && (cd "$TMP/unz2" && unzip -q "$TMP/rel2"/MographJailed-*.zip); REL2=$(ls -d "$TMP"/unz2/MographJailed-*)
check test -f "$REL2/allowed_signers" -a -f "$REL2/payload/SHA256SUMS.sig"
MJ_YES=1 MOGRAPHJAILED_INSTALL_ROOT="$TMP/Signed" "$REL2/Install MographJailed.command" </dev/null > "$TMP/ds.txt" 2>&1
check test -f "$TMP/Signed/dist/mograph-jailed.zsh"; check has "$TMP/ds.txt" "signed by the MographJailed release key"
echo "# evil" >> "$REL2/payload/src/core/constants.zsh"
(cd "$REL2/payload" && find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done > SHA256SUMS)
MJ_YES=1 MOGRAPHJAILED_INSTALL_ROOT="$TMP/Forged" "$REL2/Install MographJailed.command" </dev/null > "$TMP/df.txt" 2>&1
check test ! -e "$TMP/Forged"; check has "$TMP/df.txt" "signature on this download does not match"

# ---- #34: a startup file with a broken MographJailed section is never edited (nothing the person wrote may be dropped)
OPEN="# >>> MographJailed (added by the installer; the uninstaller removes exactly this block) >>>"; CLOSE="# <<< MographJailed <<<"
shape(){ # shape <name> <file content>: install then uninstall must leave a malformed file byte-identical
  local f="$TMP/rc_$1"; printf '%b' "$2" > "$f"; local before; before=$(shasum -a 256 "$f" | cut -d' ' -f1)
  env MJ_YES=1 MJ_INSTALL_ZSHRC=1 MJ_ZSHRC="$f" zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/shape_$1" </dev/null > "$TMP/shape_$1.out" 2>&1
  check test $? = 0
  check test "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$before"
  check has "$TMP/shape_$1.out" "incomplete"
  check test -z "$(ls "$f".mj-backup-* 2>/dev/null)"                  # nothing was changed, so nothing needed backing up
  env MJ_YES=1 MJ_ZSHRC="$f" zsh -f "$ROOT/tools/uninstall-local.zsh" "$TMP/shape_$1" > "$TMP/shape_$1.un" 2>&1
  check test "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$before"
  check has "$TMP/shape_$1.un" "incomplete"
}
shape only_open   "export A=1\n$OPEN\nexport MY_IMPORTANT_PATH=/work/bin\nalias ll='ls -l'\n"
shape only_close  "export A=1\n$CLOSE\nexport KEEP=1\n"
shape reversed    "export A=1\n$CLOSE\nexport KEEP=1\n$OPEN\n"
shape nested      "$OPEN\nexport KEEP=1\n$OPEN\n$CLOSE\n"
shape two_opens   "$OPEN\n$CLOSE\nexport KEEP=1\n$OPEN\n"
# a complete block is still replaced, and duplicate complete blocks (an older buggy install) collapse into one
printf 'export A=1\n%s\nold line\n%s\nexport B=2\n%s\nold again\n%s\n' "$OPEN" "$CLOSE" "$OPEN" "$CLOSE" > "$TMP/rc_dup"
env MJ_YES=1 MJ_INSTALL_ZSHRC=1 MJ_ZSHRC="$TMP/rc_dup" zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/shape_dup" </dev/null > /dev/null 2>&1
check test "$(grep -c '^# >>> MographJailed' "$TMP/rc_dup")" = 1; check has "$TMP/rc_dup" "export A=1"; check has "$TMP/rc_dup" "export B=2"; check test "$(grep -c 'old line\|old again' "$TMP/rc_dup")" = 0
# a lookalike line is not a marker
printf 'export A=1\n  %s\nexport KEEP=1\n' "$OPEN" > "$TMP/rc_look"
env MJ_YES=1 MJ_INSTALL_ZSHRC=1 MJ_ZSHRC="$TMP/rc_look" zsh -f "$ROOT/tools/install-local.zsh" "$TMP/src" "$TMP/shape_look" </dev/null > /dev/null 2>&1
check has "$TMP/rc_look" "export KEEP=1"; check test "$(grep -c '^# >>> MographJailed' "$TMP/rc_look")" = 1

# ---- #41: only ordinary files and folders may be in a download; permissions are tightened
odd(){ # odd <name> <command that adds the odd thing to $d>
  local d="$TMP/odd_$1"; cp -R "$TMP/src" "$d"; eval "$2"
  ( perl -e 'alarm 25; exec @ARGV' env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$d" "$TMP/odd_inst_$1" </dev/null > "$TMP/odd_$1.out" 2>&1 ); local rc=$?
  check test $rc -ne 0; check test $rc -ne 142                       # refused, and not by running out of time
  check test ! -e "$TMP/odd_inst_$1"; check has "$TMP/odd_$1.out" "not an ordinary file"
}
odd symlink 'ln -s /etc "$d/docs/etc-link"'
odd dangling 'ln -s /nonexistent "$d/docs/dangling"'
odd fifo 'mkfifo "$d/docs/pipe"'
odd socket 'python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "$d/docs/sock"'
cp -R "$TMP/src" "$TMP/perm"; chmod 4755 "$TMP/perm/tools/uninstall-local.zsh"; chmod 2755 "$TMP/perm/tools/install-local.zsh"; chmod 777 "$TMP/perm/dist/mograph-jailed.zsh"; chmod 775 "$TMP/perm/docs"
env MJ_YES=1 zsh -f "$ROOT/tools/install-local.zsh" "$TMP/perm" "$TMP/perm_inst" </dev/null > "$TMP/perm.out" 2>&1; check test $? = 0
check test -z "$(find "$TMP/perm_inst" \( -perm -4000 -o -perm -2000 \) 2>/dev/null)"        # no set-user-id / set-group-id anywhere
check test -z "$(find "$TMP/perm_inst" -perm -020 -o -perm -002 2>/dev/null | head -1)"       # nothing writable by group or others
check test -x "$TMP/perm_inst/dist/mograph-jailed.zsh" -a -x "$TMP/perm_inst/tools/install-local.zsh"   # but it still runs

echo "Install tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
