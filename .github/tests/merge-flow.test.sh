#!/usr/bin/env bash
# Behaviour tests for the merge flow (A11-274): each case runs a workflow step's `run:` block AS IT IS WRITTEN in the YAML, so a broken
# `gh api` call, `jq` filter or shell test fails here, where a grep of the file's text would still pass.
#
#   - `auto-arm.yml`'s `flow` step, in both jobs that arm: it may say `ready=true` only when `main`'s rules hold a merge queue, an approving
#     review and the required `gate`. On any other `main` an arm is an immediate merge, so the step must stay closed. `gh` is a stub that
#     prints a fixture of `GET repos/<repo>/rules/branches/main`, so nothing here reaches GitHub.
#   - `gate.yml`'s validate step, on a pull request (the merge of its head into its base) and on a merge-queue entry (`QUEUE_BASE` set):
#     every workflow file the change adds or edits is validated, an earlier commit of a queue entry included, and a diff that cannot be
#     taken fails the job. `npx` is a stub standing in for `@action-validator/cli`: it refuses a file containing `runz-on:`, so the cases
#     test which files the step hands it and what it does with the answers, offline.
#
# Run from the repository root: `bash .github/tests/merge-flow.test.sh`. Needs bash, git, jq and python3 with PyYAML (all on GitHub's Ubuntu runners).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
failures=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# The `run:` block of each step in <job> whose <key> is <value>, written to <out>.<n> (1, 2, ...); prints how many it wrote.
extract_runs() {
  python3 -I - "$@" <<'PY'
import sys, yaml
path, jobs, key, value, out = sys.argv[1:]
workflow = yaml.safe_load(open(path))
written = 0
for job in jobs.split(","):
    for step in workflow["jobs"][job]["steps"]:
        if step.get(key) == value:
            written += 1
            open(f"{out}.{written}", "w").write(step["run"])
print(written)
PY
}

# ---- auto-arm.yml: the `flow` guard ----------------------------------------------------------------------------------------------

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# A stand-in for `gh`: answers exactly the one read the guard makes, from $RULES_FIXTURE, and fails on anything else.
[ "${GH_FAIL:-}" = 1 ] && { echo "gh: HTTP 502" >&2; exit 1; }
[ "$#" -eq 2 ] && [ "$1" = api ] && [ "$2" = "repos/${GH_REPO}/rules/branches/main" ] || { echo "unexpected gh call: $*" >&2; exit 2; }
cat "$RULES_FIXTURE"
STUB
chmod +x "$WORK/bin/gh"

merge_queue='{ "type": "merge_queue", "parameters": { "merge_method": "MERGE" } }'
review() { echo "{ \"type\": \"pull_request\", \"parameters\": { \"required_approving_review_count\": $1 } }"; }
checks() { echo "{ \"type\": \"required_status_checks\", \"parameters\": { \"required_status_checks\": [ { \"context\": \"$1\", \"integration_id\": 15368 } ] } }"; }
deletion='{ "type": "deletion" }'
no_force='{ "type": "non_fast_forward" }'

# name | rules JSON | whether the guard may open
guard_cases=(
  "the whole flow (announcement-emulator's rules)|[$merge_queue, $(review 1), $(checks gate), $deletion, $no_force]|open"
  "no rules at all (a11ign.github.io before the admin acts)|[]|closed"
  "only main-protected (this repository before the admin acts)|[$deletion, $no_force, $(review 1)]|closed"
  "no merge queue|[$(review 1), $(checks gate)]|closed"
  "no approving review required|[$merge_queue, $(review 0), $(checks gate)]|closed"
  "no review rule|[$merge_queue, $(checks gate)]|closed"
  "a required check that is not gate|[$merge_queue, $(review 1), $(checks build)]|closed"
  "no required checks|[$merge_queue, $(review 1)]|closed"
)

count=$(extract_runs "$ROOT/.github/workflows/auto-arm.yml" arm,arm-approved id flow "$WORK/flow")
if [ "$count" = 2 ]; then pass "auto-arm.yml has a flow step in arm and in arm-approved"; else fail "auto-arm.yml: expected 2 flow steps in arm and arm-approved, found $count"; fi

