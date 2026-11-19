#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: publish_release_page.sh <site_dir>" >&2
  exit 2
fi

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${RELEASE_RUN_NUMBER:?RELEASE_RUN_NUMBER is required}"
: "${RELEASE_SHA:?RELEASE_SHA is required}"
: "${RELEASE_ID:?RELEASE_ID is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site_dir="$1"

update_result="$(python3 "$script_dir/update_release_page.py" "$site_dir" "$RELEASE_TAG" "$RELEASE_RUN_NUMBER" "$RELEASE_SHA")"

case "$update_result" in
  skipped)
    echo "Skipping Pages publication: run ${RELEASE_RUN_NUMBER} is older than the published release."
    exit 0
    ;;
  updated)
    ;;
  *)
    echo "error: unexpected updater result: ${update_result}" >&2
    exit 1
    ;;
esac

cd "$site_dir"

git add -- index.html release.json

if git diff --cached --quiet -- index.html release.json; then
  echo "Release page content is unchanged; skipping commit and push."
else
  diff_status=$?
  if [ "$diff_status" -ne 1 ]; then
    echo "error: git diff failed with status ${diff_status}" >&2
    exit "$diff_status"
  fi
  git -c user.name=github-actions[bot] \
    -c user.email=41898282+github-actions[bot]@users.noreply.github.com \
    commit -m "Publish release page ${RELEASE_TAG}"
  git push origin HEAD:gh-pages
fi

gh api --method PATCH "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}" -f make_latest=true
gh api --method POST "repos/${GITHUB_REPOSITORY}/pages/builds"
