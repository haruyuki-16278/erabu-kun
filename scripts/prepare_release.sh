#!/bin/bash
# Decides whether this run publishes a GitHub Release, and which CalVer tag it uses.
#
# Publishing happens only for a manual workflow_dispatch on refs/heads/main with
# the release input set to true. Every other run (pushes to main or v* tags,
# manual runs without the flag) writes publish=false and makes no API or tag calls.
#
# Writes publish, tag and version to $GITHUB_OUTPUT only after every check passed.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
release_version="$script_dir/release_version.sh"

fail() {
    echo "❌ エラー: $*" >&2
    exit 1
}

require_var() {
    # require_var <name> <value>
    if [ -z "$2" ]; then
        fail "$1 が設定されていません。"
    fi
}

require_var GITHUB_OUTPUT "${GITHUB_OUTPUT:-}"
require_var GITHUB_EVENT_NAME "${GITHUB_EVENT_NAME:-}"

publish_requested=false
if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then
    case "${INPUT_RELEASE:-}" in
        true) publish_requested=true ;;
        false | "") ;;
        *) fail "release 入力は true または false である必要があります（現在: '${INPUT_RELEASE}'）。" ;;
    esac
fi

if [ "$publish_requested" != "true" ]; then
    printf 'publish=false\n' >> "$GITHUB_OUTPUT"
    exit 0
fi

require_var GITHUB_REF "${GITHUB_REF:-}"
require_var GITHUB_SHA "${GITHUB_SHA:-}"
require_var GITHUB_RUN_NUMBER "${GITHUB_RUN_NUMBER:-}"
require_var GITHUB_RUN_ID "${GITHUB_RUN_ID:-}"
require_var GITHUB_REPOSITORY "${GITHUB_REPOSITORY:-}"
require_var GH_TOKEN "${GH_TOKEN:-}"

if [ "$GITHUB_REF" != "refs/heads/main" ]; then
    fail "release=true は refs/heads/main でのみ指定できます（現在: '${GITHUB_REF}'）。"
fi

if [[ ! "$GITHUB_RUN_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    fail "GITHUB_RUN_NUMBER '${GITHUB_RUN_NUMBER}' は正の整数である必要があります。"
fi

# The release date is the run's creation time (UTC), so a rerun of the same run keeps its tag.
created_at=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" --jq .created_at) ||
    fail "実行 ${GITHUB_RUN_ID} の作成日時を取得できませんでした。"

if [[ ! "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    fail "実行の作成日時 '${created_at}' は YYYY-MM-DDTHH:MM:SSZ 形式ではありません。"
fi

# 正規表現だけでは 2026-13-40 などの実在しない日時を防げないため、BSD date で往復検証する
if ! round_trip_at=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$created_at" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) ||
    [ "$round_trip_at" != "$created_at" ]; then
    fail "実行の作成日時 '${created_at}' は実在する日時ではありません。"
fi

run_date="${created_at:0:10}"
run_date="${run_date//-/.}"
tag="v${run_date}-${GITHUB_RUN_NUMBER}"

version=$(bash "$release_version" "$tag") || exit 1

check_existing_tag() {
    # check_existing_tag <tag>: an existing tag is acceptable only at this exact commit.
    local tag="$1" lookup_status=0 existing
    git show-ref --verify --quiet "refs/tags/${tag}" || lookup_status=$?
    case "$lookup_status" in
        0) ;;
        1) return 0 ;;
        *) fail "タグ '${tag}' の存在確認に失敗しました（終了コード ${lookup_status}）。" ;;
    esac
    existing=$(git rev-parse --verify "refs/tags/${tag}^{commit}") ||
        fail "タグ '${tag}' のコミットを取得できませんでした。"
    if [ "$existing" != "$GITHUB_SHA" ]; then
        fail "既存のタグ '${tag}' は別のコミット（${existing}）を指しています。"
    fi
}

check_existing_tag "$tag"

printf 'publish=true\ntag=%s\nversion=%s\n' "$tag" "$version" >> "$GITHUB_OUTPUT"
