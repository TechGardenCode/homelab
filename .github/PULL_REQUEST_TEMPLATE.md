## Summary

<!-- What does this change do? One or two sentences. -->

## Affected clusters / apps

<!-- Which cluster(s) and which Application(s) does this touch? -->

- [ ] `1276-core`
- [ ] `1276-dev`
- [ ] `1276-prod`
- [ ] `1501-prod`
- [ ] `shared`

## Checklist

- [ ] Conventional-commit title (`feat:`, `fix:`, `chore:`, `docs:`, `promote:`)
- [ ] `kustomize build --enable-helm` passes locally for changed cluster(s)
- [ ] For prod-path edits: dev is `Synced + Healthy` and the dev deployment has been verified
- [ ] For new apps: `ci/app-registry.yaml` entry added with `{path, env}` object form
- [ ] No manual edits to `image:` / `tag:` / `newTag:` fields under registered app-registry paths (these are bot-managed)

## Validation output (optional)

<!-- If anything non-trivial: paste the validate-and-audit.yml result link or local kustomize build output. -->
