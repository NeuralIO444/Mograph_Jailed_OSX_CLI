# MographJailed 0.3.0-dev.2 — Target-Mac Qualification

Run on the managed production Mac with no sudo, Homebrew, Xcode/CLT installation, or system configuration changes. Keep the previous MographJailed backup until all gates pass.

## 1. Health

```text
mj-status
```

Expected: READY, Core PASS, warnings 0, CLI `0.3.0-dev.2`.

## 2. Registry serialization under production zsh

Create a `system.describe` request and run it with `/bin/zsh -f`. Confirm these fields are real arrays with one capability per element:

```json
"file.inspect":{"requires":{"all":["stat","file","uname"]}}
"runtime.verify":{"optionalCapabilities":["sha256","shasum"]}
"media.inspect":{"optionalCapabilities":["mdls","avmediainfo"]}
```

Reject the build if any value appears as a joined scalar such as `["stat file uname"]`.

## 3. mj-man v2

```text
mj-man
mj-man commands
mj-man organize
mj-man terminal
```

Verify:

- headings are rendered without raw Markdown `#` prefixes
- code fences are not visible
- color is readable in the MJ Terminal profile
- `/` search works in `less`
- `q` exits cleanly

Then:

```text
NO_COLOR=1 mj-man commands
```

Verify no ANSI color escapes are visible.

## 4. mj-top snapshot dashboard

```text
mj-top
```

Verify panels appear for runtime, registry, storage, asset/media intelligence, and safety. Confirm it returns to the prompt after one snapshot and does not continue polling.

Fallbacks:

```text
mj-top --ascii
mj-top --plain
NO_COLOR=1 mj-top --ascii
COLUMNS=50 mj-top --ascii
```

Verify all return cleanly without corrupting the Terminal state.

## 5. No automation/TCC surprise

`mj-top` uses JXA only for local JSON parsing/rendering. Normal invocation should not request Automation access to Finder/System Events/Terminal/After Effects or another application. Record any unexpected prompt as a release blocker.

## 6. Temp cleanup

Before and after `mj-top`, inspect `/tmp` for `mj-top-*` files. Normal completion and Ctrl-C interruption should not leave dashboard request/response files behind.

## 7. NG-M2 native adapters

Continue the existing NG-M2 checklist for:

- `mdfind` → `search.candidate`
- `xattr` → `file.provenance`
- `sips` → `image.inspect` / `image.derivative`
- local APFS and representative SMB `storage.preflight`

## 8. After Effects

The existing AE client must still report Protocol 1 and CLI `0.3.0-dev.2`. No terminal UX file is required by bundled AE consumers.

## Pass criteria

- Registry arrays correct under real `/bin/zsh -f`
- `mj-man` v2 passes
- `mj-top` modern/ascii/plain passes
- no terminal-state corruption
- no unexpected TCC prompt
- no new runtime dependency
- NG-M2 Mac gates remain clean
