#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract tests for automatic release publishing (main push -> CalVer release).
#
# - Workflow tests parse .github/workflows/build-and-release.yml with YAML.safe_load.
# - Script tests run scripts/prepare_release.sh from a Dir.mktmpdir fixture with
#   fake `git` and `gh` first on PATH. No network, no real GitHub calls, no
#   signing, no tokens.
#
# Contract: only a manual workflow_dispatch with release=true on refs/heads/main
# publishes. Pushes to main and v* tags never publish; manual runs without the
# flag only build the artifact.
#
# Run: ruby tests/auto_release_tests.rb
# Focused: ruby tests/auto_release_tests.rb -n test_manual_release_flag_gates_publication

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
WORKFLOW_PATH = File.join(REPO_ROOT, ".github", "workflows", "build-and-release.yml")
PREPARE_SCRIPT = File.join(REPO_ROOT, "scripts", "prepare_release.sh")

BUILD_STEP_NAME = "Build, sign, notarize, and package DMG"
RELEASE_STEP_NAME = "Create GitHub Release"

SHA = "0123456789abcdef0123456789abcdef01234567"
OTHER_SHA = "fedcba9876543210fedcba9876543210fedcba98"
REPOSITORY = "haruyuki-16278/erabu-kun"
RUN_ID = "123456"
RUN_API_PATH = "repos/#{REPOSITORY}/actions/runs/#{RUN_ID}"
# API-reported run creation time, 2026-11-19 23:59:59 UTC. In Asia/Tokyo this is
# already 2026-11-20, so a local-time date computation would produce the wrong
# version. The release date must come from this value, not from the commit date.
RUN_CREATED_AT = "2026-11-19T23:59:59Z"

