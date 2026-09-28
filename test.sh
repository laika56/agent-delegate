#!/usr/bin/env bash
# Reproduces the guards in delegate.sh with a fake agent, no network, no real model.
#   bash test.sh        → "passed N, failed M", exit 1 if any failed
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1 — $2"; }

# Fake agent: takes the same flags delegate.sh passes, behaviour chosen by FAKE_MODE.
cat > "$TMP/fake-agent" <<'SH'
#!/usr/bin/env bash
dir=""; adddir=""
while [ $# -gt 1 ]; do
  case "$1" in
    -C) dir="$2"; shift 2 ;;
    --add-dir) adddir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
echo "model: fake-1"
[ -n "$adddir" ] && echo "add-dir: $adddir"
cd "$dir" || exit 97
case "${FAKE_MODE:-none}" in
  none)   : ;;
  edit)   echo changed >> work.txt ;;
  commit) echo committed >> work.txt; git add work.txt; git -c user.name=t -c user.email=t@t commit -qm work ;;
  fail)   exit 3 ;;
  stdin)  read -r line; echo "read-returned:${line:-EOF}" ;;
esac
exit 0
SH
chmod +x "$TMP/fake-agent"

export AGENT_CMD="$TMP/fake-agent" AGENT_EFFORT_FLAG="--noop" AGENT_SANDBOX_FLAG="--noop" \
       AGENT_CONFIG_GREP="^model:"

new_repo() {  # fresh repo with a committed spec
  local r="$TMP/$1"; mkdir -p "$r"; git -C "$r" init -q
  echo "# spec" > "$r/spec.md"; echo "base" > "$r/work.txt"
  printf '.delegate-runs/\n' > "$r/.gitignore"
  git -C "$r" add -A; git -C "$r" -c user.name=t -c user.email=t@t commit -qm init
  echo "$r"
}
run() { bash "$HERE/delegate.sh" "$@" >"$TMP/out" 2>&1; echo $?; }

echo "delegate.sh"
[ "$(run)" = 64 ] && ok "no arguments → 64" || bad "no arguments" "expected 64"
[ "$(run "$TMP/missing" spec.md)" = 66 ] && ok "missing project → 66" || bad "missing project" "expected 66"
R=$(new_repo r1)
[ "$(run "$R" nope.md)" = 66 ] && ok "missing spec → 66" || bad "missing spec" "expected 66"
[ "$(FAKE_MODE=none run "$R" spec.md)" = 65 ] && ok "exit 0 with no change → 65" || bad "no-op" "expected 65"
[ "$(FAKE_MODE=edit run "$R" spec.md)" = 0 ] && ok "working-tree change → 0" || bad "edit" "expected 0"
R=$(new_repo r2)
[ "$(FAKE_MODE=commit run "$R" spec.md)" = 0 ] && ok "commit only (clean tree, HEAD moved) → 0" || bad "commit" "expected 0"
R=$(new_repo r3)
[ "$(FAKE_MODE=fail run "$R" spec.md)" = 3 ] && ok "agent's own non-zero exit passes through" || bad "fail" "expected 3"
R=$(new_repo r4)
code=$(FAKE_MODE=stdin perl -e 'alarm 20; exec @ARGV' bash "$HERE/delegate.sh" "$R" spec.md >"$TMP/out" 2>&1; echo $?)
grep -q "read-returned:EOF" "$R"/.delegate-runs/*.log && ok "stdin is closed — a reading agent gets EOF, no hang" || bad "stdin" "exit $code, no EOF line"
R=$(new_repo r5)
[ "$(FAKE_MODE=edit run "$R" spec.md)" = 0 ] && grep -q "^model: fake-1" "$TMP/out" \
  && ok "agent config header is echoed back" || bad "config header" "no 'model:' line in output"
R=$(new_repo r6); git -C "$R" worktree add -q "$TMP/wt" -b t >/dev/null 2>&1
FAKE_MODE=edit run "$TMP/wt" spec.md >/dev/null
common="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"
grep -q "add-dir: $common" "$TMP/wt"/.delegate-runs/*.log && ok "worktree → shared git dir granted" || bad "worktree" "no add-dir for $common"

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
