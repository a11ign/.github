## Summary

Row a11ign/a11ign#5221, item 1 of #5153: the Renovate ENGINE and the shared preset. No manager is declared and no repository is enrolled, so a run today touches nothing.

- `.github/workflows/renovate.yml`: hourly `schedule` + `workflow_dispatch`. `octo-sts/action` (pinned v1.1.1, the SHA `consumer-gate-pin.yml` uses) mints the token under the org policy; `renovatebot/github-action` pinned to v46.3.8's full SHA runs it. A dispatch defaults to `dry-run: full`. `RENOVATE_REQUIRE_CONFIG=required` + `ONBOARDING=false`: a repository without its own `renovate.json` is skipped, never onboarded. No fallback to `GITHUB_TOKEN`.
- `.github/chainguard/renovate.sts.yaml`: an ORG policy (scope `a11ign`, identity `renovate`). `contents: write`, `pull_requests: write`, `issues: read`, nothing else. `subject` is the immutable-id `sub` of `main` of THIS repository (`.github@1410838089`, read with `gh api repos/a11ign/.github --jq .id`); `job_workflow_ref` and `ref` pinned to `main`; `event_name: schedule|workflow_dispatch`. `repositories:` is the nine-name list `nightly-ruleset-read-org.sts.yaml` carries, because omitting it reaches every repository the App sees.
- `default.json`: `enabled: false`; title `deps: bump <pkg> from <x> to <y>` (the shape `dependency-pr-body.yml` parses); `prConcurrentLimit: 1`; `automerge` through `platformAutomerge` so GitHub's own auto-merge, the approving review and the queue still decide. Two `packageRules` stop automerge for a major bump and a `0.x` bump, mirroring the rule `dependency-pr-body.yml` already states.

Flag: a repository's own `renovate.json` (`enabled`, default off). Revert: `false`, or disable the workflow.

## Acceptance (as run; the literal row command cannot pass, see below)

```
$ actionlint .github/workflows/renovate.yml          # rhysd/actionlint 1.7.12 release binary
(exit 0, no output)
$ npx --yes --package renovate renovate-config-validator default.json
INFO: Validating default.json as global config
INFO: Config validated successfully against 1 file(s)
```

**The row's literal Acceptance has a defect.** `npx --yes actionlint` fails with `npm ERR! could not determine executable to run`: the npm package `actionlint` (2.0.6, "Actionlint as wasm") exposes no `bin`. And `cd ~/repos/.github` does not exist: the checkout is `~/repos/github` (key `github` in `project.json`). I ran the same two checks with the real binary in this worktree and did not edit the row (`product-manager` amends rows).

## Mutation evidence

Both validators bite, on scratch copies (the files here were not touched): `"prConcurrentLimit": "one"` makes the validator report ``Configuration option `prConcurrentLimit` should be an integer``; an added `needs: nothing` makes actionlint report `job "renovate" needs job "nothing" which does not exist [job-needs]`. The unmutated files print nothing / `validated successfully`.

## Not proven here

- **No mint has happened.** Done-when 2 (a `workflow_dispatch` dry-run against a11ign/a11ign, log quoted, token step showing an Octo STS mint) needs this on `main` first: a dispatch needs the workflow on the default branch. That reading is the row's, after merge.
- **Whether the App holds `issues: read`, `contents: write`, `pull_requests: write` for these repositories is unread** (the installation's permissions are not visible to this session). If it lacks one, Done-when 3 applies: the row goes `needs:chairman` with a BRIEF, and nobody grants it by hand.
- **`workflows: write` is deliberately absent**, so a bump of a `uses:` pin is refused by GitHub until the github-actions manager row decides that grant (the policy header says why).
- `RENOVATE_DRY_RUN: 'null'` for a real run is the one env value not exercised locally; the first scheduled run is its reading.

platform: Octo STS (org policy), `renovatebot/github-action`, and GitHub's auto-merge are the platform features; no machinery built.

Closes: a11ign/a11ign#5221

🤖 Generated with [Claude Code](https://claude.com/claude-code)
