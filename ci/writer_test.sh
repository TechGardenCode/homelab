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

# --- runner ---------------------------------------------------------------

fail=0
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  if ( "$t" ); then echo "ok   $t"; else echo "FAIL $t"; fail=1; fi
done
exit "$fail"
