#!/usr/bin/env bash
# Self-check for ci/writer.sh. Plain bash, no framework, no network.
# Run: bash ci/writer_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=ci/writer.sh
source "$HERE/writer.sh"
set +e

# Each test runs in a subshell; a failed assertion exits it.
assert_eq() { # got want name
  if [[ "$1" != "$2" ]]; then
    printf '    %s: got [%s] want [%s]\n' "$3" "$1" "$2" >&2
    exit 1
  fi
}

# Stub the registry lookup: a tag "exists" when it is listed in $TAGS.
image_exists() { grep -qx -- "$2" "$TAGS"; }

fixture() { T=$(mktemp -d); TAGS="$T/tags"; : >"$TAGS"; }

registry() { # name + yaml body for apps
  printf 'apps:\n%s\n' "$1" >"$T/reg.yaml"
}

# --- candidate selection --------------------------------------------------

test_newest_with_image_wins() {
  fixture; printf 'c2\nc1\n' >"$TAGS"
  assert_eq "$(printf 'c3\nc2\nc1\n' | pick_candidate img)" c2 candidate
}

test_skips_commits_without_image() {
  fixture; printf 'a1\n' >"$TAGS"
  assert_eq "$(printf 'a3\na2\na1\n' | pick_candidate img)" a1 candidate
}

test_no_candidate_is_empty() {
  fixture
  local out; out=$(printf 'c3\nc2\n' | pick_candidate img); local rc=$?
  assert_eq "$out" "" output
  assert_eq "$rc" 0 rc
}

# --- registry validation --------------------------------------------------

VALID_APP='  a:
    repo: TechGardenCode/a
    paths:
      - path: x/values.yaml
        env: dev'

test_validate_rejects_unknown_key() {
  fixture; registry "$VALID_APP
    type: values"
  validate_registry "$T/reg.yaml" 2>/dev/null; assert_eq $? 1 rc
}

test_validate_rejects_missing_repo() {
  fixture; registry '  a:
    paths:
      - path: x/values.yaml
        env: dev'
  validate_registry "$T/reg.yaml" 2>/dev/null; assert_eq $? 1 rc
}

test_validate_rejects_bad_name() {
  fixture; registry '  Bad_Name:
    repo: TechGardenCode/a
    paths:
      - path: x/values.yaml
        env: dev'
  validate_registry "$T/reg.yaml" 2>/dev/null; assert_eq $? 1 rc
}

test_validate_rejects_bad_prod() {
  fixture; registry "$VALID_APP
    prod: yes"
  validate_registry "$T/reg.yaml" 2>/dev/null; assert_eq $? 1 rc
}

test_validate_rejects_bad_paths() {
  local body
  for body in '    paths: []' '    paths:
      - path: x/values.yaml
        env: stage' '    paths:
      - path: x/values.yaml
        env: dev
        extra: 1'; do
    fixture; registry "  a:
    repo: TechGardenCode/a
$body"
    validate_registry "$T/reg.yaml" 2>/dev/null; assert_eq $? 1 "rc for: $body"
  done
}

test_validate_accepts_valid_fixture() {
  fixture; registry "$VALID_APP
    prod: auto"
  validate_registry "$T/reg.yaml"; assert_eq $? 0 rc
}

test_validate_accepts_real_registry() {
  validate_registry "$HERE/app-registry.yaml"; assert_eq $? 0 rc
}

# --- tag writing ----------------------------------------------------------

values_fixture() {
  mkdir -p "$T/app"
  cat >"$T/app/values.yaml" <<'EOF'
image:
  repository: "ghcr.io/techgardencode/x"
  tag: "old"
replicas: 1
EOF
}

test_set_tag_values_and_migrate() {
  fixture; values_fixture
  cat >"$T/app/migrate-job.yaml" <<'EOF'
kind: Job
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: ghcr.io/techgardencode/x:old
        - name: sidecar
          image: busybox:1.36
EOF
  set_tag "$T/app/values.yaml" new
  assert_eq "$(yq '.image.tag' "$T/app/values.yaml")" new values
  assert_eq "$(yq '.spec.template.spec.containers[0].image' "$T/app/migrate-job.yaml")" ghcr.io/techgardencode/x:new c1
  assert_eq "$(yq '.spec.template.spec.containers[1].image' "$T/app/migrate-job.yaml")" busybox:1.36 c2
}

test_set_tag_hostile_tag_is_literal() {
  fixture; values_fixture
  set_tag "$T/app/values.yaml" 'a"|b'
  assert_eq "$(yq '.image.tag' "$T/app/values.yaml")" 'a"|b' tag
  assert_eq "$(yq '.image.repository' "$T/app/values.yaml")" ghcr.io/techgardencode/x repo
  assert_eq "$(yq '.replicas' "$T/app/values.yaml")" 1 replicas
  assert_eq "$(yq 'keys | length' "$T/app/values.yaml")" 2 keys
}

# --- promote decisions ----------------------------------------------------

