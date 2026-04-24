# Runbook: promote to prod

## When to use this

A dev rollout has been verified and the same image tag should ship to prod.

## How it normally works (automated)

For apps whose `ci/app-registry.yaml` entry uses the `{path, env}` object form:

1. Developer pushes to the app repo.
2. App CI builds + pushes `ghcr.io/techgardencode/<app>:<sha>`.
3. App CI sends `repository_dispatch(event=update-image, payload={app, tag, env: dev})`.
4. `update-image-tag.yml` commits the dev values bump to `main`.
5. Same workflow opens a `promote/<app>-<shortsha>` PR against `main` that bumps prod values.
6. Dev ArgoCD reconciles in seconds via webhook.
7. Operator verifies the dev deployment (functional check, error rates, logs).
8. Operator merges the promote PR.
9. Prod ArgoCD reconciles in seconds.
10. Stale `promote/<app>-*` branches are auto-closed on the next promotion.

## Verifying dev before merging the promote PR

For routine changes:

```sh
# From the parent kian.sh repo, not this one
kubectl --context 1276-dev -n <namespace> get pods,httproute
kubectl --context 1276-dev logs -n <namespace> -l app=<app> --tail=50
```

For anything non-trivial, hit the dev URL and exercise the code path that changed.

ArgoCD app health:

```sh
argocd app get 1276-dev.<namespace>.<app>
```

Or the parent repo's `watch-rollout` skill, which waits for health.

## Merging the promote PR

- PR title: `promote: <app> to <shortsha>`.
- Description: a link to the dev deployment + a one-line functional check.
- Merge strategy: squash (keeps `main` history linear). The bot will auto-close earlier promote PRs for the same app.

Once merged, prod ArgoCD picks up the change via webhook within seconds. If it sits in `OutOfSync` for more than a minute, see [investigate-stuck-rollout.md](investigate-stuck-rollout.md).

## Edge cases

### App uses legacy string paths in `app-registry.yaml`

The promote-to-prod job filters by `env == "prod"` via yq; legacy string-format entries skip PR creation entirely and `update-image-tag.yml` updates every listed path directly — including prod. This bypasses the review gate.

**Fix:** migrate the app-registry entry to object form:

```yaml
<app>:
  type: values
  paths:
    - path: kubernetes/clusters/1276-dev/<namespace>/<app>/values.yaml
      env: dev
    - path: kubernetes/clusters/1276-prod/<namespace>/<app>/values.yaml
      env: prod
```

### Prod requires a config change beyond the image tag

Don't edit prod `values.yaml` directly — the block-image-tag-edit hook will catch image/tag edits. For non-tag prod changes:

1. Make the same change in dev first.
2. Verify dev.
3. Open a PR that touches the prod `values.yaml` directly.
4. The prod-path guard (parent repo tooling) will confirm dev is Synced+Healthy before allowing the edit.

### Rolling back

Prod rollback = revert the promote commit on `main`. ArgoCD reconciles the previous image tag within seconds.

```sh
git revert <promote-commit-sha>
git push
```

## Related

- Parent repo skill: `.claude/skills/promote-dev-to-prod/SKILL.md` in `kian.sh` (orchestrates the verify → open-PR flow).
- Workflow: [`.github/workflows/update-image-tag.yml`](../../.github/workflows/update-image-tag.yml).
