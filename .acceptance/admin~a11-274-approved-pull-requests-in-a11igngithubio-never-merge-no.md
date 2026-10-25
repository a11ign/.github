A11-274, step 1 of 4 (`.github`): the merge flow A11-237 gave announcement-emulator. `gate.yml` now also runs on `merge_group`, and on a queue entry it validates every workflow file changed between the entry's base (`merge_group.base_sha`) and its head, since a queue entry has no pull request diff. On a pull request it does what it did. `.github/workflows/auto-arm.yml` is announcement-emulator's, with comments adapted. `.github/chainguard/auto-arm.sts.yaml` is its Octo STS policy, bound to this repository's immutable id and to `main`'s `auto-arm.yml`; because this is the organisation's policy repository, Octo STS reads it as an organisation policy, so it names `repositories: [.github]` and reaches this repository alone. `.github/rulesets/merge-queue-main.json` is byte-identical to announcement-emulator's; `main-protected` stays beside it. The ruleset and `allow_auto_merge` take effect when the chairman session applies them after merge (the pull request body has the commands).

Acceptance:

```bash
set -euo pipefail
# every changed workflow file is valid
for f in .github/workflows/gate.yml .github/workflows/auto-arm.yml; do npx --yes @action-validator/cli@0.6.0 "$f"; done
# the ruleset is byte-identical to announcement-emulator's
cmp .github/rulesets/merge-queue-main.json <(gh api repos/a11ign/announcement-emulator/contents/.github/rulesets/merge-queue-main.json --jq .content | base64 -d)
# auto-arm.yml is announcement-emulator's, line for line, once comments are set aside
diff <(grep -v '^ *#' .github/workflows/auto-arm.yml) <(gh api repos/a11ign/announcement-emulator/contents/.github/workflows/auto-arm.yml --jq .content | base64 -d | grep -v '^ *#')
# the policy's subject names this repository's own immutable id, its workflow is main's auto-arm.yml, and it reaches this repository alone
id=$(gh api repos/a11ign/.github --jq .id)
grep -qxF "subject_pattern: repo:a11ign@320310787/\.github@${id}:(pull_request|ref:refs/heads/main)" .github/chainguard/auto-arm.sts.yaml
grep -qxF '  job_workflow_ref: a11ign/\.github/\.github/workflows/auto-arm\.yml@refs/heads/main' .github/chainguard/auto-arm.sts.yaml
test "$(sed -n '/^repositories:/,$p' .github/chainguard/auto-arm.sts.yaml)" = "$(printf 'repositories:\n  - .github')"
# gate runs in the merge queue
grep -qx '  merge_group:' .github/workflows/gate.yml
grep -qF 'QUEUE_BASE: ${{ github.event.merge_group.base_sha }}' .github/workflows/gate.yml
# gate ran green on this head
test "$(gh api "repos/a11ign/.github/commits/$(git rev-parse HEAD)/check-runs?check_name=gate" --jq '.check_runs[0].conclusion')" = success
```
