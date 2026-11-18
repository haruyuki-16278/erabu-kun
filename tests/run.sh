#!/usr/bin/env bash
# Compiles the real src/*.swift (minus the @main app entry point and the
# AppEnvironment file, which the test replaces) together with
# tests/BrowserLauncherTests.swift, then runs the test executable.
# Build output lives in a private mktemp directory that is removed on exit.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/erabu-kun-tests.XXXXXX")"
work_dir="$(cd "$work_dir" && pwd -P)"

cleanup() {
    if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT

sources=()
for source_file in "$repo_root"/src/*.swift; do
    case "$(basename "$source_file")" in
        App.swift|AppEnvironment.swift) continue ;;
    esac
    sources+=("$source_file")
done

test_binary="$work_dir/BrowserLauncherTests"

echo "Compiling ${#sources[@]} source files plus test runner..."
swiftc -parse-as-library \
    "$repo_root/tests/BrowserLauncherTests.swift" \
    "${sources[@]}" \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI -framework AppKit -framework Foundation \
    -o "$test_binary"

echo "Running BrowserLauncherTests..."
status=0
"$test_binary" || status=$?
echo "BrowserLauncherTests exit status: $status"
exit "$status"
