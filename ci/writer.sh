#!/usr/bin/env bash
# Image-tag writer: reconciles every app in ci/app-registry.yaml to the newest
# commit on the app repo's main that has a built image. Dispatches are only
# nudges; nothing from a payload is read here.
#
# Env: DRY_RUN=1 (print "would: ..." and write nothing), GH_TOKEN,
#      GHCR_TOKEN (empty = anonymous), PROMOTE_GUARD (ruleset|exact-diff).
# Logs carry app names, shas and homelab paths only (public repo).
# Values reach yq via env()/strenv(), never by splicing into the expression.
set -euo pipefail

NAME_RE='^[a-z0-9-]+$'
REPO_RE='^TechGardenCode/[A-Za-z0-9._-]+$'

# --- registry -------------------------------------------------------------

apps() { yq '.apps | keys | .[]' "$1"; }
app_repo() { A="$2" yq '.apps[strenv(A)].repo' "$1"; }
app_prod() { A="$2" yq '.apps[strenv(A)].prod // "pr"' "$1"; }
app_paths() { A="$2" E="$3" yq '.apps[strenv(A)].paths[] | select(.env == strenv(E)) | .path' "$1"; }

image_of() {
  local first
  first=$(A="$2" yq '.apps[strenv(A)].paths[0].path' "$1")
  yq '.image.repository' "$first"
}

validate_registry() {
  local reg=$1 app err=0 bad
  while IFS= read -r app; do
    if [[ ! "$app" =~ $NAME_RE ]]; then
      echo "::error::registry: app name '$app' must match $NAME_RE"; err=1; continue
    fi
    bad=$(A="$app" yq '.apps[strenv(A)] | keys | .[] | select(. != "repo" and . != "prod" and . != "paths")' "$reg" 2>&1) \
      || bad="(not a map)"
    [[ -z "$bad" ]] || { echo "::error::registry: $app: unknown key(s): $bad"; err=1; }
    [[ "$(app_repo "$reg" "$app")" =~ $REPO_RE ]] \
      || { echo "::error::registry: $app: repo must match $REPO_RE"; err=1; }
    if [[ "$(A="$app" yq '.apps[strenv(A)] | has("prod")' "$reg")" == true ]]; then
      case "$(A="$app" yq '.apps[strenv(A)].prod' "$reg")" in
        pr|auto) ;;
        *) echo "::error::registry: $app: prod must be pr or auto"; err=1 ;;
      esac
    fi
    # yq can't compare arrays and its and/or precedence is surprising, so
    # count the well-formed entries and compare with the total.
    bad=$(A="$app" yq '.apps[strenv(A)].paths
      | select(type == "!!seq" and length > 0)
      | length - ([.[] | select((has("path")) and (has("env")) and ((keys | length) == 2)
          and ((.env == "dev") or (.env == "prod")) and ((.path | type) == "!!str"))] | length)' \
      "$reg" 2>/dev/null) || bad=
    [[ "$bad" == 0 ]] \
      || { echo "::error::registry: $app: paths must be a non-empty list of {path, env: dev|prod}"; err=1; }
  done < <(apps "$reg")
  return "$err"
}

# --- images ---------------------------------------------------------------

# rc 0 = tag exists, 1 = not found, 2 = registry/auth error (never treated
# as "not found", so a broken token can't silently freeze an app).
image_exists() {
  local name=${1#ghcr.io/} tag=$2 tok code
  tok=$(curl -fsS ${GHCR_TOKEN:+-u "x:$GHCR_TOKEN"} \
    "https://ghcr.io/token?scope=repository:$name:pull" | yq -p json '.token') \
    || { echo "::error::ghcr token request failed for $1" >&2; return 2; }
  code=$(curl -sS -o /dev/null -w '%{http_code}' -I \
    -H "Authorization: Bearer $tok" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$name/manifests/$tag") || code=000
  case "$code" in
    200) return 0 ;;
    404) return 1 ;;
    *) echo "::error::ghcr manifest lookup for $1 returned $code" >&2; return 2 ;;
  esac
}

main_shas() { gh api "repos/$1/commits?sha=main&per_page=100" --jq '.[].sha'; }

# stdin: shas newest-first. Prints the first one with an image; rc 2 on a
# registry error.
pick_candidate() {
  local sha rc
  while IFS= read -r sha; do
    rc=0; image_exists "$1" "$sha" || rc=$?
    case "$rc" in
      0) echo "$sha"; return 0 ;;
      2) return 2 ;;
    esac
  done
  return 0
}

# --- manifests ------------------------------------------------------------

set_tag() {
  local file=$1 tag=$2 job repo
  TAG="$tag" yq -i '.image.tag = strenv(TAG)' "$file"
  job="$(dirname "$file")/migrate-job.yaml"
  [[ -f "$job" ]] || return 0
  repo=$(yq '.image.repository' "$file")
  REPO="$repo" TAG="$tag" yq -i '
    (.spec.template.spec.containers[] | select(.image | sub(":[^:/]*$"; "") == strenv(REPO)) | .image)
      = strenv(REPO) + ":" + strenv(TAG)' "$job"
}

main() { :; }

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then main "$@"; fi
