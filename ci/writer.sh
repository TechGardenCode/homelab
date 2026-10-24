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

dry() { [[ "${DRY_RUN:-}" == 1 ]]; }

# Mutating command, or just "would: ..." under DRY_RUN.
act() { if dry; then echo "would: $*"; else "$@"; fi; }

# .image.tag of PATH at git REF; empty if the file isn't there.
tag_at() { git show "$1:$2" 2>/dev/null | yq '.image.tag' 2>/dev/null || true; }

# --- promote PRs ----------------------------------------------------------

# PROD_TAG DESIRED BRANCH_TAG PR_OPEN MERGEABLE [BRANCH_CLEAN]
promote_action() {
  local prod=$1 desired=$2 branch=$3 open=$4 mergeable=$5 clean=${6:-yes}
  if [[ "$prod" == "$desired" ]]; then
    if [[ -n "$branch" || "$open" == yes ]]; then echo cleanup; else echo noop; fi
  elif [[ "$branch" == "$desired" && "$open" == yes && "$mergeable" != CONFLICTING && "$clean" == yes ]]; then
    echo keep
  else
    echo rewrite
  fi
}

# yes when the promote branch changes only the app's prod values files and
# their migrate jobs (the exact-diff fallback for PROMOTE_GUARD).
branch_clean() { # REGISTRY APP
  local f allowed
  [[ "${PROMOTE_GUARD:-}" == exact-diff ]] || { echo yes; return; }
  allowed=$(app_paths "$1" "$2" prod | while IFS= read -r f; do echo "$f"; echo "$(dirname "$f")/migrate-job.yaml"; done)
  while IFS= read -r f; do
    grep -qxF -- "$f" <<<"$allowed" || { echo no; return; }
  done < <(git diff --name-only "origin/main...origin/promote/$2")
  echo yes
}

reconcile_promotions() {
  local reg=$1 app branch prod_paths first dev desired prod_tag branch_tag pr num mergeable action p short body fail=0
  # fd 3 so gh/git inside the loop can't eat the app list
  while IFS= read -r app <&3; do
    [[ "$(app_prod "$reg" "$app")" == pr ]] || continue
    prod_paths=$(app_paths "$reg" "$app" prod)
    [[ -n "$prod_paths" ]] || continue
    branch="promote/$app"
    first=$(head -n1 <<<"$prod_paths")
    dev=$(app_paths "$reg" "$app" dev | head -n1)
    if [[ -n "$dev" ]]; then
      desired=$(tag_at origin/main "$dev")
    else
      desired=$(main_shas "$(app_repo "$reg" "$app")" | pick_candidate "$(image_of "$reg" "$app")") \
        || { echo "::error::$app: candidate lookup failed"; fail=1; continue; }
    fi
    [[ -n "$desired" ]] || { echo "::notice::$app: nothing to promote yet"; continue; }

    prod_tag=$(tag_at origin/main "$first")
    git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null || true
    git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null || true
    branch_tag=$(tag_at "origin/$branch" "$first")
    # Same-repo PRs only: a fork can open a PR from a branch with this name.
    pr=$(gh pr list --head "$branch" --state open --json number,mergeable,isCrossRepository \
      --jq '[.[] | select(.isCrossRepository | not)][0] | select(.) | "\(.number) \(.mergeable)"') \
      || { echo "::error::$app: listing promote PRs failed"; fail=1; continue; }
    num=${pr%% *}; mergeable=${pr#* }
    action=$(promote_action "$prod_tag" "$desired" "$branch_tag" "$([[ -n "$pr" ]] && echo yes || echo no)" \
      "$mergeable" "$([[ -n "$branch_tag" ]] && branch_clean "$reg" "$app" || echo yes)")
    echo "$app: promote $action (prod $prod_tag, desired $desired)"

    case "$action" in
      cleanup)
        [[ -z "$pr" ]] || act gh pr close "$num" --comment "prod is already at $desired"
        [[ -z "$branch_tag" ]] || act git push -q origin --delete "$branch"
        ;;
      rewrite)
        short=${desired:0:7}
        if dry; then
          echo "would: force-push $branch with prod at $desired and $([[ -n "$pr" ]] && echo "retitle PR #$num" || echo "open a PR")"
          continue
        fi
        git checkout -q -B "$branch" origin/main
        while IFS= read -r p; do set_tag "$p" "$desired"; done <<<"$prod_paths"
        git commit -qam "promote: $app to $short"
        git push -qf origin "$branch"
        body=$(printf '%s\n' "Promote **$app** to \`$desired\`." "" \
          "Verify dev is Synced+Healthy before merging." "" \
          "---" "*Maintained by the homelab writer (\`ci/writer.sh\`); updated in place.*")
        if [[ -n "$pr" ]]; then
          gh pr edit "$num" --title "promote: $app to $short" --body "$body"
        else
          gh pr create --base main --head "$branch" --title "promote: $app to $short" --body "$body"
        fi
        git checkout -q --detach origin/main
        ;;
    esac
  done 3< <(apps "$reg")
  return "$fail"
}

# --- dev and prod: auto on main -------------------------------------------

# One commit per app that moved. Compares against origin/main so DRY_RUN
# needs no reset of the local checkout.
reconcile_main() {
  local reg=$1 app cand targets p changed fail=0
  validate_registry "$reg" || return 1
  while IFS= read -r app <&3; do
    cand=$(main_shas "$(app_repo "$reg" "$app")" | pick_candidate "$(image_of "$reg" "$app")") \
      || { echo "::error::$app: candidate lookup failed"; fail=1; continue; }
    [[ -n "$cand" ]] || { echo "::notice::$app: no built image yet"; continue; }
    targets=$(app_paths "$reg" "$app" dev)
    if [[ "$(app_prod "$reg" "$app")" == auto ]]; then
      targets=$(printf '%s\n%s' "$targets" "$(app_paths "$reg" "$app" prod)")
    fi
    changed=
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      [[ -f "$p" ]] || { echo "::error::$app: registered path $p does not exist"; fail=1; continue; }
      [[ "$(tag_at origin/main "$p")" != "$cand" ]] || continue
      if dry; then echo "would: set $p to $cand"; else set_tag "$p" "$cand"; fi
      changed=1
    done <<<"$targets"
    [[ -n "$changed" ]] || continue
    act git commit -qam "chore: update $app image to $cand"
    echo "$app"
  done 3< <(apps "$reg")
  return "$fail"
}

# Recompute from fresh main on every attempt: never rebase a stale commit.
push_with_retry() {
  local reg=$1 attempts=$2 i rc
  for ((i = 1; i <= attempts; i++)); do
    git fetch -q origin main
    dry || git reset -q --hard origin/main
    rc=0; reconcile_main "$reg" || rc=$?
    dry && return "$rc"
    [[ "$(git rev-list --count origin/main..HEAD)" != 0 ]] || return "$rc"
    git push -q origin HEAD:main && return "$rc"
    echo "::warning::push rejected (attempt $i/$attempts); recomputing on fresh main"
    sleep $((i * 5))
  done
  echo "::error::push failed after $attempts attempts"
  return 1
}

main() {
  local reg=ci/app-registry.yaml rc=0
  validate_registry "$reg" || return 1
  push_with_retry "$reg" 5 || rc=1
  reconcile_promotions "$reg" || rc=1
  return "$rc"
}

# exit on the same line: push_with_retry resets this file under bash's feet.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then main "$@"; exit $?; fi
