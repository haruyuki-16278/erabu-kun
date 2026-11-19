#!/usr/bin/env python3
"""Update the gh-pages release page for one release.

Usage: update_release_page.py <site_dir> <tag> <run_number> <sha>

Prints `updated` or `skipped`. Invalid input or site metadata exits non-zero with
an explicit message on stderr and writes no file.
"""

import datetime
import json
import os
import pathlib
import re
import sys

TAG_RE = re.compile(r"v(\d{4})\.(\d{2})\.(\d{2})-([1-9][0-9]*)")
RUN_NUMBER_RE = re.compile(r"[1-9][0-9]*")
SHA_RE = re.compile(r"[0-9a-f]{40}")
OWNER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*")
NAME_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*")
RELEASE_KEYS = {"tag", "run_number", "commit"}

CTA_RE = re.compile(r'<a class="btn" href="[^"]*" target="_blank" rel="noopener">([^<]*)</a>')
VERSION_RE = re.compile(r'<div class="version">((?:<span id="release-tag">[^<]*</span> \u00b7 )?[^<]*)</div>')
RELEASE_TAG_PREFIX_RE = re.compile(r'\A(?:<span id="release-tag">[^<]*</span> \u00b7 )?')


def fail(message):
    print("error: " + message, file=sys.stderr)
    sys.exit(1)


def validate_tag(tag, run_number):
    match = TAG_RE.fullmatch(tag)
    if match is None:
        fail("tag must match vYYYY.MM.DD-N: " + repr(tag))
    year, month, day, suffix = (int(part) for part in match.groups())
    try:
        datetime.date(year, month, day)
    except ValueError:
        fail("tag date is not a valid calendar date: " + repr(tag))
    if suffix != run_number:
        fail("tag suffix {} does not match run number {}".format(suffix, run_number))


def validate_repository(repository):
    owner, separator, name = repository.partition("/")
    if not separator or OWNER_RE.fullmatch(owner) is None or NAME_RE.fullmatch(name) is None:
        fail("GITHUB_REPOSITORY must be owner/name: " + repr(repository))


def read_stored_release(path):
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        fail("release.json is unreadable or not JSON: " + str(error))
    if not isinstance(data, dict) or set(data.keys()) != RELEASE_KEYS:
        fail("release.json must be an object with exactly keys tag, run_number, commit")
    tag, run_number, commit = data["tag"], data["run_number"], data["commit"]
    if not isinstance(tag, str) or not isinstance(commit, str):
        fail("release.json tag and commit must be strings")
    if type(run_number) is not int or run_number < 1:
        fail("release.json run_number must be a positive integer")
    if SHA_RE.fullmatch(commit) is None:
        fail("release.json commit must be a 40-character lowercase hex SHA")
    validate_tag(tag, run_number)
    return {"tag": tag, "run_number": run_number, "commit": commit}


def render_index(index_text, repository, tag):
    if index_text.count('class="btn"') != 1 or len(CTA_RE.findall(index_text)) != 1:
        fail("index.html must contain exactly one download CTA with class btn")
    if index_text.count('<div class="version">') != 1 or len(VERSION_RE.findall(index_text)) != 1:
        fail("index.html must contain exactly one div class version")

    url = "https://github.com/{}/releases/download/{}/Erabu-kun.dmg".format(repository, tag)
    index_text = CTA_RE.sub(
        lambda match: '<a class="btn" href="{}" target="_blank" rel="noopener">{}</a>'.format(url, match.group(1)),
        index_text,
    )

    def replace_version(match):
        platform_text = RELEASE_TAG_PREFIX_RE.sub("", match.group(1), count=1)
        return '<div class="version"><span id="release-tag">{}</span> \u00b7 {}</div>'.format(tag, platform_text)

    return VERSION_RE.sub(replace_version, index_text, count=1)


def write_atomic(path, text):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="")
    os.replace(temporary, path)


def main(argv):
    if len(argv) != 5:
        fail("usage: update_release_page.py <site_dir> <tag> <run_number> <sha>")
    site_dir = pathlib.Path(argv[1])
    tag = argv[2]
    run_text = argv[3]
    sha = argv[4]

    repository = os.environ.get("GITHUB_REPOSITORY")
    if repository is None:
        fail("GITHUB_REPOSITORY is required")
    validate_repository(repository)

    if RUN_NUMBER_RE.fullmatch(run_text) is None:
        fail("run number must be a positive integer: " + repr(run_text))
    run_number = int(run_text)
    validate_tag(tag, run_number)
    if SHA_RE.fullmatch(sha) is None:
        fail("sha must be a 40-character lowercase hex SHA")

    index_path = site_dir / "index.html"
    release_path = site_dir / "release.json"
    if not index_path.is_file():
        fail("index.html is missing in " + str(site_dir))

    stored = read_stored_release(release_path)
    if stored is not None:
        if run_number < stored["run_number"]:
            print("skipped")
            return 0
        if run_number == stored["run_number"] and (tag, sha) != (stored["tag"], stored["commit"]):
            fail("run {} is already published with a different tag or commit".format(run_number))

    index_text = index_path.read_text(encoding="utf-8")
    new_index = render_index(index_text, repository, tag)
    new_release = json.dumps({"tag": tag, "run_number": run_number, "commit": sha}, indent=2) + "\n"

    write_atomic(index_path, new_index)
    write_atomic(release_path, new_release)
    print("updated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
