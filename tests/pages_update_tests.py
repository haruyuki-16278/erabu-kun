#!/usr/bin/env python3
"""Contract tests for scripts/update_release_page.py (gh-pages release page updater).

Contract: `update_release_page.py <site_dir> <tag> <run_number> <sha>` prints exactly
`updated` or `skipped` on stdout. Invalid input or site metadata fails with an
explicit error and writes no files. Uses only the Python standard library and
temporary site fixtures; no network and no git or gh calls.

Run: python3 tests/pages_update_tests.py
Focused: python3 tests/pages_update_tests.py UpdateReleasePageCliTests.test_updates_cta_href_and_release_tag
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from collections import Counter
from html.parser import HTMLParser

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
UPDATER = REPO_ROOT / "scripts" / "update_release_page.py"

REPOSITORY = "haruyuki-16278/erabu-kun"
FORK_REPOSITORY = "example-owner/fork-repo"
SHA = "0123456789abcdef0123456789abcdef01234567"
OTHER_SHA = "fedcba9876543210fedcba9876543210fedcba98"
TAG = "v2026.11.19-42"
RUN_NUMBER = 42

CTA_LABEL = "ダウンロード（最新版 .dmg）"
PLATFORM_TEXT = "macOS 13 以降対応・Apple公証(Notarized)済み・無料"
CTA_OLD = (
    '<a class="btn" href="https://github.com/haruyuki-16278/erabu-kun/releases/latest" '
    'target="_blank" rel="noopener">' + CTA_LABEL + "</a>"
)
PLATFORM_OLD = '<div class="version">' + PLATFORM_TEXT + "</div>"

ORIGINAL_INDEX = "\n".join(
    [
        "<!DOCTYPE html>",
        '<html lang="ja">',
        "<head>",
        '  <meta charset="utf-8">',
        '  <meta name="viewport" content="width=device-width, initial-scale=1">',
        "  <title>えらぶくん</title>",
        '  <link rel="stylesheet" href="style.css">',
        "</head>",
        "<body>",
        "  <main>",
        "    <h1>えらぶくん</h1>",
        "    " + CTA_OLD,
        "    " + PLATFORM_OLD,
        '    <p>インストール方法は<a href="https://github.com/haruyuki-16278/erabu-kun/releases/latest" '
        'target="_blank" rel="noopener">こちら</a>を確認してください。</p>',
        '    <p><a href="privacy.html">プライバシーポリシー</a></p>',
        "  </main>",
        "</body>",
        "</html>",
        "",
    ]
)

INTERACTIVE_TAGS = {"a", "button", "input", "select", "textarea", "form", "details", "summary", "iframe", "label"}


def expected_index(tag, repo=REPOSITORY, base=ORIGINAL_INDEX):
    """Pure function of the known original page: the only permitted index.html output."""
    url = "https://github.com/{}/releases/download/{}/Erabu-kun.dmg".format(repo, tag)
    cta_new = '<a class="btn" href="{}" target="_blank" rel="noopener">{}</a>'.format(url, CTA_LABEL)
    platform_new = '<div class="version"><span id="release-tag">{}</span> · {}</div>'.format(tag, PLATFORM_TEXT)
    return base.replace(CTA_OLD, cta_new).replace(PLATFORM_OLD, platform_new)


class Outline(HTMLParser):
    """Collects start tags and anchor attributes/text for structural comparison."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.anchors = []
        self._anchor = None

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))
        if tag == "a":
            self._anchor = [dict(attrs), ""]

    def handle_endtag(self, tag):
        if tag == "a" and self._anchor is not None:
            self.anchors.append(tuple([self._anchor[0], self._anchor[1]]))
            self._anchor = None

    def handle_data(self, data):
        if self._anchor is not None:
            self._anchor[1] += data


def outline(text):
    parser = Outline()
    parser.feed(text)
    parser.close()
    return parser


def snapshot(root):
    files = {}
    for path in sorted(pathlib.Path(root).rglob("*")):
        if path.is_file():
            files[path.relative_to(root).as_posix()] = path.read_bytes()
    return files


class UpdateReleasePageCliTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="pages-update-test-")
        self.root = pathlib.Path(self._tmp.name)
        self.site = self.root / "site"
        self.site.mkdir()
        self._write_site(self.site)

    def tearDown(self):
        self._tmp.cleanup()

    @staticmethod
    def _write_site(directory, index=ORIGINAL_INDEX):
        (directory / "index.html").write_text(index, encoding="utf-8")
        (directory / "privacy.html").write_text(
            '<!DOCTYPE html>\n<html lang="ja"><head><meta charset="utf-8"><title>プライバシー</title></head>'
            "<body><p>privacy</p></body></html>\n",
            encoding="utf-8",
        )
        (directory / "CNAME").write_text("erabu-kun.relicsnow.net\n", encoding="utf-8")
        (directory / "assets").mkdir(exist_ok=True)
        (directory / "assets" / "dummy.bin").write_bytes(b"\x00\x01dummy")

    def _run(self, tag=TAG, run_number=RUN_NUMBER, sha=SHA, repo=REPOSITORY, site=None):
        env = {"PATH": os.environ.get("PATH", ""), "PYTHONDONTWRITEBYTECODE": "1"}
        if repo is not None:
            env["GITHUB_REPOSITORY"] = repo
        return subprocess.run(
            [sys.executable, str(UPDATER), str(site or self.site), tag, str(run_number), sha],
            cwd=str(site or self.site),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def _index(self):
        return (self.site / "index.html").read_text(encoding="utf-8")

    def test_cli_script_exists(self):
        self.assertTrue(UPDATER.is_file(), "scripts/update_release_page.py does not exist; implementation required")

    def test_updates_cta_href_and_release_tag(self):
        result = self._run()
        self.assertEqual(result.returncode, 0, "stderr: " + result.stderr)
        self.assertEqual(result.stdout.strip(), "updated")
        self.assertEqual(self._index(), expected_index(TAG))

    def test_writes_release_json_with_exact_minimum_fields(self):
        self.assertEqual(self._run().returncode, 0)
        data = json.loads((self.site / "release.json").read_text(encoding="utf-8"))
        self.assertEqual(data, {"tag": TAG, "run_number": RUN_NUMBER, "commit": SHA})
        self.assertIs(type(data["run_number"]), int)

    def test_other_site_files_are_byte_identical(self):
        before = snapshot(self.site)
        self.assertEqual(self._run().returncode, 0)
        after = snapshot(self.site)
        for name in ("privacy.html", "CNAME", "assets/dummy.bin"):
            self.assertEqual(after[name], before[name], name + " must be unchanged")

    def test_preserves_accessibility_structure_and_labels(self):
        before = outline(ORIGINAL_INDEX)
        self.assertEqual(self._run().returncode, 0)
        after = outline(self._index())

        self.assertEqual(Counter(t for t, _ in before.tags if t != "span"),
                         Counter(t for t, _ in after.tags if t != "span"),
                         "only the span for the release tag may be added")
        self.assertEqual(
            Counter(t for t, _ in after.tags if t in INTERACTIVE_TAGS),
            Counter(t for t, _ in before.tags if t in INTERACTIVE_TAGS),
            "no interactive controls may be added",
        )
        self.assertEqual(len(after.anchors), len(before.anchors))
        for (b_attrs, b_text), (a_attrs, a_text) in zip(before.anchors, after.anchors):
            self.assertEqual(a_text, b_text, "anchor text must be unchanged")
            self.assertEqual({k: v for k, v in a_attrs.items() if k != "href"},
                             {k: v for k, v in b_attrs.items() if k != "href"},
                             "anchor attributes except href must be unchanged")

        cta = [attrs for attrs, text in after.anchors if attrs.get("class") == "btn"]
        self.assertEqual(len(cta), 1)
        self.assertEqual(cta[0]["href"], "https://github.com/{}/releases/download/{}/Erabu-kun.dmg".format(REPOSITORY, TAG))
        self.assertEqual(cta[0]["target"], "_blank")
        self.assertEqual(cta[0]["rel"], "noopener")
        cta_texts = [text for attrs, text in after.anchors if attrs.get("class") == "btn"]
        self.assertEqual(cta_texts, [CTA_LABEL], "accessible download label must stay Japanese")

        spans = [attrs for tag, attrs in after.tags if tag == "span" and attrs.get("id") == "release-tag"]
        self.assertEqual(len(spans), 1)
        self.assertEqual(set(spans[0].keys()), {"id"}, "release-tag span must have no extra attributes")
        self.assertIn('lang="ja"', self._index())

    def test_repeat_same_arguments_is_idempotent(self):
        self.assertEqual(self._run().returncode, 0)
        first = snapshot(self.site)
        second = self._run()
        self.assertEqual(second.returncode, 0, "stderr: " + second.stderr)
        self.assertEqual(second.stdout.strip(), "updated")
        self.assertEqual(snapshot(self.site), first, "repeating the same arguments must not change any bytes")
        self.assertEqual(self._index().count('id="release-tag"'), 1)

    def test_newer_run_replaces_tag_without_duplicating_prefix(self):
        self.assertEqual(self._run().returncode, 0)
        newer = self._run(tag="v2026.11.19-43", run_number=43, sha=OTHER_SHA)
        self.assertEqual(newer.returncode, 0, "stderr: " + newer.stderr)
        self.assertEqual(newer.stdout.strip(), "updated")
        self.assertEqual(self._index(), expected_index("v2026.11.19-43"))
        self.assertNotIn(TAG, self._index())
        data = json.loads((self.site / "release.json").read_text(encoding="utf-8"))
        self.assertEqual(data, {"tag": "v2026.11.19-43", "run_number": 43, "commit": OTHER_SHA})

    def test_lower_run_number_is_skipped_without_file_changes(self):
        self.assertEqual(self._run(tag="v2026.11.19-50", run_number=50).returncode, 0)
        before = snapshot(self.site)
        result = self._run(tag="v2026.11.19-41", run_number=41)
        self.assertEqual(result.returncode, 0, "stderr: " + result.stderr)
        self.assertEqual(result.stdout.strip(), "skipped")
        self.assertEqual(snapshot(self.site), before)

    def test_same_run_number_with_different_sha_or_tag_fails_without_writes(self):
        self.assertEqual(self._run().returncode, 0)
        before = snapshot(self.site)
        for label, kwargs in (
            ("different sha", {"tag": TAG, "sha": OTHER_SHA}),
            ("different tag", {"tag": "v2026.11.18-42", "sha": SHA}),
        ):
            with self.subTest(label):
                result = self._run(**kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.strip(), "an explicit error message is required")
                self.assertEqual(snapshot(self.site), before)

    def test_invalid_arguments_fail_without_writes(self):
        cases = [
            ("impossible month", {"tag": "v2026.13.01-42"}),
            ("nonexistent day", {"tag": "v2026.02.30-42"}),
            ("missing v prefix", {"tag": "2026.11.19-42"}),
            ("shell injection", {"tag": "v2026.11.19-42;touch pwned"}),
            ("command substitution", {"tag": "v2026.11.19-$(id)"}),
            ("suffix mismatch", {"tag": "v2026.11.19-41"}),
            ("zero run number", {"tag": "v2026.11.19-0", "run_number": 0}),
            ("negative run number", {"tag": "v2026.11.19--1", "run_number": -1}),
            ("non-numeric run number", {"tag": "v2026.11.19-4x", "run_number": "4x"}),
            ("short sha", {"sha": "0123456"}),
            ("non-hex sha", {"sha": "g" * 40}),
        ]
        for label, kwargs in cases:
            with self.subTest(label):
                site_dir = self.root / ("case-" + str(abs(hash(label))))
                site_dir.mkdir()
                self._write_site(site_dir)
                before = snapshot(site_dir)
                result = self._run(site=site_dir, **kwargs)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.strip(), "an explicit error message is required")
                self.assertEqual(snapshot(site_dir), before, "invalid input must not write any file")
                self.assertFalse((site_dir / "release.json").exists())

    def test_bad_site_metadata_fails_without_writes(self):
        cases = [
            ("missing CTA", ORIGINAL_INDEX.replace(CTA_OLD, "")),
            ("duplicate CTA", ORIGINAL_INDEX.replace(CTA_OLD, CTA_OLD + "\n" + CTA_OLD)),
            ("missing version", ORIGINAL_INDEX.replace(PLATFORM_OLD, "")),
            ("duplicate version", ORIGINAL_INDEX.replace(PLATFORM_OLD, PLATFORM_OLD + "\n" + PLATFORM_OLD)),
        ]
        for label, index in cases:
            with self.subTest(label):
                site_dir = self.root / ("site-" + str(abs(hash(label))))
                site_dir.mkdir()
                self._write_site(site_dir, index=index)
                before = snapshot(site_dir)
                result = self._run(site=site_dir)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.strip(), "an explicit error message is required")
                self.assertEqual(snapshot(site_dir), before, "bad site metadata must not write any file")

    def test_download_url_uses_github_repository_env(self):
        result = self._run(repo=FORK_REPOSITORY)
        self.assertEqual(result.returncode, 0, "stderr: " + result.stderr)
        self.assertEqual(self._index(), expected_index(TAG, repo=FORK_REPOSITORY))

    def test_missing_or_malformed_github_repository_fails_without_writes(self):
        for label, repo in (("unset", None), ("malformed", "bad repo;x")):
            with self.subTest(label):
                site_dir = self.root / ("repo-" + label)
                site_dir.mkdir()
                self._write_site(site_dir)
                before = snapshot(site_dir)
                result = self._run(site=site_dir, repo=repo)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.strip(), "an explicit error message is required")
                self.assertEqual(snapshot(site_dir), before)


if __name__ == "__main__":
    unittest.main()
