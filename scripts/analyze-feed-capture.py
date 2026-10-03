#!/usr/bin/env python3
"""Replay operation-labelled mitmproxy captures; emit only redacted feed differences.

python3 scripts/analyze-feed-capture.py --group cold=/private/cold.flows \
  --group pull=/private/pull.flows --output DerivedData/Validation/feed-diff.json
Raw captures remain outside the repository. No credential values or persistent hashes
are emitted. Equal sensitive values share an opaque per-run ordinal, never a token.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
from urllib.parse import urlsplit

NUMERIC = set("build flush idx pull column fnval fnver fourk disable_rcmd qn recsys_mode login_event autoplay_card video_mode auto_refresh_state client_attr force_host guidance https_url_req inline_danmu inline_sound inline_sound_cold_state player_net qn_policy soft_fnval teenagers_age voice_balance device_type".split())
TEXT = {
    "mobi_app": {"iphone", "android", "android_hd"}, "platform": {"ios", "android"},
    "device": {"phone", "pad"}, "actionKey": {"appkey"},
    "c_locale": {"zh-Hans_CN", "zh_CN", "en_US"}, "s_locale": {"zh-Hans_CN", "zh_CN", "en_US"},
    "open_event": {"cold", "warm", "hot", ""}, "network": {"wifi", "cellular", "mobile", "unknown"},
}
# Classifications are investigation hints, not declarations that observed stability proves constancy.
ROLE = {**{k: "account/device/session; never copy" for k in ["access_key", "buvid", "guestid", "session_id", "x-bili-mid", "x-bili-aurora-eid", "x-bili-ticket"]},
        **{k: "operation/state; correlate with labelled actions" for k in ["open_event", "login_event", "auto_refresh_state", "flush", "idx", "pull"]},
        **{k: "settings/capabilities; compare toggles before fixing" for k in ["client_attr", "inline_danmu", "inline_sound", "inline_sound_cold_state", "autoplay_card", "video_mode", "fnval", "soft_fnval"]},
        **{k: "network; compare Wi-Fi/cellular" for k in ["network", "player_net", "x-bili-network-bin"]},
        **{k: "server/advertising; follow lifecycle, never copy" for k in ["ad_extra", "banner_hash", "splash_id", "splash_ids", "splash_creative_id"]}}


def safe_value(key, value, secret):
    if value == "": return ""
    if key in NUMERIC and re.fullmatch(r"-?\d{1,12}", value): return value
    if key in TEXT and value in TEXT[key]: return value
    if key == "appkey" and re.fullmatch(r"[a-f0-9]{16}", value): return value
    if key == "device_name" and re.fullmatch(r"(?:iPhone[ A-Za-z0-9,+]*|iPad[ A-Za-z0-9,+]*)", value): return value
    if key in {"statistics", "player_extra_content"}:
        try:
            data = json.loads(value)
            if not isinstance(data, dict): raise ValueError()
            if key == "player_extra_content" and set(data) == {"short_edge", "long_edge"} and all(re.fullmatch(r"\d{1,5}", str(v)) for v in data.values()): return data
            if key == "statistics" and set(data).issubset({"appId", "platform", "version", "abtest"}) and data.get("abtest", "") == "":
                return {k: v for k, v in data.items() if
                        (k in {"appId", "platform"} and isinstance(v, int)) or
                        (k == "version" and isinstance(v, str) and re.fullmatch(r"\d{1,3}\.\d{1,3}\.\d{1,3}", v)) or
                        (k == "abtest" and v == "")}
        except (ValueError, TypeError): pass
    # Digest exists only in child/parent memory during this run. Final output uses ordinals.
    digest = hmac.new(secret, value.encode(), hashlib.sha256).hexdigest()
    return {"redacted": digest, "length": len(value)}


def response(flow):
    if urlsplit(flow.request.pretty_url).path != "/x/v2/feed/index": return
    secret = bytes.fromhex(os.environ["NEOBILI_CAPTURE_REDACTION_KEY"])
    query = {k: safe_value(k, v, secret) for k, v in flow.request.query.items()}
    headers = {k.lower(): safe_value(k.lower(), v, secret) for k, v in flow.request.headers.items()}
    print(json.dumps({"query": query, "headers": headers,
                      "http_status": flow.response.status_code if flow.response else None}, ensure_ascii=False))


def assemble(groups):
    tags = {}
    def tag(value):
        if isinstance(value, dict) and "redacted" in value:
            digest = value["redacted"]
            if digest not in tags: tags[digest] = len(tags) + 1
            return {"private_value": tags[digest], "length": value["length"]}
        return value
    samples = []
    for label, rows in groups:
        for row in rows:
            samples.append({"operation": label, "request": len(samples) + 1,
                            "query": {k: tag(v) for k, v in row["query"].items()},
                            "headers": {k: tag(v) for k, v in row["headers"].items()},
                            "http_status": row["http_status"]})
    differences = []
    for section in ["query", "headers"]:
        keys = sorted(set().union(*(set(s[section]) for s in samples))) if samples else []
        for key in keys:
            values = [{"operation": s["operation"], "request": s["request"],
                       "value": s[section].get(key, {"absent": True})} for s in samples]
            unique = {json.dumps(v["value"], sort_keys=True) for v in values}
            differences.append({"section": section, "field": key, "changed": len(unique) > 1,
                                "role": ROLE.get(key, "unconfirmed; stability is not a protocol constant"),
                                "values": values})
    return {"warning": "An unchanged sample is not proof of a constant. Private ordinals are scoped to this run only.",
            "samples": samples, "differences": differences}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", action="append", required=True, metavar="OPERATION=FILE.flows")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    env = dict(os.environ, NEOBILI_CAPTURE_REDACTION_KEY=secrets.token_hex(32))
    groups = []
    for group in args.group:
        label, sep, file = group.partition("=")
        if not sep or not re.fullmatch(r"[a-zA-Z0-9_-]{1,40}", label): parser.error("Use a short operation label and a file path")
        if not Path(file).is_file(): parser.error("Capture file is missing")
        result = subprocess.run(["mitmdump", "-q", "-n", "-r", file, "-s", str(Path(__file__).resolve())],
                                env=env, capture_output=True, text=True)
        # Never echo raw subprocess logs; they can contain sensitive flow material.
        if result.returncode: raise SystemExit("Capture replay failed; raw output withheld")
        rows = []
        for line in result.stdout.splitlines():
            if line.startswith('{"query":'):
                rows.append(json.loads(line))
        if not rows: raise SystemExit("No completed feed requests found; check capture and mitmdump availability")
        groups.append((label, rows))
    output = assemble(groups)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(f"Analysed {len(output['samples'])} feed requests across {len(groups)} labelled groups")
    print(f"Changed fields: {sum(d['changed'] for d in output['differences'])}")


if __name__ == "__main__": main()
