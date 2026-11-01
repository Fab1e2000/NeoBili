#!/usr/bin/env python3
"""Write sidestore/apps.json for one published NeoBili release.

SideStore and AltStore read this file from a stable URL. The download address
only works after the GitHub Release is public, so drafts must not be recorded.
"""

from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Fab1e2000/NeoBili"
SOURCE_URL = "https://n015.top/neobili/apps.json"
BUNDLE_IDENTIFIER = "com.elsterlee.NeoBili"
TAG_PATTERN = re.compile(r"^v(\d+\.\d+\.\d+)$")
TIMESTAMP_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$")
APP_DESCRIPTION = (
    "为 iPhone 打造的非官方哔哩哔哩客户端。使用 SwiftUI 和 MPVKit，"
    "在本机直接访问哔哩哔哩的公开服务。安装包只有 ad-hoc 签名，由 SideStore 用你自己的 Apple ID 重签。"
)
PERMISSIONS = [
    {
        "type": "background-audio",
        "usageDescription": "在后台继续播放视频和直播。",
    },
    {
        "type": "photos",
        "usageDescription": "保存登录二维码到相册，便于在哔哩哔哩 App 的扫一扫里从相册识别登录。",
    },
]


def changelog(notes):
    """Release notes shown by SideStore, without the title or manual-install section."""
    lines = notes.splitlines()
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    text = "\n".join(lines).strip()
    install = re.search(r"(?m)^## 安装\s*$", text)
    if install:
        text = text[:install.start()].strip()
    if not text:
        raise ValueError("更新说明去掉标题和安装节后是空的")
    return text


def build_source(tag, size, published_at, notes):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError(f"标签须为 vX.Y.Z，收到 {tag}")
    if isinstance(published_at, str) and published_at.endswith("+00:00"):
        published_at = published_at[:-6] + "Z"
    if not isinstance(published_at, str) or not TIMESTAMP_PATTERN.fullmatch(published_at):
        raise ValueError(f"发布时间须为 UTC 时间，收到 {published_at}")
    if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
        raise ValueError(f"IPA 字节数须为正整数，收到 {size}")
    version = match.group(1)
    download_url = f"https://n015.top/neobili/NeoBili-{tag}-unsigned.ipa"
    icon_url = "https://n015.top/neobili/icon.png"
    description = changelog(notes)
    return {
        "name": "NeoBili",
        "identifier": "com.elsterlee.NeoBili.source",
        "sourceURL": SOURCE_URL,
        "apps": [
            {
                "name": "NeoBili",
                "bundleIdentifier": BUNDLE_IDENTIFIER,
                "developerName": "Elster Lee",
                "subtitle": "第三方哔哩哔哩客户端",
                "version": version,
                "versionDate": published_at,
                "versionDescription": description,
                "downloadURL": download_url,
                "localizedDescription": APP_DESCRIPTION,
                "iconURL": icon_url,
                "tintColor": "FB7AB3",
                "size": size,
                "screenshotURLs": [],
                "permissions": PERMISSIONS,
                "versions": [
                    {
                        "version": version,
                        "date": published_at,
                        "localizedDescription": description,
                        "downloadURL": download_url,
                        "size": size,
                    }
                ],
            }
        ],
    }


def dumps(payload):
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def github_release(tag):
    result = subprocess.run(
        ["gh", "release", "view", tag, "--json", "isDraft,publishedAt,assets"],
        check=False, capture_output=True, text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or "无法读取 GitHub Release"
        raise ValueError(message)
    payload = json.loads(result.stdout)
    if payload["isDraft"]:
        raise ValueError(f"{tag} 仍是草稿，安装包还不能公开下载")
    name = f"NeoBili-{tag}-unsigned.ipa"
    matches = [item for item in payload["assets"] if item.get("name") == name]
    if len(matches) != 1:
        raise ValueError(f"找不到唯一的 {name}")
    return matches[0]["size"], payload["publishedAt"]


def write_source(tag, size, published_at, output):
    notes_path = ROOT / "docs" / "releases" / f"{tag}.md"
    if not notes_path.is_file():
        raise ValueError(f"缺少更新说明 {notes_path.relative_to(ROOT)}")
    payload = build_source(tag, size, published_at, notes_path.read_text())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(dumps(payload))
    return payload


def main(argv=None):
    parser = argparse.ArgumentParser(description="写入 SideStore 软件源")
    parser.add_argument("--tag", required=True, help="已公开的版本标签，例如 v1.3.1")
    parser.add_argument("--from-github", action="store_true", help="从 GitHub Release 读取大小和发布时间")
    parser.add_argument("--size", type=int, help="IPA 的字节数")
    parser.add_argument("--published-at", help="Release 的 UTC 发布时间")
    parser.add_argument("--output", type=Path, default=ROOT / "sidestore" / "apps.json")
    args = parser.parse_args(argv)
    try:
        if args.from_github:
            size, published_at = github_release(args.tag)
        else:
            if args.size is None or args.published_at is None:
                raise ValueError("需要 --size 和 --published-at，或改用 --from-github")
            size, published_at = args.size, args.published_at
        payload = write_source(args.tag, size, published_at, args.output)
    except (ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    app = payload["apps"][0]
    print(f"Wrote {args.output} for {app['version']} ({app['size']} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