# Fake git: records every call, answers only the calls the release script is
# expected to make, and fails loudly on anything else.
FAKE_GIT = <<~'SH'
  #!/bin/bash
  echo "$*" >> "$GIT_LOG"
  if [ "$1" = "show-ref" ] && [ "$2" = "--verify" ] && [ "$3" = "--quiet" ] && [[ "$4" == refs/tags/* ]]; then
      if [ -n "${TEST_EXISTING_TAG_SHA:-}" ]; then
          exit 0
      fi
      exit 1
  fi
  if [ "$1" = "rev-parse" ] && [ "$2" = "--verify" ] && [[ "$3" == refs/tags/*'^{commit}' ]] && [ -n "${TEST_EXISTING_TAG_SHA:-}" ]; then
      echo "$TEST_EXISTING_TAG_SHA"
      exit 0
  fi
  echo "unexpected git call: $*" >&2
  exit 98
SH

# Fake gh: only `gh api repos/<repo>/actions/runs/<id> --jq .created_at` is expected.
# Prints TEST_RUN_CREATED_AT (an explicit empty value prints an empty line), or
# fails when TEST_GH_FAIL=1. Records every invocation in GH_LOG.
FAKE_GH = <<~'SH'
  #!/bin/bash
  echo "$*" >> "$GH_LOG"
  if [ "$1" = "api" ] && [ "$2" = "repos/haruyuki-16278/erabu-kun/actions/runs/123456" ] && [ "$3" = "--jq" ] && [ "$4" = ".created_at" ]; then
      if [ "${TEST_GH_FAIL:-0}" = "1" ]; then
          echo "gh: simulated run lookup failure" >&2
          exit 1
      fi
      printf '%s\n' "${TEST_RUN_CREATED_AT-2026-11-19T23:59:59Z}"
      exit 0
  fi
  echo "unexpected gh call: $*" >&2
  exit 98
SH

Result = Struct.new(:status, :stdout, :stderr, :outputs, :git_log, :gh_log)

module ReleaseFixture
  def load_workflow
    workflow = YAML.safe_load(File.read(WORKFLOW_PATH), [], [], false)
    # YAML 1.1 parses the bare `on:` key as boolean true.
    workflow["on"] = workflow.delete(true) if workflow.key?(true) && !workflow.key?("on")
    workflow
  end

  def build_steps(workflow)
    workflow.dig("jobs", "build", "steps") || []
  end

  def parse_outputs(text)
    text.each_line.each_with_object({}) do |line, acc|
      key, value = line.chomp.split("=", 2)
      acc[key] = value unless value.nil?
    end
  end

  # run_prepare(event:, ref:, ...) runs scripts/prepare_release.sh in a fresh fixture
  # with fake git and gh on PATH.
  # release: value of INPUT_RELEASE (the workflow_dispatch input); nil leaves it unset.
  # created_at: value the fake gh returns for the run's created_at.
  # gh_fail: makes the fake gh run lookup fail.
  # omit: names of variables to leave unset.
  def run_prepare(event:, ref:, sha: SHA, run_number: "42", run_id: RUN_ID, attempt: nil,
                  release: "false", created_at: RUN_CREATED_AT, gh_fail: false,
                  tag_sha: nil, omit: [], tz: "Asia/Tokyo")
    dir = Dir.mktmpdir("prepare_release_tests")
    @tmpdirs << dir
    bin = File.join(dir, "bin")
    FileUtils.mkdir_p(bin)
    { "git" => FAKE_GIT, "gh" => FAKE_GH }.each do |name, body|
      path = File.join(bin, name)
      File.write(path, body)
      File.chmod(0o755, path)
    end

    out_path = File.join(dir, "github_output")
    log_path = File.join(dir, "git.log")
    gh_log_path = File.join(dir, "gh.log")

    env = {
      "PATH" => "#{bin}:/usr/bin:/bin",
      "TZ" => tz,
      "GITHUB_OUTPUT" => out_path,
      "GITHUB_EVENT_NAME" => event,
      "GITHUB_REF" => ref,
      "GITHUB_SHA" => sha,
      "GITHUB_RUN_NUMBER" => run_number,
      "GITHUB_RUN_ID" => run_id,
      "GITHUB_REPOSITORY" => REPOSITORY,
      "GH_TOKEN" => "dummy-github-token",
      "GIT_LOG" => log_path,
      "GH_LOG" => gh_log_path,
      "TEST_RUN_CREATED_AT" => created_at
    }
    env["INPUT_RELEASE"] = release unless release.nil?
    env["GITHUB_RUN_ATTEMPT"] = attempt if attempt
    env["TEST_EXISTING_TAG_SHA"] = tag_sha if tag_sha
    env["TEST_GH_FAIL"] = "1" if gh_fail
    omit.each { |key| env.delete(key) }

    stdout, stderr, status = Open3.capture3(env, "bash", PREPARE_SCRIPT,
                                            chdir: dir, unsetenv_others: true)
    outputs = File.exist?(out_path) ? parse_outputs(File.read(out_path)) : {}
    git_log = File.exist?(log_path) ? File.read(log_path) : ""
    gh_log = File.exist?(gh_log_path) ? File.read(gh_log_path) : ""
    Result.new(status.exitstatus, stdout, stderr, outputs, git_log, gh_log)
  end

  def assert_success(result, label = "run")
    assert_equal 0, result.status, "#{label}: expected exit 0, got #{result.status}\nstderr:\n#{result.stderr}"
  end

  def assert_failure_without_publish(result, label)
    refute_equal 0, result.status, "#{label}: expected nonzero exit"
    refute_equal "true", result.outputs["publish"], "#{label}: publish must not be true"
    refute_empty result.stderr, "#{label}: expected an error message on stderr"
  end

  def assert_no_tag(result, label)
    assert_includes [nil, ""], result.outputs["tag"], "#{label}: no tag may be generated"
  end

  # Non-publishing runs must not query the run metadata or look up existing tags.
  def assert_no_external_lookups(result, label)
    assert_equal "", result.gh_log, "#{label}: gh must not be called"
    refute_match(/\b(show-ref|rev-parse)\b/, result.git_log, "#{label}: no tag lookup expected")
  end
end

class WorkflowReleaseContractTest < Minitest::Test
  include ReleaseFixture

  def test_manual_release_flag_gates_publication
    workflow = load_workflow
    dispatch = workflow["on"].is_a?(Hash) ? workflow["on"]["workflow_dispatch"] : nil
    inputs = dispatch.is_a?(Hash) ? dispatch["inputs"] : nil
    release_input = inputs.is_a?(Hash) ? inputs["release"] : nil
    refute_nil release_input, "missing workflow_dispatch.inputs.release (boolean flag, default false)"
    assert_equal "boolean", release_input["type"]
    assert_equal false, release_input["default"]
    refute_empty release_input["description"].to_s.strip, "workflow_dispatch.inputs.release needs a description"

    release = build_steps(workflow).find { |step| step["name"] == RELEASE_STEP_NAME }
    refute_nil release, "missing step named '#{RELEASE_STEP_NAME}'"
    assert_equal "steps.release.outputs.publish == 'true'", release["if"]
  end

  def test_prepare_step_gets_release_input_token_and_actions_read
    workflow = load_workflow
    steps = build_steps(workflow)

    prepare_index = steps.index { |step| step["id"] == "release" }
    refute_nil prepare_index, "missing prepare step with id 'release'"
    prepare = steps[prepare_index]
    assert_includes prepare["run"].to_s.lines.map(&:strip), "bash scripts/prepare_release.sh"
    env = prepare["env"] || {}
    assert_equal "${{ inputs.release }}", env["INPUT_RELEASE"]
    assert_equal "${{ github.token }}", env["GH_TOKEN"]

    permissions = workflow.dig("jobs", "build", "permissions") || workflow["permissions"]
    assert_kind_of Hash, permissions, "permissions must be an explicit map"
    assert_equal "read", permissions["actions"], "run metadata lookup needs actions: read"
    assert_equal "write", permissions["contents"]

    build_index = steps.index { |step| step["name"] == BUILD_STEP_NAME }
    refute_nil build_index, "missing step named '#{BUILD_STEP_NAME}'"
    assert_operator prepare_index, :<, build_index, "prepare step must run before build"
  end

  def test_release_step_publishes_explicit_tag_and_commit
    steps = build_steps(load_workflow)

    release = steps.find { |step| step["name"] == RELEASE_STEP_NAME }
    refute_nil release, "missing step named '#{RELEASE_STEP_NAME}'"
    with = release["with"] || {}
    assert_equal "${{ steps.release.outputs.tag }}", with["tag_name"]
    assert_equal "${{ github.sha }}", with["target_commitish"]
    assert_equal "false", with["make_latest"].to_s
    assert_equal "true", with["fail_on_unmatched_files"].to_s

    build_index = steps.index { |step| step["name"] == BUILD_STEP_NAME }
    refute_nil build_index, "missing step named '#{BUILD_STEP_NAME}'"
    assert_equal "${{ steps.release.outputs.tag }}", steps[build_index].dig("env", "RELEASE_TAG")
  end
end

class PrepareReleaseContractTest < Minitest::Test
  include ReleaseFixture

  def setup
    @tmpdirs = []
  end

  def teardown
    @tmpdirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  # Pushes to main (including a develop->main merge) never publish, even if a
  # release value is present; they do not look up the run or any tag.
  def test_main_push_never_publishes_or_looks_up_tags
    result = run_prepare(event: "push", ref: "refs/heads/main", release: "")
    assert_success(result, "main push")
    refute_equal "true", result.outputs["publish"], "main push must not publish"
    assert_no_tag(result, "main push")
    assert_no_external_lookups(result, "main push")
  end

  def test_main_push_ignores_release_value
    result = run_prepare(event: "push", ref: "refs/heads/main", release: "true")
    refute_equal "true", result.outputs["publish"], "main push must not publish even with release=true"
    assert_no_external_lookups(result, "main push with release=true")
  end

  # Tag pushes never publish; tag format validation lives in the shared helper and build tests.
  def test_tag_push_never_publishes
    %w[refs/tags/v2026.11.19 refs/tags/v2026.11.19-42 refs/tags/v1.0.2].each do |ref|
      result = run_prepare(event: "push", ref: ref, release: "")
      refute_equal "true", result.outputs["publish"], "#{ref}: tag push must not publish"
      assert_no_external_lookups(result, ref)
    end
  end

  def test_branch_push_does_not_publish_or_generate_tag
    result = run_prepare(event: "push", ref: "refs/heads/feature/x", release: "")
    assert_success(result, "feature branch push")
    refute_equal "true", result.outputs["publish"]
    assert_no_tag(result, "feature branch push")
    assert_no_external_lookups(result, "feature branch push")
  end

  # Manual runs without the flag (false or unset) only build the artifact.
  def test_manual_release_false_or_unset_builds_artifact_only
    [["refs/heads/main", "false"], ["refs/heads/main", nil], ["refs/tags/v2026.11.19", "false"]].each do |ref, release|
      label = "manual #{ref} release=#{release.inspect}"
      result = run_prepare(event: "workflow_dispatch", ref: ref, release: release)
      assert_success(result, label)
      refute_equal "true", result.outputs["publish"], "#{label}: must not publish"
      assert_no_tag(result, label)
      assert_no_external_lookups(result, label)
    end
  end

  # Manual release on main publishes v<UTC date of run creation>-<run number>.
  # TZ is Asia/Tokyo: a local-time date would give 2026.11.20 for this run.
  def test_manual_release_on_main_publishes_tag_and_metadata
    result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main", release: "true")
    assert_success(result, "manual release on main")
    assert_equal(
      { "publish" => "true", "tag" => "v2026.11.19-42", "version" => "2026.11.19" },
      result.outputs.slice("publish", "tag", "version")
    )
    assert_includes result.gh_log, "api #{RUN_API_PATH} --jq .created_at"
    assert_includes result.git_log, "show-ref --verify --quiet refs/tags/v2026.11.19-42"
  end

  # The release date comes from the run's API created_at, not the commit date.
  def test_manual_release_uses_run_created_date_not_commit_date
    result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main", release: "true",
                         created_at: "2026-11-18T12:00:00Z")
    assert_success(result, "manual release with older run")
    assert_equal "v2026.11.18-42", result.outputs["tag"]
    assert_equal "2026.11.18", result.outputs["version"]
    refute_includes result.git_log, "show -s", "commit timestamp must not be used"
  end

  # Rerunning the same run (new attempt, same created_at and run number) yields identical outputs.
  def test_manual_release_rerun_yields_same_outputs
    first = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main", release: "true", attempt: "1")
    rerun = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main", release: "true", attempt: "2")
    assert_success(first, "first attempt")
    assert_success(rerun, "rerun attempt")
    assert_equal "true", first.outputs["publish"]
    assert_equal first.outputs.slice("publish", "tag", "version"),
                 rerun.outputs.slice("publish", "tag", "version")
  end

  def test_manual_release_rejects_invalid_run_number
    %w[0 abc 1a].each do |run_number|
      result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                           release: "true", run_number: run_number)
      assert_failure_without_publish(result, "run number #{run_number.inspect}")
      assert_no_tag(result, "run number #{run_number.inspect}")
    end
  end

  def test_manual_release_requires_run_metadata_and_token
    %w[GITHUB_RUN_NUMBER GITHUB_RUN_ID GITHUB_REPOSITORY GITHUB_SHA GITHUB_REF GH_TOKEN].each do |key|
      result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                           release: "true", omit: [key])
      assert_failure_without_publish(result, "missing #{key}")
    end
  end

  def test_manual_release_rejects_invalid_api_timestamp
    ["", "not-a-date", "2026-13-40T00:00:00Z", "null"].each do |created_at|
      result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                           release: "true", created_at: created_at)
      assert_failure_without_publish(result, "created_at #{created_at.inspect}")
      assert_no_tag(result, "created_at #{created_at.inspect}")
    end
  end

  def test_manual_release_fails_when_run_lookup_fails
    result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                         release: "true", gh_fail: true)
    assert_failure_without_publish(result, "run lookup failure")
    assert_no_tag(result, "run lookup failure")
  end

  def test_manual_release_existing_tag_at_same_sha_is_allowed
    result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                         release: "true", tag_sha: SHA)
    assert_success(result, "existing tag at same SHA")
    assert_equal "true", result.outputs["publish"]
    assert_equal "v2026.11.19-42", result.outputs["tag"]
  end

  def test_manual_release_existing_tag_at_different_sha_fails_before_outputs
    result = run_prepare(event: "workflow_dispatch", ref: "refs/heads/main",
                         release: "true", tag_sha: OTHER_SHA)
    assert_failure_without_publish(result, "existing tag at different SHA")
    assert_empty result.outputs, "no outputs may be written before the failure"
  end

  # release=true is only valid on main; other refs fail explicitly before any output.
  def test_manual_release_on_feature_or_tag_ref_fails_before_outputs
    ["refs/heads/feature/x", "refs/tags/v2026.11.19"].each do |ref|
      result = run_prepare(event: "workflow_dispatch", ref: ref, release: "true")
      assert_failure_without_publish(result, "release=true on #{ref}")
      assert_empty result.outputs, "#{ref}: no outputs may be written before the failure"
    end
  end
end
