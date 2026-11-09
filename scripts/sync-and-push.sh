#!/usr/bin/env bash
set -euo pipefail

# Reconcile the local UC2 recomp branch with origin/main after the remote
# history was rewritten/recreated, then push without force.

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ "$branch" != "main" ]]; then
  echo "Expected branch 'main'; currently on '$branch'." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Worktree is not clean. Commit or stash changes, then rerun." >&2
  exit 1
fi

remote="origin"
remote_branch="refs/remotes/$remote/main"
echo "Fetching $remote/main..."
git fetch "$remote" main

if git merge-base --is-ancestor "$remote_branch" HEAD; then
  echo "Local main already contains the remote history."
elif git merge-base --is-ancestor HEAD "$remote_branch"; then
  echo "Fast-forwarding local main to the remote..."
  git merge --ff-only "$remote_branch"
else
  remote_tree="$(git rev-parse "$remote_branch^{tree}")"
  matching_snapshot=""
  while IFS= read -r commit; do
    if [[ "$(git rev-parse "$commit^{tree}")" == "$remote_tree" ]]; then
      matching_snapshot="$commit"
      break
    fi
  done < <(git rev-list --first-parent HEAD)

  if [[ -z "$matching_snapshot" ]]; then
    echo "Remote history diverged, and its tree does not match any local main snapshot." >&2
    echo "No history was changed. Inspect origin/main and reconcile manually." >&2
    exit 1
  fi

  echo "Remote tree matches local snapshot $matching_snapshot."
  echo "Creating a merge commit that preserves both histories..."
  git merge --no-ff -s ours "$remote_branch" \
    -m "Merge remote main history"
fi

echo "Pushing main to $remote..."
git push "$remote" main
echo "Done."
