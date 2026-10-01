# The mj command

`mj` is the command-line front end for every MographJailed operation. It builds the request file, runs the runtime, and prints the JSON response.

```text
mj                                  launch screen (status of hosts, library, audit log, renders)
mj ui                               live dashboard (see mj-man terminal)
mj cd                               go to the MographJailed folder
mj ops                              list operations; required arguments are marked *
mj <operation> name=value ...       run one operation
mj recipe <file> name=value ...     run a recipe
mj last                             show the newest render receipt
mj open-last                        open the newest render folder in Finder
```

Values with spaces need quotes: `mj file.inspect "path=/Users/me/My Project/a.aep"`.

## Tab completion

Press Tab after `mj` for operation names, after an operation for its argument names, and after `name=` for file paths. Argument lists come from the runtime itself (`system.describe`), so they never go stale.

## Recipes

A recipe is a text file with one operation per line.

```text
# render-qa.mjrecipe
golden.check path={{frames}} input={{golden}}
loop.seams path={{frames}} maxResults=3
```

Run it with `mj recipe render-qa.mjrecipe frames=/path/to/frames golden=/path/to/hero.golden.json`.

- Lines starting with `#` and blank lines are ignored.
- `{{name}}` is filled from the command line; a missing value stops the recipe before it starts.
- Every operation and argument name is checked against the runtime before the first step runs.
- Recipes are data. Shell syntax inside a recipe is never executed.
- The recipe stops at the first failing step and returns its exit code.

An example lives in `recipes/render-qa.mjrecipe`.

## Output

On a terminal, `mj` pretty-prints JSON (needs `jq`, which ships with macOS). Piped, it prints the raw envelope: `{ok, data, error, ...}`. Exit codes follow the runtime (65 bad request, 69 unsupported, 73 output problem, 74 operation failed, 77 permission).
