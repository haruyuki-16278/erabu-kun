#!/usr/bin/env bash
# Integration tests for calendar versioning (CLV-01) in build_release.sh.
#
# Runs the real build_release.sh from a private mktemp fixture directory (never
# the repository) with PATH stubs for git, swiftc, codesign and every tool that
# must not run (signing, DMG, notarization). The codesign stub records the
# bundle version it observes and exits 73 so the script stops before DMG and
# notarization. Real PlistBuddy is used to read the generated Info.plist.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
script_under_test="$repo_root/build_release.sh"
repo_info_plist="$repo_root/src/Info.plist"

fixed_utc_date="2026.11.19"
build_number="42"
codesign_stop_status="73"

root="$(mktemp -d "${TMPDIR:-/tmp}/release_version_tests.XXXXXX")"
root="$(cd "$root" && pwd -P)"

cleanup() {
    if [[ -n "${root:-}" && -d "$root" ]]; then
        rm -rf -- "$root"
    fi
}
trap cleanup EXIT

stub_bin="$root/bin"
mkdir -p "$stub_bin"

# git: only rev-list --count HEAD is expected by build_release.sh.
cat > "$stub_bin/git" <<'EOF'
#!/bin/bash
if [ "$1" = "rev-list" ] && [ "$2" = "--count" ]; then
    echo 42
    exit 0
fi
echo "unexpected git call: $*" >&2
exit 98
EOF

# swiftc: no-op compile.
cat > "$stub_bin/swiftc" <<'EOF'
#!/bin/bash
exit 0
EOF

# codesign: record the bundle's version keys (read by real PlistBuddy), then stop.
cat > "$stub_bin/codesign" <<'EOF'
#!/bin/bash
app="${*: -1}"
plist="$app/Contents/Info.plist"
: > "$CAPTURE_DIR/codesign_called"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" > "$CAPTURE_DIR/short_version" 2>/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" > "$CAPTURE_DIR/build_version" 2>/dev/null
exit 73
EOF

# date: only the fixed UTC calendar-date query is intercepted; all else goes to /bin/date.
cat > "$stub_bin/date" <<'EOF'
#!/bin/bash
if [ "$#" -eq 2 ] && [ "$1" = "-u" ] && [ "$2" = "+%Y.%m.%d" ]; then
    echo 2026.11.19
    exit 0
fi
exec /bin/date "$@"
EOF

# Tools that must never run in these tests: record and fail.
for forbidden in xcrun hdiutil sips iconutil swift osascript; do
    printf '#!/bin/bash\n: > "$CAPTURE_DIR/forbidden_%s"\nexit 99\n' "$forbidden" > "$stub_bin/$forbidden"
done

