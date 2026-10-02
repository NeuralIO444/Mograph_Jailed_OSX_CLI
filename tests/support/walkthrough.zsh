# The commands the tutorials in docs/guides show, run in a sandbox. Usage:
#   zsh -f tests/support/walkthrough.zsh <repo root> <sandbox dir> <runtime path>
# Output is normalized by tests/run_guides.sh and compared with docs/guides/walkthrough.golden.
R="$1"; S="$2"; RUNTIME="$3"
export HOME="$S/home"
mkdir -p "$HOME" "$HOME/Library/Application Support" "$HOME/Library/Logs"
python3 "$R/tests/support/make_tutorial_fixtures.py" "$HOME/AE" >/dev/null
mkdir -p "$HOME/AE/hold" "$HOME/AE/versions" "$HOME/AE/out"
mv "$HOME/AE/receipts"/summer.* "$HOME/AE/receipts"/logo.* "$HOME/AE/hold/"
touch -t 202610010900 "$HOME/AE/receipts/spring.20261001T090000Z.scrape.json"
touch -t 202610011630 "$HOME/AE/receipts/spring.20261001T163000Z.scrape.json"
export MJ_CONFIG="$HOME/.config/mograph-jailed/config" MJ_STORE_DIR="$HOME/Library/Application Support/MographJailed" MJ_AUDIT_DIR="$HOME/Library/Logs/MographJailed" MJ_CLI="$RUNTIME"
source "$R/scripts/shell/mj-cli.zsh"
sec() { print -r -- "##### $1"; }
run() { print -r -- "\$ $*"; eval "$@" 2>&1; print; }

sec setup
run 'mj config set versions_dir ~/AE/versions'
run 'mj config set receipts_dir ~/AE/receipts'
run 'mj config set watch_dir ~/AE/projects'
run 'mj config show'
sec snapshot
run 'mj snapshot "Spring Promo"'
run 'mj snapshot "Spring Promo"'
run 'mj versions'
sec check
run 'mj lint last'
run 'mj health ~/AE/receipts/spring.20261001T090000Z.scrape.json --record'
run 'mj health last --record'
run 'mj diff last'
sec batch
run 'mj batch "$R/recipes/check-scrapes.mjrecipe" ~/AE/receipts'
sec search
run 'mj index.add path="$HOME/AE/receipts" | jq -c ".data | {added, updated, unchanged}"'
run 'mj trace.asset format=missing | jq -r ".data.projects[] | .projectPath, (.matches[] | \"  \" + .name, (.uses[] | \"    \" + .paths[0] + \"  (layer \" + .layer + \")\"))"'
run 'mj trace.asset format=font target="Brandon Grotesque" | jq -r ".data.projects[] | .projectPath, (.matches[] | (.uses[] | \"  \" + .paths[0] + \"  (layer \" + .layer + \")\"))"'
run 'mj audit.plugins target=S_Glow | jq -r ".data.projects[].projectPath"'
run 'mj audit.plugins | jq -r ".data.effects[] | \"\\(.matchName)  \\(.projects) project(s)\""'
sec cinema4d
cp "$HOME/AE/hold"/* "$HOME/AE/receipts/"
touch -t 202610020800 "$HOME/AE/receipts"/logo.*; touch -t 202610020900 "$HOME/AE/receipts"/summer.*
run 'mj scene last --summary'
run 'mj scene last'
run 'mj bridge last last'
sec handoff
run 'mj handoff.package path="$HOME/AE/projects/Spring Promo/Spring Promo.aep" input="$HOME/AE/receipts/spring.20261001T163000Z.scrape.json" output="$HOME/AE/out" label=spring_v2 > ~/AE/handoff.json; mj explain ~/AE/handoff.json'
run 'ls ~/AE/out/spring_v2.handoff'
sec status
run 'mj status'
run 'mj notify status'
