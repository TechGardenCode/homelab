# ADR-0003: Local `generic-service` Helm chart

**Status:** Accepted · 2025-03

## Context

Every application in this homelab is shaped roughly the same: a `Deployment`, a `Service`, an `HTTPRoute` (Gateway API), an optional `HPA`, an `ExternalSecret` pulling from Bitwarden, and per-environment resource tuning. Options:

1. Plain manifests per app — duplication, drift.
2. A per-app Helm chart — one chart repo per app, overhead for ~10 apps.
3. A single shared local chart that every app consumes via Kustomize's inline `helmCharts:`.

## Decision

Maintain a single `generic-service` chart in [`helm-charts/generic-service/`](../../helm-charts/generic-service/). Every application directory references it via `helmCharts:` in its `kustomization.yaml`, overriding the chart's defaults with a local `values.yaml`.

## Consequences

**Positive:**
- One place to evolve the deployment pattern. Adding a new capability (e.g. ServiceMonitor, NetworkPolicy template) is one chart change, rolls out to every app next sync.
- Every app looks the same on disk: `kustomization.yaml` + `values.yaml`. Zero-to-running for a new app is minutes.
- The chart is versioned in-tree — no Helm repo to maintain, no tagging dance.
- CI validates the chart on every PR with `helm template`.

**Negative:**
- The chart accumulates flags as apps demand variations (cronJobs, initContainers, extra envFroms). It's grown gracefully so far but will eventually need splitting.
- "One chart to rule them all" means a regression in the chart breaks every app simultaneously. Mitigated by the per-cluster `kustomize build --enable-helm` CI matrix that catches template-time errors.

**Rejected alternatives:**
- Per-app charts: too much boilerplate for homogeneous apps.
- Library chart (helper-only): apps would still duplicate top-level resources. Defeats the point.
