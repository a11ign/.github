Row a11ign/a11ign#5221: the Renovate engine workflow, its org Octo STS policy and the shared preset, with no manager declared and no repository enrolled. The row's literal command `npx --yes actionlint` cannot pass (the npm package `actionlint` is a wasm library with no bin) and its `cd ~/repos/.github` names a directory that does not exist (the checkout is `~/repos/github`); this runs the same two checks with a package that has a bin.

Acceptance: bash -c 'npx --yes @action-validator/cli .github/workflows/renovate.yml && npx --yes --package renovate renovate-config-validator default.json'

Mutation: both validators were measured on scratch copies: `runz-on:` for `runs-on:` in the workflow makes action-validator exit 1, and `"prConcurrentLimit": "one"` in default.json makes renovate-config-validator report that the option should be an integer. The unmutated files exit 0.

Closes a11ign/a11ign#5221
