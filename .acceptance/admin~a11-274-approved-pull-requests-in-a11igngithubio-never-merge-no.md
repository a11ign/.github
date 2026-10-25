A11-274, step 1 of 4 (`.github`): the merge flow A11-237 gave announcement-emulator. `gate.yml` now also runs on `merge_group`, and on a queue entry it validates every workflow file changed between the entry's base (`merge_group.base_sha`) and its head, since a queue entry has no pull request diff. On a pull request it does what it did, except that a `git diff` that fails now fails the job instead of reading as no workflow changed. `.github/workflows/auto-arm.yml` is announcement-emulator's, with comments adapted and one guard step per job: it arms nothing until `main`'s rules hold a merge queue, a required review and the required `gate`, because on an unprotected branch an arm is an immediate merge. `.github/chainguard/auto-arm.sts.yaml` is its Octo STS policy, bound to this repository's immutable id and to `main`'s `auto-arm.yml`; because this is the organisation's policy repository, Octo STS reads it as an organisation policy, so it names `repositories: [.github]` and reaches this repository alone. `.github/rulesets/merge-queue-main.json` is byte-identical to announcement-emulator's; `main-protected` stays beside it. The ruleset and `allow_auto_merge` take effect when the chairman session applies them after merge (the pull request body has the commands).

Acceptance:

```bash
# every changed workflow file is valid
npx --yes @action-validator/cli@0.6.0 .github/workflows/gate.yml
npx --yes @action-validator/cli@0.6.0 .github/workflows/auto-arm.yml
# the ruleset is byte-identical to announcement-emulator's
cmp .github/rulesets/merge-queue-main.json <(gh api repos/a11ign/announcement-emulator/contents/.github/rulesets/merge-queue-main.json --jq .content | base64 -d)
# auto-arm.yml is announcement-emulator's, line for line, once comments and the A11-274 guard (one `flow` step per job, and the `if:` it sets) are set aside
diff <(gh api repos/a11ign/announcement-emulator/contents/.github/workflows/auto-arm.yml --jq .content | base64 -d | grep -v '^ *#') <(grep -v '^ *#' .github/workflows/auto-arm.yml | sed "/- name: Read whether main has the merge flow/,/^          fi\$/d; /^        if: steps.flow.outputs.ready == 'true'\$/d")
# the guard is in both jobs, and each arming step waits on it
grep -c '^        id: flow$' .github/workflows/auto-arm.yml | grep -qx 2
grep -c "^        if: steps.flow.outputs.ready == 'true'$" .github/workflows/auto-arm.yml | grep -qx 2
# the policy's subject names this repository's own immutable id, its workflow is main's auto-arm.yml, and it reaches this repository alone
grep -qxF "subject_pattern: repo:a11ign@320310787/\.github@$(gh api repos/a11ign/.github --jq .id):(pull_request|ref:refs/heads/main)" .github/chainguard/auto-arm.sts.yaml
grep -qxF '  job_workflow_ref: a11ign/\.github/\.github/workflows/auto-arm\.yml@refs/heads/main' .github/chainguard/auto-arm.sts.yaml
diff <(sed -n '/^repositories:/,$p' .github/chainguard/auto-arm.sts.yaml) <(printf 'repositories:\n  - .github\n')
# gate runs in the merge queue, against the entry's base
grep -qx '  merge_group:' .github/workflows/gate.yml
grep -qF 'QUEUE_BASE: ${{ github.event.merge_group.base_sha }}' .github/workflows/gate.yml
```
