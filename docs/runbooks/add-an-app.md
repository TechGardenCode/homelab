# Runbook: add an app

## When to use this

A new application needs to run on one or more clusters. The app either:
- has its own source repo + CI pipeline pushing to GHCR, or
- is a third-party chart with minor customization.

## Steps

1. **Pick a cluster and namespace.** Convention: `kubernetes/clusters/<cluster>/<namespace>/<app>/`. Namespace matches the app's product/team grouping (e.g. `hausparty`, `techgarden`, `platform`).

2. **Create the namespace kustomization (if new).** Drop a `_namespace/` dir at `kubernetes/clusters/<cluster>/<namespace>/_namespace/` with a kustomization that references `helm-charts/namespace/`. The `validate-and-audit.yml` matrix skips `_namespace` dirs by design.

3. **Create the app directory.** Minimal layout:

   ```
   kubernetes/clusters/<cluster>/<namespace>/<app>/
   ├── kustomization.yaml
   └── values.yaml
   ```

   `kustomization.yaml` references `helm-charts/generic-service/` (or a remote chart) via `helmCharts:`. Look at an existing app for a template — `kubernetes/clusters/1276-dev/hausparty/hausparty/` is a complete example.

4. **Validate locally.** From the repo root:

   ```sh
   kustomize build kubernetes/clusters/<cluster>/<namespace>/<app> --enable-helm
   ```

   The output should be valid YAML — no template errors, no missing values.

5. **Register for image-tag bumps (if the app has its own CI).** Add an entry to `ci/app-registry.yaml`:

   ```yaml
   <app>:
     type: values
     paths:
       - path: kubernetes/clusters/1276-dev/<namespace>/<app>/values.yaml
         env: dev
       - path: kubernetes/clusters/1276-prod/<namespace>/<app>/values.yaml
         env: prod
   ```

   Use the `{path, env}` object form — the `promote-to-prod` job filters on `env == "prod"` and will skip PR creation if `env` is missing.

6. **Configure the app repo's CI** to send `repository_dispatch` to the homelab repo on each build:

   ```yaml
   - name: Dispatch image update
     run: |
       gh api repos/techgardencode/homelab/dispatches \
         --method POST \
         -f event_type=update-image \
         -f "client_payload[app]=<app>" \
         -f "client_payload[tag]=${{ github.sha }}" \
         -f "client_payload[env]=dev"
   ```

7. **Commit and push.** The `validate-and-audit.yml` workflow runs on the PR. Merge after green.

8. **Wait for ArgoCD.** The ApplicationSet git generator discovers the new directory on next sync (seconds via webhook). The Application will appear in the ArgoCD UI as `<cluster>.<namespace>.<app>`.

## Verification

- ArgoCD UI shows the new Application as `Synced + Healthy`.
- `kubectl -n <namespace> get all` on the target cluster shows the expected pods.
- Observability (Alloy) picks up new pods automatically via pod discovery.

## Gotchas

- **Don't commit an `image.tag` that doesn't exist in GHCR yet.** Validation passes, but ArgoCD will deploy and pods will `ImagePullBackOff`. Dispatch from CI first, then PR for any non-tag manifests.
- **Secrets belong in Bitwarden + an `ExternalSecret`,** not in `values.yaml`. The `generic-service` chart supports `externalSecret:` blocks.
- **HTTPRoute hostnames** must exist in DNS (internal Technitium zone or Cloudflare). `external-dns` writes them automatically if the `HTTPRoute` has the right annotations.

## Related

- `generic-service` chart values: [`helm-charts/generic-service/values.yaml`](../../helm-charts/generic-service/values.yaml)
- Parent repo skill: `.claude/skills/add-app/SKILL.md` in `kian.sh` (automates most of this).
