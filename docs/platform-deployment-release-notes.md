# Platform Deployment — Release Notes & Transition

## Overview

This document explains the introduction of the `platform-deployment` umbrella chart in k3s-lab v0.10.0+. This is an **additive feature** — no breaking changes.

## Version History

### v0.9.x (Before)

**Structure:**
- Individual platform-* charts (platform-argocd, platform-monitoring, platform-vault, etc.)
- infra consumes each via separate Applications
- Configuration scattered across `platform/*/values.yaml`

**Current state:** All users currently here.

### v0.10.0+ (Now)

**New feature:** `charts/platform-deployment/` umbrella chart (v0.1.0)

**What's new:**
- ✅ `charts/platform-deployment/Chart.yaml` (aggregates all platform-* as dependencies)
- ✅ `charts/platform-deployment/values.yaml` (default config)
- ✅ Documentation: `docs/helm-platform-deployment.md`

**Backwards compatible:** Yes!
- Existing Applications still work
- Old per-component deployments continue to work
- You can mix old (separate Applications) and new (umbrella) in the same cluster

**Migration optional:** You can stay on v0.9.x deployment forever, or migrate to umbrella chart when ready.

## Migration Path

### Minimal effort (stay on v0.9.x infrastructure)

Just pull v0.10.0+:

```bash
cd vendor/k3s-lab
git fetch origin
git checkout v0.10.0+  # or: main
```

No changes to infra needed. Your Applications still deploy the individual platform-* charts.

### Full refactoring (migrate to umbrella chart)

If you want the benefits (single Application, Helm dependency management):

**Phase 1:** Create new infrastructure
- Create `infra/platform/deployment/values.yaml` (consolidate all values)
- Create `argocd/applications/platform.yaml` (single umbrella Application)

**Phase 2:** Deploy and verify
- Deploy platform.yaml alongside existing Applications
- All subcharts deploy (duplicate of existing)
- Verify everything is running

**Phase 3:** Cutover
- Delete old Applications (argocd.yaml, monitoring.yaml, etc.)
- Helm release stabilizes
- Old Helm releases are orphaned (safe to delete later)

**Phase 4:** Cleanup
- Delete `platform/*/` directories (values files)
- Keep only `platform/deployment/` + `platform/security/` + `platform/prometheus/`
- Commit cleanup

## Benefits After Migration

| Aspect       | Before                  | After             |
| ------------ | ----------------------- | ----------------- |
| Applications | 8+ separate CRDs        | 1 CRD (platform)  |
| Values files | 8+ scattered            | 1 consolidated    |
| Dependencies | Manual version tracking | Helm-managed      |
| Update all   | Edit 8+ files           | 1 Chart.yaml      |
| Troubleshoot | Check 8 statuses        | 1 `helm status`   |
| Rollback     | 8 separate rollbacks    | 1 `helm rollback` |

## Compatibility Matrix

| infra version     | k3s-lab version | Works? | Notes                                     |
| ----------------- | --------------- | ------ | ----------------------------------------- |
| v0.x              | v0.9.x          | ✅ Yes  | Status quo (no umbrella chart)            |
| v0.x              | v0.10.0+        | ✅ Yes  | Umbrella chart available but not required |
| v0.x (refactored) | v0.10.0+        | ✅ Yes  | Uses umbrella chart                       |
| v0.x (refactored) | v0.9.x          | ❌ No   | Missing platform-deployment chart         |

## Timeline Recommendations

**Immediate (Week 1):**
- Tag k3s-lab v0.10.0 with platform-deployment chart
- Announce: "Optional umbrella chart available for infra users"

**Near-term (Week 2-4):**
- Create example Applications
- Document migration steps
- Test in staging

**Mid-term (Month 2):**
- If successful in staging, migrate production
- Monitor for issues
- Gather feedback

**Long-term (Month 3+):**
- Deprecate per-component Applications in docs
- Recommend umbrella chart for new users
- Consider removing old per-component Application examples

## Testing Checklist

Before releasing v0.10.0:

- [ ] `helm lint k3s-lab/charts/platform-deployment`
- [ ] `helm dependency update` works
- [ ] `helm template` generates valid YAML
- [ ] All subcharts in Chart.yaml are available at specified versions
- [ ] Example values validate without errors
- [ ] Example Application applies to cluster without errors
- [ ] All pods become Running
- [ ] ArgoCD UI is accessible
- [ ] Grafana is accessible
- [ ] `helm list` shows platform release
- [ ] `helm status platform-deployment` succeeds
- [ ] Rollback works: `helm rollback platform-deployment 1`
- [ ] Update works: `helm upgrade platform-deployment ...`

## FAQ

### Q: Should I migrate to the umbrella chart immediately?

A: No. It's optional. If your current setup (v0.9.x + separate Applications) is working, stay on it. Migrate when you're ready for the benefits.

### Q: Can I have mixed deployments (some umbrella, some separate)?

A: Technically yes, but confusing. Better to commit to one approach cluster-wide.

### Q: How do I know if migration went well?

Run validation checklist above. All subcharts should be Running and synced.

### Q: What if I break something during migration?

You have multiple recovery options:
1. Rollback via Helm: `helm rollback platform-deployment <REV>`
2. Restore from backup: `kubectl replace -f backup-applications.yaml`
3. Redeploy old per-component Applications: `kubectl apply -f old-apps/`

### Q: Can I use umbrella chart on older infra?

The umbrella chart is in k3s-lab v0.10.0+, which requires infra to pull that version. So yes, any infra version can consume v0.10.0+ k3s-lab.

## Release Engineering

### Creating v0.10.0 tag:

```bash
git tag -a v0.10.0 -m "feat: Add platform-deployment umbrella chart

- New chart: k3s-lab/charts/platform-deployment/ (aggregates all platform-* subcharts)
- Documentation: helm-platform-deployment.md
- Example Application + values in infra documentation
- Backwards compatible; migration optional"

git push origin v0.10.0
```

### Documentation updates:

- [ ] Update `docs/getting-started.md` to mention umbrella chart option
- [ ] Add `docs/helm-platform-deployment.md` to table of contents
- [ ] Link to platform-deployment README in charts directory
- [ ] Add `charts/platform-deployment/README.md`

## Announcements

### For infra users:

> **New in k3s-lab v0.10.0:** Optional `platform-deployment` umbrella chart combines all platform components into a single Helm release, making version management and rollbacks easier.
>
> Old approach (separate Applications) continues to work. See [migration guide](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/docs/helm-platform-deployment.md).

### For new users:

> Start with k3s-lab v0.10.0+, which includes the modern umbrella chart deployment pattern. See [platform-deployment README](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-deployment/README.md).
