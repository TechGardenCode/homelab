# ADR-0006: Separate `core` hub cluster

**Status:** Accepted · 2025-02

## Context

ArgoCD can manage workloads on any cluster it can reach, including the one it runs on. The simplest topology is one cluster that runs everything: GitOps controller, databases, workloads, observability. Multi-cluster adds cost.

But a homelab has exactly the same blast-radius concern as a real org: if the workload cluster goes down, you don't want GitOps down with it. The cost of a second cluster in a homelab is small (Talos + three small VMs); the insulation is meaningful.

## Decision

Run **`1276-core` as a dedicated hub cluster**. It hosts:

- ArgoCD (controllers + UI + repo-server)
- Shared platform services: Envoy Gateway, MetalLB, PKI (step-ca + step-issuer), democratic-csi
- Observability that shouldn't depend on workload-cluster health: GlitchTip, OpenPanel
- Cluster-ops: priority classes, etcd snapshots, backup jobs

`1276-dev` and `1276-prod` run workloads only. They register with `1276-core`'s ArgoCD via cluster-access secrets (stored in Bitwarden, synced via external-secrets).

## Consequences

**Positive:**
- Workload cluster upgrades, node drains, or complete rebuilds don't interrupt GitOps.
- Error tracking and product analytics stay available during workload-cluster incidents — so we can actually see what broke.
- `1276-core`'s own updates go through ArgoCD (self-manages), but its control plane is stable enough that a brief GitOps pause during its own rollout is acceptable.

**Negative:**
- 3x the cluster-lifecycle work (Talos upgrades, cert rotations, etc.) for hub + two workload clusters.
- Cross-cluster networking requires MetalLB VIPs + DNS, which we needed anyway for external ingress.
- One extra piece of state to back up (ArgoCD config, though it's all declarative).

**Rejected alternative:**
- Single cluster: ruled out by the workload-cluster-failure scenario.
