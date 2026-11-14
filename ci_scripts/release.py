#!/usr/bin/env python3
"""Package Xcode Cloud products for sideloading and attach them to a draft."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

REPOSITORY = "Fab1e2000/NeoBili"
API = f"https://api.github.com/repos/{REPOSITORY}"


def metadata(root, env):
    with (root / "NeoBili/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a release version in X.Y.Z format")
    commit = env.get("CI_COMMIT", "")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Missing CI_COMMIT")
    if env.get("CI_PULL_REQUEST_NUMBER"):
        raise ValueError("Release must not run on pull requests")
    tag = env.get("CI_TAG", "")
    if tag and tag != f"v{version}":
        raise ValueError(f"Tag {tag} does not match version {version}")
    manual = not tag
    if manual:
        number = env.get("CI_BUILD_NUMBER", "")
        if not number.isdigit():
            raise ValueError("Missing CI_BUILD_NUMBER for manual release")
        tag = f"cloud-build-{number}"
        title = f"NeoBili {version} — Cloud build {number}"
        body = "手动构建预览，仅供下载检查。保持此草稿未公开；正式发布使用 vX.Y.Z 标签。"
    else:
        notes = (root / "docs/releases" / f"{tag}.md").read_text()
        first, _, rest = notes.partition("\n")
        title = first[2:] if first.startswith("# ") else f"NeoBili {tag}"
        body = rest if first.startswith("# ") else notes
    body += f"\n\n**构建信息**：提交 `{commit}`，由 [Xcode Cloud]({env['CI_BUILD_URL']}) 构建。\n"
    return {"tag_name": tag, "target_commitish": commit, "name": title,
            "body": body, "draft": True, "prerelease": manual}, info


def request(token, method, path, data=None, content_type="application/json"):
    url = path if path.startswith("https://") else API + path
    body = json.dumps(data).encode() if isinstance(data, dict) else data
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28", "Content-Type": content_type}
    with urlopen(Request(url, data=body, headers=headers, method=method), timeout=300) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def find_release(token, tag):
    # Listing includes unpublished drafts, including those without a Git tag yet.
    page = 1
    while True:
        releases = request(token, "GET", f"/releases?per_page=100&page={page}")
        for release in releases:
            if release["tag_name"] == tag:
                return release
        if len(releases) < 100:
            return None
        page += 1


def check_release(token, details, tagged):
    if tagged:
        commit = request(token, "GET", "/commits/" + quote(details["tag_name"], safe=""))
        if commit["sha"] != details["target_commitish"]:
            raise ValueError("GitHub tag points to a different commit")
    release = find_release(token, details["tag_name"])
    if release:
        if not release["draft"]:
            raise ValueError("Release is already public; refusing to replace its assets")
        if release["target_commitish"] != details["target_commitish"]:
            raise ValueError("Existing draft belongs to another commit")
    return release


def package(app, destination, source_info):
    if not (app / "Info.plist").is_file():
        raise ValueError(f"Missing built app: {app}")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination) as temporary:
        work = Path(temporary)
        copied = work / "Payload/NeoBili.app"
        copied.parent.mkdir()
        shutil.copytree(app, copied, symlinks=True)
        with (copied / "Info.plist").open("rb") as source:
            built = plistlib.load(source)
        version = source_info["CFBundleShortVersionString"]
        if built["CFBundleShortVersionString"] != version:
            raise ValueError("Built app version differs from the source version")
        # Cloud assigns its build number; preserve the project's distribution number.
        built["CFBundleVersion"] = source_info["CFBundleVersion"]
        with (copied / "Info.plist").open("wb") as output:
            plistlib.dump(built, output)
        for profile in copied.rglob("embedded.mobileprovision"):
            profile.unlink()
        for file in copied.rglob("*"):
            if file.is_file() and not file.is_symlink():
                subprocess.run(["codesign", "--remove-signature", str(file)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for framework in sorted(copied.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(framework)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(copied)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(copied)], check=True)
        ipa = destination / f"NeoBili-v{version}-unsigned.ipa"
        # zip updates existing archives, so remove only this generated output first.
        ipa.unlink(missing_ok=True)
        subprocess.run(["zip", "-qry", str(ipa.resolve()), "Payload"], cwd=work, check=True)
    checksum = destination / "SHA256SUMS.txt"
    hasher = hashlib.sha256()
    with ipa.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(chunk)
    checksum.write_text(f"{hasher.hexdigest()}  {ipa.name}\n")
    return [ipa, checksum]


def publish(token, details, files, tagged):
    release = check_release(token, details, tagged)
    if release is None:
        release = request(token, "POST", "/releases", details)
    else:
        release = request(token, "PATCH", f"/releases/{release['id']}", details)
    # Retrying the same draft replaces these two artifacts without publishing it.
    names = {file.name for file in files}
    for asset in release.get("assets", []):
        if asset["name"] in names:
            request(token, "DELETE", f"/releases/assets/{asset['id']}")
    upload = release["upload_url"].split("{", 1)[0]
    for file in files:
        request(token, "POST", upload + "?" + urlencode({"name": file.name}),
                file.read_bytes(), "application/octet-stream")
    print(f"Draft ready: {release['html_url']}")


def main():
    command = sys.argv[1] if len(sys.argv) == 2 else ""
    if command not in ("check", "publish"):
        raise ValueError("Usage: release.py check|publish")
    env = os.environ
    root = Path(env["CI_PRIMARY_REPOSITORY_PATH"])
    token = env.get("NEOBILI_RELEASE_TOKEN")
    if not token:
        raise ValueError("Set secret NEOBILI_RELEASE_TOKEN in the Release workflow")
    details, info = metadata(root, env)
    tagged = bool(env.get("CI_TAG"))
    check_release(token, details, tagged)
    if command == "check":
        print(f"Release preflight passed: {details['tag_name']}")
        return
    if env.get("CI_XCODEBUILD_EXIT_CODE") != "0":
        raise ValueError("Xcode build did not succeed")
    if env["CI_XCODEBUILD_ACTION"] == "archive":
        app = Path(env["CI_ARCHIVE_PATH"]) / "Products/Applications/NeoBili.app"
    else:
        app = Path(env["CI_DERIVED_DATA_PATH"]) / "Build/Products/Release-iphoneos/NeoBili.app"
    destination = root / "DerivedData/CloudRelease"
    files = package(app, destination, info)
    publish(token, details, files, tagged)


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        sys.exit(f"GitHub API failed: HTTP {error.code} {error.reason}")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
