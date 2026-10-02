#!/usr/bin/env bash
# Unit tests for tests/support/check_guides.py using small fixture markdown files.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
printf 'snapshot.create\nproject.lint\nindex.add\n' > "$TMP/ops"
chk(){ python3 "$ROOT/tests/support/check_guides.py" "$ROOT" "$TMP/ops" "snapshot versions lint" "$1" >/dev/null 2>&1; }
ok(){ if chk "$1"; then pass=$((pass+1)); else echo "FAIL (expected ok): $2" >&2; fail=$((fail+1)); fi; }
bad(){ if chk "$1"; then echo "FAIL (expected reject): $2" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi; }
w(){ printf '%s\n' "$2" > "$TMP/$1.md"; echo "$TMP/$1.md"; }

ok  "$(w a '```text
$ mj snapshot "X"
```')" "known verb"
ok  "$(w b '```
$ mj index.add path=/x
```')" "known operation"
ok  "$(w c '```
$ MJ_X=1 mj lint last
```')" "env prefix"
bad "$(w d '```
$ mj frobnicate
```')" "unknown verb"
bad "$(w e 'Use `index.remove` to undo.')" "unknown operation in prose"
ok  "$(w f 'See `mj-config.zsh` and `index.add`.')" "file name and known op in prose"
ok  "$(w g 'Plain text, mj frobnicate outside a code block.')" "ignores prose outside code blocks"
ok  "$(w h 'The `foo.bar` thing.')" "non-operation dotted name"

echo "Guide checker unit tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