# Each step runs as Actions runs it: `bash -e`, with GITHUB_OUTPUT a file.
run_flow() { # <script> <fixture> [GH_FAIL] -> sets flow_rc and flow_output
  local output="$WORK/github-output"; : > "$output"
  PATH="$WORK/bin:$PATH" GH_REPO=a11ign/example RULES_FIXTURE="$2" GH_FAIL="${3:-}" GITHUB_OUTPUT="$output" \
    bash -e "$1" > "$WORK/flow-stdout" 2>&1
  flow_rc=$?
  flow_output=$(cat "$output")
}

for n in $(seq 1 "$count"); do
  for case in "${guard_cases[@]}"; do
    IFS='|' read -r name rules want <<<"$case"
    printf '%s\n' "$rules" > "$WORK/rules.json"
    run_flow "$WORK/flow.$n" "$WORK/rules.json"
    if [ "$want" = open ]; then
      [ "$flow_rc" = 0 ] && [ "$flow_output" = "ready=true" ] && pass "flow step $n opens on $name" \
        || fail "flow step $n should open on $name (exit $flow_rc, output '$flow_output')"
    else
      [ "$flow_rc" = 0 ] && [ -z "$flow_output" ] && grep -q '::notice::AUTO-ARM: main has no merge flow yet' "$WORK/flow-stdout" \
        && pass "flow step $n stays closed, with a notice, on $name" \
        || fail "flow step $n should stay closed with a notice on $name (exit $flow_rc, output '$flow_output')"
    fi
  done
  # A read that fails must not open the guard: the step fails (red, so it is seen) and writes nothing.
  run_flow "$WORK/flow.$n" "$WORK/rules.json" 1
  [ "$flow_rc" != 0 ] && [ -z "$flow_output" ] && pass "flow step $n fails closed when the rules cannot be read" \
    || fail "flow step $n should fail closed when the rules cannot be read (exit $flow_rc, output '$flow_output')"
done

# ---- gate.yml: the validate step --------------------------------------------------------------------------------------------------

count=$(extract_runs "$ROOT/.github/workflows/gate.yml" gate name "Validate every workflow file the pull request, or the queue entry, changes" "$WORK/validate")
if [ "$count" = 1 ]; then pass "gate.yml has its validate step"; else fail "gate.yml: expected 1 validate step, found $count"; fi
python3 -I -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); on=d.get("on", d.get(True)); sys.exit(0 if "merge_group" in on and "pull_request" in on else 1)' "$ROOT/.github/workflows/gate.yml" \
  && pass "gate.yml runs on pull_request and merge_group" || fail "gate.yml should run on pull_request and merge_group"

cat > "$WORK/bin/npx" <<'STUB'
#!/usr/bin/env bash
# A stand-in for `npx --yes @action-validator/cli@<version> <file>`: refuses a file with `runz-on:`, and records each file it is given.
[ "$1" = --yes ] && [[ "$2" == @action-validator/cli@* ]] && [ "$#" -eq 3 ] || { echo "unexpected npx call: $*" >&2; exit 2; }
echo "$3" >> "$VALIDATED_LOG"
! grep -q 'runz-on:' "$3"
STUB
chmod +x "$WORK/bin/npx"

valid_workflow='name: x
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi'
broken_workflow="${valid_workflow/runs-on/runz-on}"

