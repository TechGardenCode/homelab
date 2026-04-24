# ADR-0005: Renovate over Dependabot

**Status:** Accepted · 2025-02

## Context

Dependency updates cover three things in this repo:

1. Helm chart versions (declared inline inside `kustomization.yaml` `helmCharts:` blocks).
2. Container image digests (base images in Dockerfiles; image tags in values.yaml are bot-managed separately).
3. GitHub Actions versions.

Dependabot's Kubernetes / Helm support is limited — it doesn't parse inline `helmCharts:` blocks, and its custom-manager story is weak. Renovate parses Kustomize + inline Helm natively, supports custom regex managers for anything else, and has richer packageRules for grouping, scheduling, and versioning.

## Decision

Use **Renovate** (GitHub App) with `config:recommended` + homelab-specific packageRules:

- Auto-merge: patch Helm bumps, digest / pin updates, `ghcr.io/techgardencode/*` (in-house images).
- Manual review: Helm minor/major bumps.
- Grouped: `external-dns`, `ingress-nginx`, `step-issuer`, `democratic-csi`, `external-secrets`.
- Pinned: `keycloak < 25.0.0`, `redis < 1.0.0`.
- Schedule: weekdays before 6am.

Config lives in [`renovate.json`](../../renovate.json).

## Consequences

**Positive:**
- Helm chart versions in `kustomization.yaml` are tracked automatically.
- Patch updates merge overnight without human intervention; risky bumps queue with a `manual-review` label.
- Grouping cuts PR noise for multi-instance deployments (e.g. democratic-csi has four instances).
- Version pins hold back upgrades that would require migration work (e.g. Keycloak 25's realm schema changes).

**Negative:**
- Two bot accounts now push to this repo (Renovate + our own `update-image-tag.yml`). Branch hygiene requires occasional cleanup.
- Auto-merge + `validate-and-audit.yml` is the only gate; if CI misses something, it lands on main. Post-merge validation creates a GitHub issue on failure; so far the gap hasn't caused an outage.

**Rejected alternatives:**
- Dependabot: insufficient Helm/Kustomize parsing.
- Manual bumps: no.
