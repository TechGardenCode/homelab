# ADR-0004: Kustomize with inline `helmCharts`

**Status:** Accepted · 2025-03

## Context

Most ArgoCD installs pick either Kustomize or Helm. The choice shapes every app's layout. But in practice:

- **Helm** is good for third-party charts with many knobs (cert-manager, external-secrets, ArgoCD itself).
- **Kustomize** is good for composition: overlays, common labels, patching upstream chart output, and supplementing a chart with extra resources (e.g. ExternalSecret beside a Helm-rendered Deployment).

An app that only uses Helm can't easily add a sibling `ExternalSecret` without a post-render hook. A Kustomize overlay that only uses raw manifests can't easily pull in a third-party chart.

## Decision

Use **Kustomize at the top of every app**, with `helmCharts:` blocks referencing either local charts (`helm-charts/generic-service`) or remote charts (cert-manager, external-secrets). ArgoCD is configured with a custom `kustomize-helm` config-management-plugin that runs `kustomize build --enable-helm`.

## Consequences

**Positive:**
- One mental model for every app: `kustomization.yaml` is always the entry point.
- Supplementary resources (ExternalSecret, ConfigMap, NetworkPolicy) sit next to the chart reference.
- Overlays work naturally for per-env patches (dev/prod resource tuning, host overrides).
- The custom plugin is trivial: one wrapper script.

**Negative:**
- `--enable-helm` downloads charts on every ArgoCD sync (cached per revision). Cold caches slow first-sync slightly.
- `kustomize build` doesn't support Helm hooks (`helm.sh/hook`) — any chart depending on hooks must be converted to ArgoCD sync-waves or a PreSync hook. We hit this with CNPG and a few operators; tracked in runbooks.
- Two tools in the pipeline. A PR author has to understand both.

**Rejected alternatives:**
- Pure Helm via ArgoCD's built-in Helm support: loses sibling-resource composition.
- Pure Kustomize with `helmCharts` outputs pre-rendered into files: loses Renovate's ability to update chart versions.
