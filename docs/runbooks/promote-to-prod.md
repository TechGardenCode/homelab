# Runbook: promote to prod

## When to use this

A dev rollout has been verified and the same image tag should ship to prod.

## How it normally works (automated)

1. Developer pushes to the app repo's `main`.
2. App CI builds and pushes `ghcr.io/techgardencode/<app>:<sha>`, then nudges this repo.
3. The writer (`update-image-tag.yml`) finds the newest `main` commit with an image and commits the dev values bump as `chore: update <app> image to <sha>`.
4. It keeps one PR per app on branch `promote/<app>`, titled `promote: <app> to <shortsha>`, at dev's sha. A newer dev bump updates the same PR in place.
5. Dev ArgoCD reconciles in seconds via webhook.
6. Operator verifies the dev deployment (functional check, error rates, logs).
7. Operator merges the promote PR.
8. Prod ArgoCD reconciles in seconds. On its next run the writer sees prod has caught up and deletes the branch.

Apps marked `prod: auto` in `ci/app-registry.yaml` (no dev environment) skip steps 4–7: the writer commits prod directly.

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

- PR title: `promote: <app> to <shortsha>`. The diff should touch only the prod `values.yaml` (and a `migrate-job.yaml` beside it, if the app has one).
- Merge strategy: squash (keeps `main` history linear). Don't delete the branch: only the writer may touch `promote/**`, and it cleans up on its next run.

Once merged, prod ArgoCD picks up the change via webhook within seconds. If it sits in `OutOfSync` for more than a minute, see [investigate-stuck-rollout.md](investigate-stuck-rollout.md).

## Edge cases

### No promote PR appeared

Prod may already match dev, the app may be `prod: auto`, or it may have no `env: prod` path. Otherwise, read the latest `update-image-tag` run log, which lists each app's candidate sha. To trigger a run by hand: `gh workflow run update-image-tag.yml -R TechGardenCode/homelab`.

### Prod requires a config change beyond the image tag

Don't edit prod `values.yaml` directly — the block-image-tag-edit hook will catch image/tag edits. For non-tag prod changes:

1. Make the same change in dev first.
2. Verify dev.
3. Open a PR that touches the prod `values.yaml` directly.
4. The prod-path guard (parent repo tooling) will confirm dev is Synced+Healthy before allowing the edit.

### Rolling back

Prod rollback = a PR that reverts the promote commit (`main` is locked). ArgoCD reconciles the previous image tag within seconds of the merge.

```sh
git switch -c revert/<app>-prod origin/main
git revert <promote-commit-sha>
git push -u origin HEAD && gh pr create --fill
```

The writer then reopens `promote/<app>` at dev's sha. Leave it open until the fix reaches dev.

## Related

- Parent repo skill: `.claude/skills/promote-dev-to-prod/SKILL.md` in `kian.sh` (verifies dev, then hands the PR to a human to merge).
- Workflow: [`.github/workflows/update-image-tag.yml`](../../.github/workflows/update-image-tag.yml).
