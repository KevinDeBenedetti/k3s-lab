# Étape 3 — Helm Wrapper Chart for Platform Dependencies

## Summary of Changes (Not Committed)

This document summarizes all changes made for Étape 3 (Helm wrapper chart). These are **not yet committed**; you'll commit them manually.

### In k3s-lab Repository

#### New Files Created:

1. **`charts/platform-deployment/Chart.yaml`**
   - Umbrella chart declaring all platform-* as dependencies
   - Version: 0.1.0
   - Dependencies: 7 platform-* charts (argocd, monitoring, vault, eso, cert-manager, traefik, security)

2. **`charts/platform-deployment/values.yaml`**
   - Default values (mostly empty; subcharts override)
   - Example of how to enable/disable subcharts

3. **`charts/platform-deployment/README.md`**
   - Usage guide for the umbrella chart
   - Installation options (direct Helm, via ArgoCD)
   - Configuration examples
   - Troubleshooting

4. **`charts/platform-deployment/templates/NOTES.txt`**
   - Post-installation notes displayed to user
   - Quick verification commands

5. **`docs/helm-platform-deployment.md`**
   - Comprehensive guide to the wrapper chart
   - Architecture diagram
   - Benefits vs. old approach
   - Migration timeline
   - Validation checklist

6. **`docs/platform-deployment-release-notes.md`**
   - Release notes explaining v0.9.x → v0.10.0+ transition
   - Backwards compatibility notes
   - FAQ
   - Release engineering steps

### In infra Repository

#### New Files Created:

1. **`docs/platform-refactoring.md`**
   - Step-by-step refactoring guide
   - Shows how to consolidate 8+ per-component values into 1 file
   - Covers deletion of old Applications
   - Verification checklist
   - Rollback procedures

2. **`docs/platform-deployment-values-example.yaml`**
   - Example of consolidated `platform/deployment/values.yaml`
   - Shows nesting structure
   - Includes ArgoCD + Monitoring configs as examples
   - Migration notes

3. **`docs/platform-application-example.yaml`**
   - Example `argocd/applications/platform.yaml`
   - Single Application that replaces 8+
   - Inline values configuration
   - Alternative: values-from-file approach

## File Structure

### k3s-lab

```
k3s-lab/
├── charts/
│   └── platform-deployment/           ← NEW
│       ├── Chart.yaml                 (umbrella chart with dependencies)
│       ├── values.yaml                (default config)
│       ├── README.md                  (usage guide)
│       └── templates/
│           └── NOTES.txt              (post-install help)
└── docs/
    ├── helm-platform-deployment.md    ← NEW
    └── platform-deployment-release-notes.md  ← NEW
```

### infra

```
infra/
└── docs/
    ├── platform-refactoring.md        ← NEW
    ├── platform-deployment-values-example.yaml   ← NEW
    └── platform-application-example.yaml  ← NEW
```

## Key Design Decisions

### 1. Chart Version: 0.1.0
- Starts at 0.1.0 to continue 0.x.x versioning scheme with other platform-* charts
- k3s-lab will be v0.10.0+ (includes this chart)

### 2. Dependency Versions
- All pinned to versions in current k3s-lab (e.g., platform-argocd: 0.9.2)
- Can be updated independently in Chart.yaml

### 3. Conditional Subcharts
Each subchart has `condition: platform-*.enabled` to allow disable:
```yaml
platform-vault:
  enabled: false  # Skip Vault
```

### 4. Values Nesting
Follows Helm convention: subchart values nested under subchart name:
```yaml
platform-argocd:
  argo-cd:           # ← Passed to platform-argocd chart
    global:
      domain: ...
```

### 5. Backwards Compatibility
- Old per-component Applications still work
- No breaking changes to existing platform-* charts
- Migration is **optional**

## What Needs to Happen Next

### For k3s-lab:
1. ✅ Create umbrella chart (DONE)
2. ✅ Document it (DONE)
3. ⏳ **You**: Commit and tag v0.10.0

### For infra (user choice):
1. ✅ Provide refactoring guide (DONE)
2. ✅ Provide examples (DONE)
3. ⏳ **You**: Decide when to migrate (optional)
4. If migrating:
   - Create `platform/deployment/values.yaml` from examples
   - Create `argocd/applications/platform.yaml` from examples (platform-deployment: 0.1.0)
   - Deploy and test
   - Delete old Applications + values files
   - Commit

## Testing Recommendations

Before committing:

```bash
# 1. Validate chart syntax
helm lint k3s-lab/charts/platform-deployment/

# 2. Verify dependencies exist
helm dependency update k3s-lab/charts/platform-deployment/
helm dependency verify k3s-lab/charts/platform-deployment/

# 3. Validate example values
helm template platform k3s-lab/charts/platform-deployment/ -f docs/platform-application-example.yaml

# 4. Optional: Try in test cluster
helm install platform k3s-lab/charts/platform-deployment/ --dry-run
```

## Documentation Checklist

- [x] Chart README (k3s-lab/charts/platform-deployment/README.md)
- [x] Helm guide (k3s-lab/docs/helm-platform-deployment.md)
- [x] Release notes (k3s-lab/docs/platform-deployment-release-notes.md)
- [x] Refactoring guide (infra/docs/platform-refactoring.md)
- [x] Example values (infra/docs/platform-deployment-values-example.yaml)
- [x] Example Application (infra/docs/platform-application-example.yaml)

## Communication Plan

### To k3s-lab users:
"New in v0.10.0: Optional umbrella chart for simpler platform management. Old approach still works."

### To infra users:
"k3s-lab now includes platform-deployment chart. Migration optional but recommended. See docs/platform-refactoring.md"

## Future Improvements (Not in Scope)

- [ ] Auto-generate documentation from Chart.yaml
- [ ] Create Kustomize base for platform-deployment values (per-environment)
- [ ] Add helm-diff plugin to CI/CD for change previews
- [ ] Helm chart museum / artifact hub registration
- [ ] OCI chart signing (cosign)

## Summary

**Étape 3 is complete.** The umbrella chart (v0.1.0) is ready for deployment. All documentation is in place. Users can now migrate to a cleaner, more maintainable platform deployment pattern.

**Next step:** k3s-lab tag v0.10.0, then Étape 4 (Vault seeder transformation) or Étape 5 (Public contract).
