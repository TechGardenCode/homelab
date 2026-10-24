# ADR-0008: Reconciling image writer and locked `main`

**Status:** Accepted · 2026-10

## Context

`main` is ArgoCD's source of truth, and several writers hit it at once: app CI image bumps, Renovate, human PRs, AI sessions. The old `update-image-tag.yml` replayed each `repository_dispatch` payload (`app`, `tag`, `env`) as a commit. That broke in three ways:

- **Lost bumps.** Two dispatches racing to push meant one was rejected and its tag never landed.
- **Going backwards.** Tags are commit shas, which carry no order. A slow build finishing last overwrote a newer one.
- **Prod without review.** The payload chose the environment, so an app repo could write prod directly.

`main` itself only blocked force-push and deletion. Bot commits ran no checks, and the repo is public.

## Decision

**One writer that reconciles, not replays.** `update-image-tag.yml` runs `ci/writer.sh`. Every run, for every app in `ci/app-registry.yaml`, it walks the app repo's `main` newest-first and takes the first commit that has an image. Dev is set to that sha; prod follows via a PR.

- **Triggers:** a dispatch from app CI (payload ignored except for logging), a change to the registry, every 30 minutes, or manually. Runs are serialized; a push rejected by a concurrent merge is recomputed from scratch and retried.
- **Prod:** one PR per app on the stable branch `promote/<app>`, updated in place and closed once prod catches up. Apps with no dev environment are marked `prod: auto` in the registry and written directly.
- **Identity:** the writer pushes as a GitHub App whose key lives in an Environment restricted to `main`, so only reviewed workflow code can use it.
- **Locked `main`:** a ruleset requires a PR and green checks for everyone. The writer App is the only bypass. Only the App may create, update or delete `promote/**`.
- **Hardening:** third-party actions are pinned by commit sha; fork PRs need approval and get no secrets; writer logs show only app names, shas and paths.

## Consequences

**Positive:**
- No bump is lost or reordered: whatever is missed heals on the next run, with no re-runs by hand.
- Monorepos work unchanged; an api-only commit doesn't move the web image.
- Prod only moves by a reviewed PR (or an explicit `prod: auto` in this repo).
- Every change to `main` runs the same validation checks; human and Renovate changes can't land until they pass.

**Negative:**
- Every change, however small, needs a PR.
- The writer App can technically write anywhere on `main`; the control is that only reviewed workflow code can mint its token.
