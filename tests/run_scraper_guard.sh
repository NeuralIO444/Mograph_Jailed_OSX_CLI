#!/usr/bin/env bash
# The Tier 0 scraper read-only guard (issues #1 #2 #3): it must reject every kind of
# After Effects mutation and accept the real scraper.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/scripts/check-scraper-readonly.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
verdict(){ printf 'var x = 1;\n%s\n' "$1" > "$TMP/s.jsx"; if sh "$GUARD" "$TMP/s.jsx" >/dev/null 2>&1; then echo accepted; else echo rejected; fi; }
must_reject(){ check test "$(verdict "$1")" = rejected; [ "$(verdict "$1")" = rejected ] || echo "   (accepted: $1)" >&2; }
must_accept(){ check test "$(verdict "$1")" = accepted; [ "$(verdict "$1")" = accepted ] || echo "   (rejected: $1)" >&2; }

# the real scraper passes, and a missing file fails
check sh "$GUARD"
check bash -c "! sh '$GUARD' '$TMP/nope.jsx' >/dev/null 2>&1"

# --- original patterns ---
for s in 'app.project.save();' 'item.remove();' 'comp.layers.add(x);' 'str.replace(/a/, "b");' 'prop.setValue(1);' \
         'prop.setValueAtTime(0, 1);' 'prop.addKey(0);' 'prop.removeKey(1);' 'layer.duplicate();' 'proj.close(CloseOptions.DO_NOT_SAVE_CHANGES);' \
         'app.beginUndoGroup("x");' 'app.endUndoGroup();' 'app.executeCommand(2);'; do must_reject "$s"; done

# --- #2: mutators the first version missed ---
for s in 'prop.setValuesAtTimes(t, v);' 'app.project.autoFixExpressions("a", "b");' 'app.project.importFile(io);' \
         'app.project.importPlaceholder("p", 1, 1, 1, 1);' 'item.setProxy(f);' 'item.setProxyToFile(f);' 'item.setProxyToNone();' \
         'layer.copyToComp(c);' 'layer.moveAfter(o);' 'layer.moveBefore(o);' 'layer.moveToBeginning();' 'layer.moveToEnd();' \
         'app.project.saveWithDialog();' 'system.callSystem("rm -rf /");' 'layer.setParentWithJump(p);' 'comp.layers.addSolid(a, b, 1, 1, 1);' \
         'layer.property("x").addProperty("y");' 'layer.removeAll();' 'item.replaceSource(f, false);' 'app.project.items.addFolder("f");' \
         'app.open(f);' 'app.newProject();' 'app.quit();' 'app.purge(PurgeTarget.ALL_CACHES);' 'app.project.importFileWithDialog();'; do must_reject "$s"; done

# --- #3: assignment-based mutation ---
for s in 'prop.expression = "x";' 'layer.enabled = false;' 'comp.name = "x";' 'layer.locked = true;' 'layer.solo = true;' 'layer.shy = true;' \
         'layer.comment = "c";' 'comp.width = 100;' 'comp.duration += 1;' 'comp.frameRate -= 1;' 'layer.transform.opacity = 0;' \
         'item.parent = other;' 'layer.source = s;' 'app.project.item(1).name = "x";' 'layers[2].enabled = false;' 'x.property("a").value = 3;' \
         'prop.expressionEnabled = false;' 'layer.startTime *= 2;' 'comp.bgColor = [0, 0, 0];' 'layer.property("Source Text").text = "t";'; do must_reject "$s"; done

# --- dynamic code ---
for s in 'eval("x");' 'var f = new Function("return 1");' '$.evalFile(f);' 'var a = $.eval("1");'; do must_reject "$s"; done

# --- legitimate read-only code is accepted ---
must_accept 'var rec = {}; rec.expression = "text";'
must_accept 'rec.name = String(layer.name);'
must_accept 'var v = layer.enabled; if (v == true) { n++; }'
must_accept 'if (comp.name == "x" || comp.width >= 10) { ok = true; }'
must_accept 'var out = new File(p); out.open("w"); out.writeln(s); out.close();'
must_accept 'var names = []; names.push(item.name);'
must_accept 'for (i = 1; i <= proj.numItems; i++) { item = proj.item(i); }'
must_accept 'var d = layer.property("Source Text").value;'
must_accept 'acc.numProperties++;'
# conservative by design: text search cannot tell code from comments, so a comment that spells out a banned pattern is rejected too
must_reject '// comp.name = "x" is only a comment about what NOT to do'

echo "Scraper guard tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
