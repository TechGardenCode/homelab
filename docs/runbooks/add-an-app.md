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
     repo: TechGardenCode/<repo>   # required: whose main history decides "newest"
     # prod: auto                  # only for apps with no dev environment
     paths:
       - path: kubernetes/clusters/1276-dev/<namespace>/<app>/values.yaml
         env: dev
       - path: kubernetes/clusters/1276-prod/<namespace>/<app>/values.yaml
         env: prod
   ```

   The writer fails loudly on an unknown field, a missing `repo`, or an app name that isn't lowercase-hyphen. The image name comes from `.image.repository` in the first path.

   - **Private app repo:** add it to the writer GitHub App's installation, and to `repositories:` in `update-image-tag.yml`, so the writer can read its history.
   - **Private image:** in the GHCR package settings, grant this repo Read under "Manage Actions access".

6. **Make the app repo's CI nudge the writer** after it pushes an image tagged with the full commit sha. Set the `HOMELAB_DISPATCH_TOKEN` secret in the app repo, then add:

   ```yaml
   - name: Nudge homelab writer
     if: github.event_name == 'push' && github.ref == 'refs/heads/main'
     uses: peter-evans/repository-dispatch@28959ce8df70de7be546dd1250a005dd32156697 # v4.0.1
     with:
       token: ${{ secrets.HOMELAB_DISPATCH_TOKEN }}
       repository: TechGardenCode/homelab
       event-type: update-image
       client-payload: '{"app": "<app>"}'
   ```

   The payload is only logged; the writer decides the tag from history. Without the nudge the 30-minute schedule still picks the image up.

7. **Open a PR.** `main` requires a PR with the `validate-and-audit.yml` checks green. Once the registry change merges, the writer runs and lands the app's newest existing image with no dispatch needed.

8. **Wait for ArgoCD.** The ApplicationSet git generator discovers the new directory on next sync (seconds via webhook). The Application will appear in the ArgoCD UI as `<cluster>.<namespace>.<app>`.

## Verification

- ArgoCD UI shows the new Application as `Synced + Healthy`.
- `kubectl -n <namespace> get all` on the target cluster shows the expected pods.
- Observability (Alloy) picks up new pods automatically via pod discovery.

## Gotchas

- **Don't hand-write an `image.tag`.** Leave the tag from an existing app as a placeholder or point it at a sha you know exists; the writer replaces it with the newest real image as soon as the registry entry merges.
- **Secrets belong in Bitwarden + an `ExternalSecret`,** not in `values.yaml`. The `generic-service` chart supports `externalSecret:` blocks.
- **HTTPRoute hostnames** must exist in DNS (internal Technitium zone or Cloudflare). `external-dns` writes them automatically if the `HTTPRoute` has the right annotations.

## Related

- `generic-service` chart values: [`helm-charts/generic-service/values.yaml`](../../helm-charts/generic-service/values.yaml)
- Parent repo skill: `.claude/skills/add-app/SKILL.md` in `kian.sh` (automates most of this).