test_promote_noop_when_prod_current() { assert_eq "$(promote_action t1 t1 "" no "")" noop r; }
# The promote/** ruleset blocks GitHub's auto-delete-on-merge.
test_promote_cleanup_leftover_branch() { assert_eq "$(promote_action t1 t1 t1 no "")" cleanup r; }
test_promote_cleanup_open_pr() { assert_eq "$(promote_action t1 t1 t0 yes MERGEABLE)" cleanup r; }
test_promote_keep_up_to_date() { assert_eq "$(promote_action t0 t1 t1 yes MERGEABLE)" keep r; }
test_promote_rewrite_on_new_tag() { assert_eq "$(promote_action t0 t2 t1 yes MERGEABLE)" rewrite r; }
test_promote_rewrite_on_conflict() { assert_eq "$(promote_action t0 t1 t1 yes CONFLICTING)" rewrite r; }
test_promote_rewrite_when_none() { assert_eq "$(promote_action t0 t1 "" no "")" rewrite r; }
test_promote_rewrite_when_dirty() { assert_eq "$(promote_action t0 t1 t1 yes MERGEABLE no)" rewrite r; }

# --- reconcile + push (local bare repo as origin) -------------------------

export GIT_AUTHOR_NAME=writer GIT_AUTHOR_EMAIL=writer@test GIT_COMMITTER_NAME=writer GIT_COMMITTER_EMAIL=writer@test
sleep() { :; }
main_shas() { cat "$T/shas"; }

# App a: dev + prod (prod: pr). App b: prod only, prod: auto.
repo_fixture() { # current tag
  fixture
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/work" 2>/dev/null
  cd "$T/work" || exit 1
  local f
  for f in a/dev a/prod b/prod; do
    mkdir -p "$f"
    printf 'image:\n  repository: "ghcr.io/techgardencode/%s"\n  tag: "%s"\n' "${f%%/*}" "$1" >"$f/values.yaml"
  done
  cat >reg.yaml <<'EOF'
apps:
  a:
    repo: TechGardenCode/a
    paths:
      - path: a/dev/values.yaml
        env: dev
      - path: a/prod/values.yaml
        env: prod
  b:
    repo: TechGardenCode/b
    prod: auto
    paths:
      - path: b/prod/values.yaml
        env: prod
EOF
  git add -A && git commit -qm init && git push -q origin HEAD:main
  printf 'new\nold\n' >"$T/shas"; printf 'new\nold\n' >"$TAGS"
}

test_reconcile_commits_per_app() {
  repo_fixture old
  reconcile_main reg.yaml >/dev/null
  assert_eq "$(git log --format=%s origin/main..HEAD | grep -c 'image to')" 2 commits
  assert_eq "$(git log --format=%s origin/main..HEAD | grep -cx 'chore: update a image to new')" 1 msg
  assert_eq "$(yq .image.tag a/dev/values.yaml)" new tag
}

test_prod_auto_writes_prod() {
  repo_fixture old
  reconcile_main reg.yaml >/dev/null
  assert_eq "$(yq .image.tag b/prod/values.yaml)" new tag
}

test_prod_pr_never_touches_prod_on_main() {
  repo_fixture old
  reconcile_main reg.yaml >/dev/null
  assert_eq "$(yq .image.tag a/prod/values.yaml)" old tag
}

# A missing promote branch must read as "", not yq's "null" (else cleanup
# tries to delete a branch that isn't there).
test_tag_at_missing_ref_is_empty() {
  repo_fixture old
  assert_eq "$(tag_at origin/promote/a a/prod/values.yaml)" "" missing-ref
  assert_eq "$(tag_at origin/main a/prod/values.yaml)" old present
}

test_noop_when_current() {
  repo_fixture new
  git() { [[ "$1" == push ]] && touch "$T/pushed"; command git "$@"; }
  push_with_retry reg.yaml 5 >/dev/null; assert_eq $? 0 rc
  assert_eq "$(command git rev-list --count HEAD)" 1 commits
  assert_eq "$([[ -e "$T/pushed" ]] && echo pushed)" "" push
}

test_push_retry_recomputes() {
  repo_fixture old
  # First push: someone else lands a commit on origin first, so ours is
  # rejected as non-fast-forward. Later pushes go through.
  git() {
    if [[ "$1" == push && ! -e "$T/raced" ]]; then
      touch "$T/raced"
      command git clone -q "$T/origin.git" "$T/other" 2>/dev/null
      (cd "$T/other" && echo x >unrelated && command git add unrelated \
        && command git commit -qm unrelated && command git push -q origin HEAD:main)
    fi
    command git "$@"
  }
  push_with_retry reg.yaml 5 >/dev/null 2>&1; assert_eq $? 0 rc
  local unrelated; unrelated=$(command git -C "$T/origin.git" log --format='%H %s' main | awk '$2=="unrelated"{print $1}')
  local first; first=$(command git -C "$T/origin.git" rev-list --reverse "$unrelated..main" | head -n1)
  assert_eq "$(command git -C "$T/origin.git" rev-parse "$first^")" "$unrelated" parent
  assert_eq "$(command git -C "$T/origin.git" rev-list --count "$unrelated..main")" 2 writer-commits
  assert_eq "$(command git -C "$T/origin.git" show main:a/dev/values.yaml | yq .image.tag)" new tag
}

# --- dispatch payload never reaches the writer ----------------------------

test_payload_ignored() {
  local wf="$ROOT/.github/workflows/update-image-tag.yml"
  assert_eq "$(grep -c client_payload "$wf")" 1 workflow-uses
  grep -qE '^\s+APP: \$\{\{ github\.event\.client_payload\.app \}\}$' "$wf"; assert_eq $? 0 env-entry
  assert_eq "$(grep -c client_payload "$HERE/writer.sh")" 0 writer-uses
}

# --- runner ---------------------------------------------------------------

fail=0
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  if ( "$t" ); then echo "ok   $t"; else echo "FAIL $t"; fail=1; fi
done
exit "$fail"
