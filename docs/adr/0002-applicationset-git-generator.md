# ADR-0002: ArgoCD ApplicationSet with git directory generator

**Status:** Accepted · 2025-02

## Context

ArgoCD needs to know about every workload. Three common patterns:

1. **One `Application` YAML per workload**, committed alongside manifests.
2. **App-of-apps** — a parent Application whose templates generate child Applications.
3. **ApplicationSet** with a generator (git, list, cluster, etc.) that produces Applications dynamically.

With ~60+ workloads across 4 clusters, pattern 1 means maintaining ~240 copies of the same boilerplate. Pattern 2 works but still leaves a single YAML to update per app.

## Decision

Use **ApplicationSet with the git directory generator**. A single generator block per cluster scans `kubernetes/clusters/<cluster>/**/*` and produces one Application per leaf directory containing a `kustomization.yaml`.

Application name convention: `{cluster}.{namespace}.{basenameNormalized}`, derived from the path.

## Consequences

**Positive:**
- Adding a new app is just `mkdir` + `kustomization.yaml` + `values.yaml`. No ArgoCD-specific YAML to touch.
- Removing an app deletes the directory; ApplicationSet prunes the Application.
- Consistent naming, consistent sync policy (`selfHeal`, `prune`, `ApplyOutOfSyncOnly`, `ServerSideApply`).
- The generator's `exclude:` field gives a single-line override for in-progress or deliberately-held directories.

**Negative:**
- Per-app overrides (different sync policy, sync waves at the Application level, ignoreDifferences) require either an `exclude:` + hand-written Application, or a generator template with conditionals. So far, no app has needed this.
- Directory-structure changes (moves, renames) cause ArgoCD to prune the old Application and create a new one. Changes to `kubernetes/clusters/**` paths are constrained.
- The `basenameNormalized` function is good-but-not-perfect; apps with dots or underscores in their dir name render awkwardly.

**Rejected alternatives:**
- App-of-apps: still required a per-app YAML, offered no benefit over ApplicationSet for homogeneous workloads.
- Per-app Applications: too much boilerplate for a homelab-sized op load.
