# frozen_string_literal: true

# Contract tests for the gh-pages release page publication.
#
# Contract: only a manual workflow_dispatch with release=true publishes (decided
# by the build job's `publish` output). After a successful flagged release, the
# publish-pages job promotes the release page. Pushes to main, v* tags and
# build-only manual runs never reach the job.
#
# - WorkflowTest parses .github/workflows/build-and-release.yml with YAML.safe_load.
# - PublishReleasePageScriptTest runs scripts/publish_release_page.sh with fake
#   `git` and `gh` first on PATH, and runs the real scripts/update_release_page.py
#   inside a temporary site fixture. No network, no real commits, pushes or API calls.
#
# Run: ruby tests/pages_workflow_tests.rb
# Focused: ruby tests/pages_workflow_tests.rb -n test_publish_pages_job_exists

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "yaml"

module PagesReleaseContract
  REPO_ROOT = File.expand_path("..", __dir__)
  WORKFLOW_PATH = File.join(REPO_ROOT, ".github", "workflows", "build-and-release.yml")
  PUBLISH_SCRIPT = File.join(REPO_ROOT, "scripts", "publish_release_page.sh")
  PAGES_JOB = "publish-pages"

  REPOSITORY = "haruyuki-16278/erabu-kun"
  SHA = "0123456789abcdef0123456789abcdef01234567"
  OTHER_SHA = "fedcba9876543210fedcba9876543210fedcba98"
  TAG = "v2026.11.19-42"
  RUN_NUMBER = "42"
  RELEASE_ID = "987654"

  CTA_LABEL = "ダウンロード（最新版 .dmg）"
  PLATFORM_TEXT = "macOS 13 以降対応・Apple公証(Notarized)済み・無料"

  # Known gh-pages index.html shape (before any release has been published).
  ORIGINAL_INDEX = <<~HTML.freeze
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>えらぶくん</title>
      <link rel="stylesheet" href="style.css">
    </head>
    <body>
      <main>
        <h1>えらぶくん</h1>
        <a class="btn" href="https://github.com/haruyuki-16278/erabu-kun/releases/latest" target="_blank" rel="noopener">ダウンロード（最新版 .dmg）</a>
        <div class="version">macOS 13 以降対応・Apple公証(Notarized)済み・無料</div>
        <p>インストール方法は<a href="https://github.com/haruyuki-16278/erabu-kun/releases/latest" target="_blank" rel="noopener">こちら</a>を確認してください。</p>
        <p><a href="privacy.html">プライバシーポリシー</a></p>
      </main>
    </body>
    </html>
  HTML

  # Fake git: logs every call to the shared CALLS_LOG sequence file and answers
  # only the calls the publish script is expected to make.
  FAKE_GIT = <<~'SH'
    #!/bin/bash
    echo "git $*" >> "$CALLS_LOG"
    while [ "${1:-}" = "-c" ]; do shift 2; done
    case "${1:-}" in
      add|commit) exit 0 ;;
      diff) exit "${TEST_GIT_DIFF_STATUS:-1}" ;;
      push)
        if [ "${TEST_GIT_PUSH_FAIL:-0}" = "1" ]; then
          echo "simulated push rejection" >&2
          exit 1
        fi
        exit 0 ;;
      *) echo "unexpected git call: $*" >&2; exit 98 ;;
    esac
  SH

  # Fake gh: logs every call to the shared CALLS_LOG sequence file and answers
  # only the PATCH (make latest) and POST (Pages build) requests.
  FAKE_GH = <<~'SH'
    #!/bin/bash
    echo "gh $*" >> "$CALLS_LOG"
    if [ "${1:-}" != "api" ]; then
      echo "unexpected gh call: $*" >&2
      exit 98
    fi
    case "$*" in
      *"--method PATCH"*)
        if [ "${TEST_GH_PATCH_FAIL:-0}" = "1" ]; then
          echo "simulated PATCH failure" >&2
          exit 1
        fi
        exit 0 ;;
      *"--method POST"*)
        if [ "${TEST_GH_POST_FAIL:-0}" = "1" ]; then
          echo "simulated POST failure" >&2
          exit 1
        fi
        exit 0 ;;
      *) echo "unexpected gh api call: $*" >&2; exit 98 ;;
    esac
  SH

  # Normalizes a GitHub expression: strips surrounding ${{ }} and whitespace.
  def self.expr(value)
    value.to_s.strip.sub(/\A\$\{\{\s*/, "").sub(/\s*\}\}\z/, "").strip
  end

  class WorkflowTest < Minitest::Test
    def workflow
      @workflow ||= YAML.safe_load(File.read(WORKFLOW_PATH))
    end

    def jobs
      workflow.fetch("jobs", {})
    end

    def pages_job
      job = jobs[PAGES_JOB]
      assert job.is_a?(Hash),
             "job '#{PAGES_JOB}' is missing from #{WORKFLOW_PATH}; jobs present: #{jobs.keys.join(', ')}"
      job
    end

    def pages_steps
      pages_job.fetch("steps", [])
    end

    def checkout_steps
      pages_steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }
    end

    def publish_step
      step = pages_steps.find { |s| s["run"].to_s.include?("scripts/publish_release_page.sh") }
      assert step, "no #{PAGES_JOB} step runs scripts/publish_release_page.sh"
      step
    end

    def expr(value)
      PagesReleaseContract.expr(value)
    end

    def test_publish_pages_job_exists
      assert jobs.key?(PAGES_JOB),
             "expected job '#{PAGES_JOB}' in #{WORKFLOW_PATH}; jobs present: #{jobs.keys.join(', ')}"
    end

    def test_publish_pages_needs_only_build
      assert_equal ["build"], Array(pages_job["needs"]),
                   "#{PAGES_JOB} must need only the build job"
    end

    def test_publish_pages_runs_only_when_build_publish_output_is_true
      assert_equal "needs.build.outputs.publish == 'true'", expr(pages_job["if"]),
                   "#{PAGES_JOB} must be gated only by the build publish output (no main HEAD or ref gate)"
    end

    def test_publish_pages_runs_on_ubuntu_latest
      assert_equal "ubuntu-latest", pages_job["runs-on"],
                   "#{PAGES_JOB} must run on ubuntu-latest"
    end

    def test_publish_pages_permissions_are_contents_and_pages_write
      assert_equal({ "contents" => "write", "pages" => "write" }, pages_job["permissions"],
                   "#{PAGES_JOB} must request exactly contents: write and pages: write")
    end

    def test_publish_pages_concurrency_serializes_without_cancelling
      assert_equal({ "group" => "release-pages", "cancel-in-progress" => false, "queue" => "max" },
                   pages_job["concurrency"],
                   "#{PAGES_JOB} must use group release-pages with cancel-in-progress false " \
                   "and queue max so all pending publications are queued")
    end

    def test_publish_pages_checks_out_pinned_sha
      pinned = checkout_steps.find { |step| expr(step.dig("with", "ref")) == "github.sha" }
      assert pinned,
             "#{PAGES_JOB} must check out the pinned github.sha (with.ref: ${{ github.sha }}); " \
             "checkout refs: #{checkout_steps.map { |s| s.dig('with', 'ref') }.inspect}"
    end

    def test_publish_pages_checks_out_gh_pages_into_site
      pages = checkout_steps.find do |step|
        step.dig("with", "ref").to_s.strip == "gh-pages" && step.dig("with", "path").to_s.strip == "site"
      end
      assert pages,
             "#{PAGES_JOB} must check out gh-pages with path: site; " \
             "checkouts: #{checkout_steps.map { |s| s['with'] }.inspect}"
    end

    def test_publish_pages_runs_publish_script_on_site_after_checkouts
      assert publish_step["run"].to_s.include?("bash scripts/publish_release_page.sh site"),
             "publish step must run: bash scripts/publish_release_page.sh site"
      publish_index = pages_steps.index(publish_step)
      checkout_indexes = checkout_steps.map { |step| pages_steps.index(step) }
      assert checkout_indexes.all? { |index| index < publish_index },
             "publish step must run after both checkouts"
    end

    def test_publish_pages_passes_release_environment
      env = publish_step.fetch("env", {})
      expected = {
        "GH_TOKEN" => "github.token",
        "RELEASE_TAG" => "needs.build.outputs.tag",
        "RELEASE_ID" => "needs.build.outputs.release_id",
        "RELEASE_RUN_NUMBER" => "github.run_number",
        "RELEASE_SHA" => "github.sha"
      }
      expected.each do |name, value|
        assert_equal value, expr(env[name]), "publish step env #{name} must be ${{ #{value} }}"
      end
    end

    def test_build_job_outputs_release_metadata
      outputs = jobs.fetch("build").fetch("outputs")
      expected = {
        "publish" => "steps.release.outputs.publish",
        "tag" => "steps.release.outputs.tag",
        "version" => "steps.release.outputs.version",
        "release_id" => "steps.publish.outputs.id"
      }
      expected.each do |name, value|
        assert_equal value, expr(outputs[name]), "build output #{name} must come from #{value}"
      end
    end
  end

  class PublishReleasePageScriptTest < Minitest::Test
    def setup
      @tmp = Dir.mktmpdir("pages-publish-test")
      @bin = File.join(@tmp, "bin")
      @site = File.join(@tmp, "site")
      @calls = File.join(@tmp, "calls.log")
      FileUtils.mkdir_p(@bin)
      FileUtils.mkdir_p(@site)
      write_exec(File.join(@bin, "git"), FAKE_GIT)
      write_exec(File.join(@bin, "gh"), FAKE_GH)
      write_site(@site)
    end

    def teardown
      FileUtils.rm_rf(@tmp) if @tmp
    end

    def write_exec(path, content)
      File.write(path, content)
      File.chmod(0o755, path)
    end

    def write_site(dir, index: ORIGINAL_INDEX)
      File.write(File.join(dir, "index.html"), index)
      File.write(File.join(dir, "privacy.html"), "<!DOCTYPE html>\n<html lang=\"ja\"><head><meta charset=\"utf-8\"><title>プライバシー</title></head><body><p>privacy</p></body></html>\n")
      File.write(File.join(dir, "CNAME"), "erabu-kun.relicsnow.net\n")
      FileUtils.mkdir_p(File.join(dir, "assets"))
      File.binwrite(File.join(dir, "assets", "dummy.bin"), "\x00\x01dummy".b)
    end

    def base_env
      {
        "PATH" => "#{@bin}:#{ENV.fetch('PATH', '')}",
        "CALLS_LOG" => @calls,
        "GH_TOKEN" => "dummy-token-not-a-secret",
        "GITHUB_REPOSITORY" => REPOSITORY,
        "RELEASE_TAG" => TAG,
        "RELEASE_RUN_NUMBER" => RUN_NUMBER,
        "RELEASE_SHA" => SHA,
        "RELEASE_ID" => RELEASE_ID,
        "PYTHONDONTWRITEBYTECODE" => "1"
      }
    end

    # Runs the publish script with a dummy environment; a nil value unsets a variable.
    def run_publish(overrides = {})
      assert File.file?(PUBLISH_SCRIPT),
             "scripts/publish_release_page.sh does not exist; implementation required"
      env = base_env.merge(overrides)
      Open3.capture3(env, "bash", PUBLISH_SCRIPT, @site, chdir: @site)
    end

    def calls
      File.exist?(@calls) ? File.readlines(@calls, chomp: true) : []
    end

    def call_index(pattern)
      index = calls.index { |line| line.match?(pattern) }
      assert index, "expected a call matching #{pattern.inspect}; calls were: #{calls.inspect}"
      index
    end

    def snapshot(root)
      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.each_with_object({}) do |path, files|
        next unless File.file?(path)

        files[path.delete_prefix("#{root}/")] = File.binread(path)
      end
    end

    def test_missing_required_env_fails_before_any_calls
      _out, err, status = run_publish("RELEASE_ID" => nil)
      refute status.success?, "missing RELEASE_ID must fail; stderr: #{err}"
      assert_empty calls, "missing env must fail before any git or gh call"
    end

    def test_skipped_older_run_makes_no_git_gh_calls_and_no_file_changes
      File.write(File.join(@site, "release.json"),
                 %({"tag": "v2026.11.19-50", "run_number": 50, "commit": "#{OTHER_SHA}"}\n))
      before = snapshot(@site)

      _out, err, status = run_publish
      assert status.success?, "older run must be skipped with exit 0; stderr: #{err}"
      assert_empty calls, "skipped publication must make no git or gh calls"
      assert_equal before, snapshot(@site), "skipped publication must not change files"
    end

    def test_updated_run_commits_pushes_then_patches_latest_then_requests_build
      _out, err, status = run_publish
      assert status.success?, "flagged release must publish with exit 0; stderr: #{err}"

      add = call_index(/\Agit (?:-c \S+ )*add (?:-- )?index\.html release\.json\z/)
      diff = call_index(/\Agit (?:-c \S+ )*diff --cached --quiet -- index\.html release\.json\z/)
      commit = call_index(/\Agit (?:-c \S+ )*commit\b/)
      push = call_index(/\Agit (?:-c \S+ )*push origin HEAD:gh-pages\z/)
      patch = call_index(%r{\Agh api --method PATCH repos/#{Regexp.escape(REPOSITORY)}/releases/#{RELEASE_ID} -f make_latest=true\z})
      post = call_index(%r{\Agh api --method POST repos/#{Regexp.escape(REPOSITORY)}/pages/builds\z})

      assert_equal [add, diff, commit, push, patch, post].sort, [add, diff, commit, push, patch, post],
                   "calls must run in order add, diff, commit, push, PATCH latest, POST pages build; calls: #{calls.inspect}"
    end

    def test_unchanged_content_skips_commit_and_push_but_still_patches_and_requests_build
      _out, err, status = run_publish("TEST_GIT_DIFF_STATUS" => "0")
      assert status.success?, "unchanged content must still succeed; stderr: #{err}"

      refute(calls.any? { |line| line.match?(/\Agit (?:-c \S+ )*commit\b/) },
             "unchanged content must not commit; calls: #{calls.inspect}")
      refute(calls.any? { |line| line.match?(/push origin HEAD:gh-pages\z/) },
             "unchanged content must not push; calls: #{calls.inspect}")

      patch = call_index(%r{\Agh api --method PATCH repos/#{Regexp.escape(REPOSITORY)}/releases/#{RELEASE_ID} -f make_latest=true\z})
      post = call_index(%r{\Agh api --method POST repos/#{Regexp.escape(REPOSITORY)}/pages/builds\z})
      assert_operator patch, :<, post, "PATCH must precede the Pages build request"
    end

    def test_push_failure_stops_before_patch_and_build_request
      _out, _err, status = run_publish("TEST_GIT_PUSH_FAIL" => "1")
      refute status.success?, "push failure must fail the publish step"
      refute(calls.any? { |line| line.start_with?("gh ") },
             "push failure must not PATCH or request a Pages build; calls: #{calls.inspect}")
    end

    def test_patch_failure_propagates_without_build_request
      _out, _err, status = run_publish("TEST_GH_PATCH_FAIL" => "1")
      refute status.success?, "PATCH failure must fail the publish step"
      refute(calls.any? { |line| line.match?(%r{\Agh api --method POST}) },
             "PATCH failure must not fall back to a Pages build request; calls: #{calls.inspect}")
    end

    def test_pages_build_request_failure_propagates
      _out, _err, status = run_publish("TEST_GH_POST_FAIL" => "1")
      refute status.success?, "Pages build request failure must fail the publish step"
    end
  end
end