# A scratch repository with a base commit (holding $BASE_WORKFLOW, a broken workflow, when it is set), then one commit per
# <path>=valid|broken|deleted|other. `pr` checks out the merge of that branch into
# its base (what `pull_request`'s checkout is); `queue` stays on the entry's head with QUEUE_BASE the base (what `merge_group`'s is).
validate_case() { # <name> <pr|queue> <want exit 0|nonzero> <expected validated files, space separated> <path=kind>...
  local name=$1 mode=$2 want=$3 expected=$4; shift 4
  local repo="$WORK/repo-$name" base
  rm -rf "${repo:?}"; mkdir -p "$repo/.github/workflows"
  git -C "$repo" init -q -b main; git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
  echo base > "$repo/README.md"
  [ -z "${BASE_WORKFLOW:-}" ] || printf '%s\n' "$broken_workflow" > "$repo/$BASE_WORKFLOW"
  git -C "$repo" add -A; git -C "$repo" commit -qm base; base=$(git -C "$repo" rev-parse HEAD)
  for spec in "$@"; do
    mkdir -p "$repo/$(dirname "${spec%%=*}")" # `git rm` of a directory's last file removes the directory
    case "${spec#*=}" in
      deleted) git -C "$repo" rm -q "${spec%%=*}" ;;
      valid) printf '%s\n' "$valid_workflow" > "$repo/${spec%%=*}" ;;
      broken) printf '%s\n' "$broken_workflow" > "$repo/${spec%%=*}" ;;
      *) echo other > "$repo/${spec%%=*}" ;;
    esac
    git -C "$repo" add -A; git -C "$repo" commit -qm "change ${spec%%=*}"
  done
  local queue_base=""
  if [ "$mode" = pr ]; then
    local head; head=$(git -C "$repo" rev-parse HEAD); git -C "$repo" checkout -q "$base"; git -C "$repo" merge -q --no-ff -m merge "$head"
  else
    queue_base=$base
  fi
  : > "$WORK/validated"
  (cd "$repo" && PATH="$WORK/bin:$PATH" QUEUE_BASE="$queue_base" VALIDATED_LOG="$WORK/validated" bash -e "$WORK/validate.1" > /dev/null 2>&1)
  local rc=$? validated; validated=$(sort "$WORK/validated" | tr '\n' ' ' | sed 's/ $//')
  local ok=1
  if [ "$want" = 0 ]; then [ "$rc" = 0 ] || ok=0; else [ "$rc" != 0 ] || ok=0; fi
  [ "$validated" = "$expected" ] || ok=0
  [ "$ok" = 1 ] && pass "validate: $name" || fail "validate: $name (exit $rc, validated '$validated'; want exit $want, validated '$expected')"
}

W=.github/workflows
validate_case "a pull request that changes no workflow" pr 0 "" other.txt=other
validate_case "a pull request with a valid workflow" pr 0 "$W/a.yml" $W/a.yml=valid
validate_case "a pull request with a broken workflow" pr nonzero "$W/a.yml" $W/a.yml=broken
validate_case "a pull request with two broken workflows validates both" pr nonzero "$W/a.yml $W/b.yaml" $W/a.yml=broken $W/b.yaml=broken
validate_case "a queue entry that changes no workflow" queue 0 "" other.txt=other
validate_case "a queue entry of two commits, both valid" queue 0 "$W/a.yml $W/b.yml" $W/a.yml=valid $W/b.yml=valid
validate_case "a queue entry whose broken workflow is in its first commit" queue nonzero "$W/a.yml $W/b.yml" $W/a.yml=broken $W/b.yml=valid
validate_case "a queue entry whose broken workflow is in its last commit" queue nonzero "$W/a.yml $W/b.yaml" $W/a.yml=valid $W/b.yaml=broken
# A deleted workflow leaves nothing to validate, even one that was broken before the change deleted it.
BASE_WORKFLOW=$W/old.yml validate_case "a pull request that deletes a workflow" pr 0 "" $W/old.yml=deleted
BASE_WORKFLOW=$W/old.yml validate_case "a queue entry that deletes a workflow and adds a valid one" queue 0 "$W/a.yml" $W/old.yml=deleted $W/a.yml=valid

# A base the checkout does not hold: the diff fails, and so must the job (never "No workflow file changed").
repo="$WORK/repo-unreachable"; mkdir -p "$repo"; git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
echo x > "$repo/f"; git -C "$repo" add -A; git -C "$repo" commit -qm x
(cd "$repo" && PATH="$WORK/bin:$PATH" QUEUE_BASE=0123456789abcdef0123456789abcdef01234567 VALIDATED_LOG="$WORK/validated" bash -e "$WORK/validate.1" > /dev/null 2>&1)
[ "$?" != 0 ] && pass "validate: a queue base the checkout cannot reach fails the job" || fail "validate: a queue base the checkout cannot reach should fail the job (exit 0)"

echo
if [ "$failures" -eq 0 ]; then echo "merge-flow tests: all passed"; else echo "merge-flow tests: $failures failed"; fi
[ "$failures" -eq 0 ]
