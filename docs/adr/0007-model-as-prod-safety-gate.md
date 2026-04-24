# ADR-0007: Model-enforced prod safety gate

**Status:** Accepted · 2025-03

## Context

Prod ArgoCD apps auto-sync from `main`. There's no approval step inside ArgoCD for this repo — a push to `main` that touches a prod manifest deploys. That's intentional: it keeps the feedback loop tight for an unattended homelab.

The risk: accidental direct edits to a `kubernetes/clusters/*-prod/**` path (a tag bump, a config change) before the same change has been verified in dev. Traditional mitigations: branch protection, required reviewers, CI gates. They work, but add friction for routine dev-tier work on the same PR.

## Decision

Enforce the gate **upstream of the commit**, in the Claude Code tooling inside the parent repo (`kian.sh/.claude/`):

1. A `PreToolUse` hook blocks edits to `homelab/kubernetes/clusters/*-prod/**` unless the paired dev app is `Synced + Healthy`. Override with `PROMOTE_OVERRIDE=1` in the commit message.
2. A second hook blocks manual edits to `image:` / `tag:` / `newTag:` fields under paths registered in `ci/app-registry.yaml`. Image tags must be updated by `update-image-tag.yml` (which opens a promotion PR for prod).
3. The `promote-dev-to-prod` skill orchestrates the dev-verify → open-PR flow.

Prod syncs stay automatic. The gate is the agent that authors the change.

## Consequences

**Positive:**
- Zero ArgoCD-side latency. Prod still deploys in seconds after PR merge.
- The gate is context-aware: it knows which dev/prod pair a change belongs to and actually verifies dev health.
- Routine dev work is unaffected.
- The mechanism is transparent and debuggable — hooks are scripts in `kian.sh/.claude/scripts/hooks/`.

**Negative:**
- The safety property depends on everyone using the same tooling. A direct push from `git` CLI outside the agent environment bypasses the hook.
- Mitigation: GitHub branch protection on `main` can be added later (not currently enabled; homelab is single-operator).

**Rejected alternatives:**
- Manual PR approval: too much friction for routine work and doesn't actually verify dev health.
- ArgoCD manual-sync on prod: breaks the "ArgoCD as passive reconciler" model and creates a second source of truth for "is this deployed yet".
