#!/bin/bash
# CalVer helper shared by build_release.sh and scripts/prepare_release.sh.
#
# Usage:
#   release_version.sh             print the current UTC date as YYYY.MM.DD
#   release_version.sh <tag>       validate <tag> and print its YYYY.MM.DD version
#
# <tag> must be vYYYY.MM.DD, optionally followed by -<N> where N is a positive
# integer without leading zeros (CI suffix, e.g. v2026.11.19-42). The date must
# exist in the calendar. Errors go to stderr with a nonzero exit status.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    date -u +%Y.%m.%d
    exit 0
fi

if [ "$#" -ne 1 ]; then
    echo "❌ エラー: release_version.sh は引数を 0 個または 1 個（リリースタグ）で指定してください。" >&2
    exit 1
fi

tag="$1"

if [[ ! "$tag" =~ ^v([0-9]{4}\.[0-9]{2}\.[0-9]{2})(-[1-9][0-9]*)?$ ]]; then
    echo "❌ エラー: リリースタグ '${tag}' は vYYYY.MM.DD 形式（任意で -<番号>）ではありません（例: v2026.11.19、v2026.11.19-42）。" >&2
    exit 1
fi

version="${BASH_REMATCH[1]}"

# 正規表現だけでは 2025.02.29 などの実在しない日付を防げないため、BSD date で往復検証する
if ! round_trip_date=$(date -j -u -f '%Y.%m.%d' "$version" '+%Y.%m.%d' 2>/dev/null) ||
    [ "$round_trip_date" != "$version" ]; then
    echo "❌ エラー: リリースタグ '${tag}' は実在する YYYY.MM.DD の日付ではありません（例: v2026.11.19）。" >&2
    exit 1
fi

printf '%s\n' "$version"