chmod +x "$stub_bin"/*

pass_count=0
fail_count=0
case_dir=""
run_status=""
run_output=""

pass() {
    pass_count=$((pass_count + 1))
    echo "PASS: $1"
}

fail() {
    fail_count=$((fail_count + 1))
    echo "FAIL: $1"
}

assert_eq() {
    # assert_eq <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1 (expected '$2', got '$3')"
    fi
}

captured() {
    if [ -f "$case_dir/$1" ]; then
        cat "$case_dir/$1"
    else
        echo "<missing>"
    fi
}

# run_build <case> <ref_type> <ref_name> [release_tag]
# An empty ref_type means the variables are unset (default non-tag build).
# An optional release_tag is passed as an explicit RELEASE_TAG environment override
# (as the CI prepare step does); an empty value leaves RELEASE_TAG unset.
run_build() {
    local name="$1" ref_type="$2" ref_name="$3" release_tag="${4:-}"
    case_dir="$root/$name"
    mkdir -p "$case_dir/src" "$case_dir/build"
    cp "$script_under_test" "$case_dir/build_release.sh"
    cp "$repo_info_plist" "$case_dir/src/Info.plist"
    if [ -d "$repo_root/scripts" ]; then
        cp -R "$repo_root/scripts" "$case_dir/scripts"
    fi
    : > "$case_dir/build/sentinel"

    local env_args=(
        "PATH=$stub_bin:/usr/bin:/bin"
        "HOME=$case_dir"
        "CAPTURE_DIR=$case_dir"
        "TZ=Pacific/Honolulu"
        "APPLE_ID=dummy-apple-id"
        "APP_SPECIFIC_PASSWORD=dummy-app-password"
    )
    if [ -n "$ref_type" ]; then
        env_args+=("GITHUB_REF_TYPE=$ref_type" "GITHUB_REF_NAME=$ref_name")
    fi
    if [ -n "$release_tag" ]; then
        env_args+=("RELEASE_TAG=$release_tag")
    fi

    (cd "$case_dir" && /usr/bin/env -i "${env_args[@]}" /bin/bash ./build_release.sh) \
        > "$case_dir/output.txt" 2>&1
    run_status=$?
    run_output="$case_dir/output.txt"
}

# expect_release_version <case> <ref_name> <expected_short_version>
expect_release_version() {
    run_build "$1" tag "$2"
    assert_eq "$1: build reached codesign stop" "$codesign_stop_status" "$run_status"
    assert_eq "$1: CFBundleShortVersionString" "$3" "$(captured short_version)"
    assert_eq "$1: CFBundleVersion (git count)" "$build_number" "$(captured build_version)"
    if cmp -s "$case_dir/src/Info.plist" "$repo_info_plist"; then
        pass "$1: src/Info.plist unmodified"
    else
        fail "$1: src/Info.plist was modified in fixture"
    fi
}

# expect_rejected <case> <ref_name>
# Invalid tags must fail before the build directory is removed and before codesign.
expect_rejected() {
    run_build "$1" tag "$2"
    if [ "$run_status" -ne 0 ] && [ "$run_status" -ne "$codesign_stop_status" ]; then
        pass "$1: nonzero exit before codesign (status $run_status)"
    else
        fail "$1: expected rejection, got status $run_status"
    fi
    if [ -e "$case_dir/codesign_called" ]; then
        fail "$1: codesign was reached for invalid ref '$2'"
    else
        pass "$1: codesign not reached"
    fi
    if [ -f "$case_dir/build/sentinel" ]; then
        pass "$1: build directory preserved"
    else
        fail "$1: build directory was deleted before validation"
    fi
    if grep -Eiq 'YYYY\.MM\.DD|invalid|不正' "$run_output"; then
        pass "$1: clear error message"
    else
        fail "$1: no clear error message in output"
    fi
    if compgen -G "$case_dir/forbidden_*" > /dev/null; then
        fail "$1: a forbidden tool (signing/notarization/auth) was invoked"
    else
        pass "$1: no forbidden tool invoked"
    fi
}

# Primary RED assertion: release tag must publish its calendar version.
expect_release_version "release_tag_v2026_11_19" "v2026.11.19" "2026.11.19"

# Leap day accepted.
expect_release_version "release_leap_day_v2024_02_29" "v2024.02.29" "2024.02.29"

# Suffixed CI release tag (v<date>-<run number>) publishes the calendar date only.
expect_release_version "release_tag_suffix_v2026_11_19_42" "v2026.11.19-42" "2026.11.19"

# Explicit RELEASE_TAG override on a main branch build uses the supplied tag's date, not wall-clock.
run_build "release_tag_env_on_main_uses_supplied_date" branch main "v2024.02.29"
assert_eq "release_tag_env_on_main_uses_supplied_date: build reached codesign stop" "$codesign_stop_status" "$run_status"
assert_eq "release_tag_env_on_main_uses_supplied_date: CFBundleShortVersionString" "2024.02.29" "$(captured short_version)"

run_build "release_tag_env_suffix_on_main_uses_supplied_date" branch main "v2024.02.29-7" "v2024.02.29-7"
assert_eq "release_tag_env_suffix_on_main_uses_supplied_date: build reached codesign stop" "$codesign_stop_status" "$run_status"
assert_eq "release_tag_env_suffix_on_main_uses_supplied_date: CFBundleShortVersionString" "2024.02.29" "$(captured short_version)"

# Default non-tag build (and main/manual branch build) uses current UTC date.
run_build "default_non_tag_utc" "" ""
assert_eq "default_non_tag_utc: build reached codesign stop" "$codesign_stop_status" "$run_status"
assert_eq "default_non_tag_utc: CFBundleShortVersionString" "$fixed_utc_date" "$(captured short_version)"
assert_eq "default_non_tag_utc: CFBundleVersion (git count)" "$build_number" "$(captured build_version)"

run_build "branch_main_utc" branch "main"
assert_eq "branch_main_utc: build reached codesign stop" "$codesign_stop_status" "$run_status"
assert_eq "branch_main_utc: CFBundleShortVersionString" "$fixed_utc_date" "$(captured short_version)"

# Invalid tags fail clearly before any build deletion, auth or signing.
expect_rejected "reject_2025_02_29_non_leap" "v2025.02.29"
expect_rejected "reject_2026_02_30" "v2026.02.30"
expect_rejected "reject_2026_13_01" "v2026.13.01"
expect_rejected "reject_legacy_v1_0_2" "v1.0.2"
expect_rejected "reject_nonpadded_v2026_1_5" "v2026.1.5"
expect_rejected "reject_malformed_v" "v"
expect_rejected "reject_empty_tag_name" ""
expect_rejected "reject_suffix_zero" "v2026.11.19-0"
expect_rejected "reject_suffix_non_numeric" "v2026.11.19-abc"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
