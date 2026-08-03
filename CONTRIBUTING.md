# Contributing

Thanks for considering a contribution! The general flow (fork → branch → PR,
issue templates, code of conduct) follows the
[profile-wide contributing guide](https://github.com/KevinDeBenedetti/.github/blob/main/CONTRIBUTING.md);
this page covers what is **specific to k3s-lab**.

## Development setup

```bash
brew install bats-core shellcheck actionlint prek helm
```

Run the checks CI will run:

```bash
bats tests/bats/          # unit tests for every shell library and script
prek run --all-files      # lint hooks (shellcheck, yaml, gitleaks, …)
```

Every shell library in `lib/` has a matching `.bats` file in `tests/bats/` —
a change to one without the other is usually a red flag, and new helpers are
expected to arrive with tests for their failure modes, not just their happy
path.

## Versioning — what you must NOT do

Releases are fully automated with release-please, and versions follow a
deliberate **0.x line**:

- **Never bump `version:` or `appVersion:` in any `charts/*/Chart.yaml`** —
  release-please owns those fields and bumps every chart at each release.
- **Never add a `Release-As:` footer** to a commit.
- Dependency versions (`dependencies[].version`, subchart pins) are the part
  humans — or dedicated automation — edit. The umbrella's pins are aligned by
  an automated PR after each release; `check-umbrella-pins.sh` in CI catches
  any drift.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) — they drive the
changelog and the next version number (`feat:` → minor, `fix:` → patch,
`chore:`/`docs:`/… → no release):

```
feat(charts/platform-traefik): expose dashboard toggle
fix(scripts/check-umbrella-pins.sh): handle single-segment registry paths
```

## Security-sensitive changes

The Traefik/cert-manager/external-secrets versions the charts ship are
security decisions with their own daily advisory watch. If you touch a wrapped
component's version, run the corresponding check before opening the PR:

```bash
scripts/check-traefik-advisories.sh
scripts/check-deployed-charts.sh --only <chart> --chart-version <candidate>
```

For vulnerabilities, see [SECURITY.md](SECURITY.md) — never a public issue.
