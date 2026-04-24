# ADR-0001: Talos over kubeadm

**Status:** Accepted · 2025-02

## Context

The homelab needs a Kubernetes distribution that works unattended on heterogeneous hardware (Minisforum mini-PCs, HP EliteDesk, older repurposed boxes). Options considered: kubeadm, k3s, k0s, RKE2, Talos.

Goals:
- Immutable nodes — no SSH, no package drift, no "it worked on the other box"
- Declarative machine config versioned alongside manifests
- Minimal surface area on each node
- Fast disaster recovery (wipe + reapply)
- A single toolchain for bootstrap and upgrades

## Decision

Use **Talos Linux** for all clusters. Machine configs are generated from layered patches (base → profile → cluster → node) and stored in the parent IaC repo (`kian.sh/talos/`). Upgrades are API-driven via `talosctl`.

## Consequences

**Positive:**
- No SSH attack surface; the only entry is a mutually-authenticated API on the node.
- Bootstrapping a new cluster is a single `talosctl apply-config` + `talosctl bootstrap` flow.
- The whole OS is reinstalled on upgrade — no partial-update states.
- Machine config diffs are readable in code review.

**Negative:**
- Standard k8s troubleshooting commands that expect `exec` into the node (e.g. `crictl`) need `talosctl` equivalents; slight learning curve.
- CNI / CSI quirks surface more obviously because there's no fallback shell to paper over them.
- Kubelet / CRI customization requires a machine-config patch and node reboot, not a quick `systemctl` reload.

**Not-chosen alternatives:**
- `kubeadm` — mutable nodes + manual ops. Rejected for drift risk.
- `k3s` — simpler but single-binary design makes multi-control-plane HA fiddlier and it ships its own CNI/storage stack that would conflict with Envoy Gateway + democratic-csi.
- `RKE2` — strong CIS posture, but Talos's immutable-OS story maps better to a homelab where hardware is reset often.
