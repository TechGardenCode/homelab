# Runbook: investigate a stuck rollout

## When to use this

An ArgoCD Application is `OutOfSync`, `Progressing`, or `Degraded` for more than ~1 minute after a merge. Common shapes:

- `ImagePullBackOff` — GHCR auth, missing tag, or typo.
- `CrashLoopBackOff` — app starts then exits.
- `Pending` — no node can schedule the pod.
- `OutOfSync` (not progressing) — ArgoCD hasn't picked up the webhook.

Don't poll the rollout repeatedly. Diagnose it.

## First pass — find the right Application

```sh
# From kian.sh repo (kubectl context default / argocd CLI configured)
argocd app list | grep <app>
argocd app get <cluster>.<namespace>.<app>
```

## Tree for common failures

### `OutOfSync` stuck at the same revision

ArgoCD webhook delivery from `homelab` failed. Check:

1. Latest commit on `main` matches what you pushed (`git log origin/main -1`).
2. ArgoCD saw it: `argocd app get ... | grep -E 'Sync Policy|Revision'`.
3. If ArgoCD is behind, trigger manually: `argocd app sync <app>`. If that works, the webhook failed — check `cloudflared` tunnel status in `1276-core`.

### `ImagePullBackOff`

1. Does the image actually exist in GHCR?  `crane manifest ghcr.io/techgardencode/<app>:<tag>` or the GH UI.
2. Did `update-image-tag.yml` commit the right tag? Check the values file at the cluster path.
3. Registry pull secret present in the namespace? `kubectl -n <ns> get sa default -o yaml | grep imagePullSecrets`.

### `CrashLoopBackOff`

1. Logs: `kubectl -n <ns> logs <pod> --previous` (the `--previous` matters because the current container is already restarting).
2. If the app tries to reach a DB or external service, check the `ExternalSecret` has synced: `kubectl -n <ns> get externalsecret,secret`. A `SecretSyncedError` means Bitwarden Secrets Manager can't reach the key.
3. Migration failure: look at the `migrate-job` in the same directory — CNPG + app-owned migrations are a common cause.

### `Pending`

1. `kubectl describe pod <pod>` — the Events section names the reason (resources, PVC binding, node selector mismatch).
2. PVC binding failure with iSCSI → the NAS iSCSI target may have gone read-only. Known issue; see parent repo's `project_iscsi_readonly_pattern` memory.
3. Resource pressure: `kubectl top node`; consider adjusting requests.

### Chart hook race (ExternalSecret before Job)

CNPG-backed apps sometimes have a migration Job that depends on an ExternalSecret. If the Job starts before the ExternalSecret materializes, it crashes. Pattern:

- Promote the ExternalSecret to a `PreSync` hook with sync-wave `-10`.
- Do **not** strip the chart's native `helm.sh/hook` annotations; convert via Kustomize patch.

## Escalation

If the rollout is stuck and the commit is known-good, revert the commit. ArgoCD reconciles back to the previous state in seconds.

```sh
git revert <commit-sha>
git push
```

Then investigate the forward fix in a follow-up PR.

## Related

- Parent repo skill: `.claude/skills/investigate-stuck-rollout/SKILL.md` in `kian.sh` (automates this diagnosis in a context-isolated agent).
- LGTM stack: Loki for app logs, Prometheus for resource pressure.
