#!/usr/bin/env bash
set -euo pipefail
forbidden="$(printf '%s%s%s' 'sp' 'roo' 'ty')"
failures=0
fail() { printf 'migration policy: %s\n' "$1" >&2; failures=$((failures + 1)); }
if git grep -Iqi -- "$forbidden" HEAD --; then
  git grep -Ini -- "$forbidden" HEAD -- >&2 || true
  fail 'forbidden legacy identifier found in tracked content'
fi
while IFS= read -r -d '' path; do
  if [[ "${path,,}" == *"$forbidden"* ]]; then
    printf '%s\n' "$path" >&2
    fail 'forbidden legacy identifier found in tracked path'
  fi
done < <(git ls-files -z)
workflow_matches="$(git grep -nE 'runs-on:[[:space:]]*(ubuntu|windows|macos)-|runs-on:[[:space:]]*.*(ubuntu|windows|macos|arm).*latest|runs-on:[[:space:]]*\$\{\{' HEAD -- '.github/workflows/*.yml' '.github/workflows/*.yaml' || true)"
if [[ -n "$workflow_matches" ]]; then
  printf '%s\n' "$workflow_matches" >&2
  fail 'workflow selects a hosted or unresolved dynamic runner'
fi
if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  # Fetch the base ref with full history (not --depth=1): a shallow base ref
  # grafts away its ancestry, so `origin/BASE..HEAD` can no longer tell that
  # the base tip's ancestors are shared with HEAD. On a branch that has merged
  # the base in (e.g. after "Update branch"), that made historical base commits
  # reappear in the range as false positives.
  git fetch --no-tags origin "$GITHUB_BASE_REF" >/dev/null 2>&1 || true
  # Scope to commits this PR actually introduces: everything since the branch
  # diverged from the base (merge-base), which excludes commits merged in from
  # the base itself.
  base="$(git merge-base "origin/$GITHUB_BASE_REF" HEAD 2>/dev/null || true)"
  commits="$(git rev-list --reverse "${base:+$base..}HEAD" 2>/dev/null || git rev-list --reverse HEAD~1..HEAD 2>/dev/null || git rev-list --reverse HEAD)"
elif [[ "${GITHUB_EVENT_NAME:-}" == push && "${GITHUB_BEFORE:-}" != 0000000000000000000000000000000000000000 ]]; then
  commits="$(git rev-list --reverse "${GITHUB_BEFORE:-}..HEAD" 2>/dev/null || git rev-list --reverse HEAD~1..HEAD 2>/dev/null || git rev-list --reverse HEAD)"
else
  commits="$(git rev-list --reverse HEAD~1..HEAD 2>/dev/null || git rev-list --reverse HEAD)"
fi
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  metadata="$(git show -s --format='%an%n%ae%n%cn%n%ce%n%B' "$commit")"
  if grep -qi -- "$forbidden" <<<"$metadata"; then
    printf '%s\n' "$commit" >&2
    fail 'forbidden legacy identifier found in commit metadata'
  fi
done <<<"$commits"
(( failures == 0 )) || exit 1
printf 'migration policy passed\n'
