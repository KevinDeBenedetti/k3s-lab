# platform-base

Foundation chart: it creates the namespaces every other platform chart installs
into, and applies the cluster-wide defaults those namespaces inherit.

| | |
|---|---|
| Subcharts | none — this chart owns all its templates |
| Creates | 8 namespaces, a `LimitRange` and 2 `NetworkPolicy` per namespace |
| Per-cluster overrides | `infra/platform/base/values.yaml` |

> [!IMPORTANT]
> Install this **first**. The other `platform-*` charts assume their namespace
> already exists with the right Pod Security Standards labels; they do not
> create it themselves.

## What it creates

For each entry in `namespaces`:

- the **namespace**, labelled with Pod Security Standards
  (`pod-security.kubernetes.io/enforce|audit|warn`);
- a **`LimitRange`** named from `limitRange`, so a pod that specifies nothing
  still gets a request and a limit;
- **`default-deny-all`** and **`allow-dns`** `NetworkPolicy` objects — except in
  `ingress`, which is deliberately skipped because Traefik must be reachable
  from outside the cluster.

That last exception is the one to remember: every namespace is deny-by-default
for both ingress and egress, with only DNS (UDP/TCP 53) allowed out. A workload
that needs to reach anything else needs its own `NetworkPolicy`, and the symptom
of forgetting is a connection timeout rather than a refusal.

## Pod Security Standards levels

| Namespace | enforce | Why |
|---|---|---|
| `apps` | `restricted` | application workloads, no reason to be privileged |
| `ingress` | `baseline` | Traefik binds host ports |
| `monitoring` | `baseline` | node-level collectors need host access |
| `cert-manager`, `vault`, `external-dns`, `external-secrets`, `auth` | `restricted` | |

`audit` and `warn` are set to `restricted` everywhere, including where `enforce`
is only `baseline` — so a `baseline` namespace still reports what would fail
under `restricted` without blocking it.

## Values

| Key | Default | Note |
|---|---|---|
| `namespaces[].name` | 8 namespaces | see the table above |
| `namespaces[].pss.enforce` | `restricted` / `baseline` | Pod Security Standards level |
| `namespaces[].labels` | `environment: production` on `apps` | extra labels, optional |
| `limitRange.default` | `200m` CPU, `256Mi` | limit applied when a pod omits one |
| `limitRange.defaultRequest` | `50m` CPU, `64Mi` | request applied when a pod omits one |
| `limitRange.max` | `2` CPU, `2Gi` | rejects anything larger |

Adding a namespace here is enough to get the LimitRange and the NetworkPolicies
with it; there is nothing else to wire up.

## See also

- [`platform-security`](../platform-security/README.md) — Kyverno policies that enforce a similar baseline at admission
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
