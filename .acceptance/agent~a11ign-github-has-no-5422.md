Row a11ign/a11ign#5422: a `gate` workflow on `pull_request`, so a pull request in `a11ign/.github` has a check on its head and a settled head exists for the gate to offer a reviewer. It validates every workflow file the pull request changes with `@action-validator/cli` and passes when none changed. The row's literal command `cd ~/repos/github/.github` reads the primary checkout, which does not hold this file until it merges, and its `grep -q "pull_request"` also matches the header comment, so it cannot tell a removed trigger from a present one; this runs the same three checks from the repository root with the trigger grep anchored.

Acceptance: bash -c 'npx --yes @action-validator/cli@0.6.0 .github/workflows/gate.yml && grep -q "^  gate:" .github/workflows/gate.yml && grep -q "^  pull_request:" .github/workflows/gate.yml'

Mutation: on scratch copies, `gate:` renamed `check:` makes the second grep exit 1; `runz-on:` for `runs-on:` makes action-validator exit 1; `pull_request:` replaced by `push:` makes the third grep exit 1 (the row's unanchored grep still matched 2 comment lines there). The unmutated file exits 0. The job's `run` step was also run at the head of a synthetic merge commit: no workflow file changed exits 0, a changed valid file exits 0, a changed file with `runz-on:` exits 1, a deleted workflow exits 0, a new `.yaml` is validated.

Closes a11ign/a11ign#5422
