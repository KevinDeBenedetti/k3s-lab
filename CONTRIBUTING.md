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

- **Never bump `version:` or `appVersion:` in any `charts/*/Chart.yaml`**, nor
  the `platform-*` pins of `platform-deployment` — release-please owns them.
  The whole repository is one release-please component
  (`.github/release/release-please-config.json`) and shares one version:
  every chart and the umbrella's pins move together, in a single release PR.
- **A new chart needs one entry** in `release-please-config.json`: an
  `extra-files` line for its `Chart.yaml` (`$.version`). Without it its version
  stops moving; `release-please-config.bats` and `check-umbrella-pins.sh`
  catch that.
- **Never add a `Release-As:` footer** to a commit.
- Third-party dependency versions (`dependencies[].version` of the non-`platform-*`
  subcharts) are the part humans — or Renovate — edit.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) — they drive the
changelog and the next version number (`feat:` → minor, `fix:` → patch,
`chore:`/`docs:`/… → no release):

```
feat(charts/platform-traefik): expose dashboard toggle
fix(scripts/check-umbrella-pins.sh): handle single-segment registry paths
```

## Security-sensitive changes

The component versions the charts ship are security decisions. Traefik has its
own daily advisory watch; if you touch its version, run the check before
opening the PR:

```bash
scripts/check-traefik-advisories.sh
```

For vulnerabilities, see [SECURITY.md](SECURITY.md) — never a public issue.
