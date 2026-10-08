# Kollaudo gate for GitHub Actions

Gate a job on [Kollaudo](https://github.com/kollaudo/kollaudo)'s verdict: before a version moves on,
one step asks whether it is healthy where it was tested. The job goes on only on `pass`. A second
action, [`push`](#send-test-results), sends the test results the gate judges.

```yaml
jobs:
  production:
    runs-on: ubuntu-latest
    steps:
      - uses: kollaudo/action@v0
        with:
          url: ${{ vars.KOLLAUDO_URL }}
          token: ${{ secrets.KOLLAUDO_GATE_TOKEN }}
          component: api
          environment: staging
      - run: ./deploy.sh production "$GITHUB_SHA"
```

| Verdict | The step |
|---|---|
| `pass` | succeeds, and the job goes on |
| `fail` | fails: the latest run of a kind of test has failed tests |
| `unknown` | fails: evidence is missing, such as tests that never reported |
| no verdict | fails: Kollaudo didn't answer, or the token or the inputs are wrong |

The summary of the workflow run says why: the verdict in a sentence, then a table with one row for
each kind of test, who sent it and a link to its test run. It also says when an override let the
version through, when the environment runs another version, and when `allow` let the job go on.

## Inputs

| Input | | |
|---|---|---|
| `url` | required | the URL of your Kollaudo server |
| `token` | required | a read token of your Kollaudo project |
| `component` | required | the component, as your CI sends it with `kollaudo push` |
| `environment` | required | where the version was tested: usually the one it comes from, such as `staging` |
| `version` | `github.sha` | the version, as your CI sends it with `kollaudo push` |
| `require` | | kinds of test that must have a run, such as `e2e,smoke`. They add to your policy, never relax it |
| `allow` | | outcomes to let through besides `pass`: `unknown`, `no-verdict`, or both |

| Output | |
|---|---|
| `outcome` | `pass`, `fail`, `unknown` or `no-verdict` |
| `message` | the verdict in a sentence, such as `e2e failed.`, or why there is no verdict, such as `Can't reach Kollaudo at …` |

Later steps can use them, for example to say why a job stopped:

```yaml
      - id: gate
        uses: kollaudo/action@v0
        continue-on-error: true
        with: { url: "${{ vars.KOLLAUDO_URL }}", token: "${{ secrets.KOLLAUDO_GATE_TOKEN }}", component: api, environment: staging }
      - if: steps.gate.outputs.outcome != 'pass'
        env:
          MESSAGE: ${{ steps.gate.outputs.message }} # through the environment, never into the script
        run: echo "Stopped: $MESSAGE"
```

## Send test results

`kollaudo/action/push` sends CTRF or JUnit XML reports to Kollaudo, for a version of a component.
Run it even when tests failed, so that the gate sees them:

```yaml
jobs:
  e2e-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: npx playwright test
      - uses: kollaudo/action/push@v0
        if: ${{ !cancelled() }} # also when tests failed
        with:
          url: ${{ vars.KOLLAUDO_URL }}
          token: ${{ secrets.KOLLAUDO_TOKEN }}
          path: ctrf/ctrf-report.json
          component: frontend
          environment: staging
```

| Input | | |
|---|---|---|
| `url` | required | the URL of your Kollaudo server |
| `token` | required | an ingest token of your Kollaudo project |
| `path` | required | report files, one per line. Glob patterns such as `test-results/**/*.xml` are expanded, and all the files make one test run |
| `component` | required | the component under test |
| `environment` | | where the tests ran. Leave it empty for build-level tests, such as unit tests |
| `kind` | `e2e` | the kind of test: `unit`, `e2e`, `smoke`, `uat`… |
| `version` | `github.sha` | the version under test, the one the gate will ask about |
| `tool` | | the tool that ran the tests, such as `pytest`: JUnit reports don't say it |
| `commit`, `branch`, `tag`, `pull-request` | from the workflow run | where the version comes from |
| `digest` | | the digest of the artifact that was built, such as a container image digest |

The step fails when Kollaudo doesn't store the results, not when tests failed: failing on tests is
the job of the test step. The output `test-run-url` links to the test run, and the summary of the
workflow run says what was sent.

## Tokens

Give the gate its own `read` token, with a name, so that Kollaudo's log of verdicts says which gate
asked, and the gate can't send results:

```bash
kollaudo-server token create <project> --scope read --name github-gate
```

Store it as a secret of the repository or of the environment, such as `KOLLAUDO_GATE_TOKEN`.

For `push`, use an `ingest` token, limited to the components and environments the workflow tests:

```bash
kollaudo-server token create <project> --scope ingest --name github-ci --component frontend --environment staging
```

## Failing closed, and when not to

By default the gate stops whenever it doesn't get a `pass`, including when Kollaudo is down: a gate
that goes ahead without a verdict is no gate
([ADR 0019](https://github.com/kollaudo/kollaudo/blob/main/docs/adr/0019-when-the-gate-is-skipped-or-kollaudo-is-down.md)).
For development and preview environments, you can let missing evidence or an unreachable Kollaudo
through, and the run shows a warning when it does:

```yaml
      - uses: kollaudo/action@v0
        with:
          url: ${{ vars.KOLLAUDO_URL }}
          token: ${{ secrets.KOLLAUDO_GATE_TOKEN }}
          component: api
          environment: dev
          allow: unknown,no-verdict
```

An urgent fix that can't wait for its evidence goes through with an
[override](https://github.com/kollaudo/kollaudo/blob/main/docs/overrides.md) in Kollaudo, not by
editing the gate.

## How it works

The actions are a few lines of shell, and nothing else: they set up Node.js 24, install the Kollaudo
CLI at the version of this release, and run `kollaudo verdict` or `kollaudo push`
([ADR 0020](https://github.com/kollaudo/kollaudo/blob/main/docs/adr/0020-github-action.md)). Read
[`action.yml`](action.yml), [`gate.sh`](gate.sh), [`push/action.yml`](push/action.yml) and
[`push/push.sh`](push/push.sh) before you use them, and pin a commit SHA instead of `v0` to review
every change.

- They set up Node.js 24, which the steps after them in the same job then use. If those need another
  version, set it up again after the action.
- They download the CLI from npm, so the runner needs to reach the npm registry.

Each release of the actions runs the CLI of the same release of Kollaudo, and is tested against it,
in [`test.yml`](.github/workflows/test.yml).

## License

[Apache-2.0](LICENSE)
