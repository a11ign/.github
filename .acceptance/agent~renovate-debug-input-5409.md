Row a11ign/a11ign#5409: a `log-level` dispatch input for the Renovate engine, so a dispatch can read WHY a run on `a11ign/agent-org` opened no `PROJECT_REF` bump (at `info` the repository is extracted, looked up and finished with no line saying why). The schedule is unchanged: `inputs` is empty there, so `LOG_LEVEL` stays `info`.

Acceptance: bash -c 'npx --yes @action-validator/cli .github/workflows/renovate.yml && grep -q "LOG_LEVEL: .{{ inputs.log-level || .info. }}" .github/workflows/renovate.yml && grep -q "^      log-level:" .github/workflows/renovate.yml'

Mutation: on scratch copies, `runz-on:` for `runs-on:` makes action-validator exit 1; `LOG_LEVEL: info` back in place of the expression makes the first grep exit 1; removing the `log-level:` input makes the second grep exit 1. The unmutated file exits 0.

Closes: none -- evidence step for a11ign/a11ign#5409; the row closes on the fix that follows it
