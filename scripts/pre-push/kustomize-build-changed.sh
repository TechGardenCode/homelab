#!/usr/bin/env bash
# Run kustomize build for every Application dir under any cluster(s) whose
# files have changed in the staged commits about to be pushed. Keeps
# pre-push fast on small changes while catching template errors early.
set -euo pipefail

upstream="${1:-origin/main}"

# Find cluster directories with changes between HEAD and upstream.
changed_clusters=$(
  git diff --name-only "${upstream}"...HEAD -- 'kubernetes/clusters/**' 2>/dev/null \
    | awk -F/ 'NF>=3 {print $3}' \
    | sort -u
)

if [[ -z "${changed_clusters}" ]]; then
  echo "No cluster changes; skipping kustomize build."
  exit 0
fi

if ! command -v kustomize >/dev/null 2>&1; then
  echo "kustomize not installed; skipping (CI will validate)."
  exit 0
fi

failed=0
for cluster in ${changed_clusters}; do
  echo "==> Building ${cluster}"
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    if ! kustomize build "${dir}" --enable-helm >/dev/null 2>&1; then
      echo "FAILED: ${dir}"
      kustomize build "${dir}" --enable-helm 2>&1 || true
      failed=1
    fi
  done < <(
    find "kubernetes/clusters/${cluster}" -name kustomization.yaml \
      -exec dirname {} \; \
      | grep -v '_namespace' \
      | grep -v 'example' \
      | sort
  )
done

exit "${failed}"
