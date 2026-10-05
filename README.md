# Kollaudo gate for GitHub Actions

Gate a job on [Kollaudo](https://github.com/kollaudo/kollaudo)'s verdict: before a version moves on,
one step asks whether it is healthy where it was tested. The job goes on only on `pass`.

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

The verdict, its reasons and the links to the test runs are in the log of the step and in the
summary of the workflow run.

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

The output `outcome` is `pass`, `fail`, `unknown` or `no-verdict`.

## Tokens

Give the gate its own `read` token, with a name, so that Kollaudo's log of verdicts says which gate
asked, and the gate can't send results:

```bash
kollaudo-server token create <project> --scope read --name github-gate
```

Store it as a secret of the repository or of the environment, such as `KOLLAUDO_GATE_TOKEN`.

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

The action is a few lines of shell, and nothing else: it sets up Node.js 24, installs the Kollaudo
CLI at the version of this release, and runs `kollaudo verdict`
([ADR 0020](https://github.com/kollaudo/kollaudo/blob/main/docs/adr/0020-github-action.md)). Read
[`action.yml`](action.yml) and [`gate.sh`](gate.sh) before you use it, and pin a commit SHA instead of
`v0` to review every change.

- It sets up Node.js 24, which steps after it in the same job then use. If they need another
  version, set it up again after the gate.
- It downloads the CLI from npm, so the runner needs to reach the npm registry.

Each release of the action runs the CLI of the same release of Kollaudo. It is tested against that
release, in [`test.yml`](.github/workflows/test.yml).

## License

[Apache-2.0](LICENSE)
