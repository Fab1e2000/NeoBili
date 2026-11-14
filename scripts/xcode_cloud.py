#!/usr/bin/env python3
"""Start an approved Cloud build and report its result on the requested commit."""
import json
import os
from pathlib import Path
import signal
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

APPLE = "https://api.appstoreconnect.apple.com/v1"
GITHUB = "https://api.github.com"
CONTEXT = "Xcode Cloud / Build"


def apple_token(env):
    import jwt
    now = int(time.time())
    return jwt.encode({"iss": env["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
                       "aud": "appstoreconnect-v1"}, env["ASC_PRIVATE_KEY"], algorithm="ES256",
                      headers={"kid": env["ASC_KEY_ID"], "typ": "JWT"})


def request(base, token, method, path, data=None):
    url = path if path.startswith(base + "/") else base + path
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    if base == GITHUB:
        headers.update({"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    body = json.dumps(data).encode() if data is not None else None
    with urlopen(Request(url, data=body, headers=headers, method=method), timeout=60) as response:
        return json.load(response)


def find_resource(call, path, matches):
    while path:
        response = call("GET", path)
        found = [item for item in response["data"] if matches(item["attributes"])]
        if len(found) > 1:
            raise ValueError("Multiple matching Cloud resources")
        if found:
            return found[0]["id"]
        path = response.get("links", {}).get("next")
    raise ValueError("Requested PR or branch is not available in Xcode Cloud")


def build_relationships(cloud, workflow, repository, event, ref):
    relationships = {"workflow": {"data": {"type": "ciWorkflows", "id": workflow}}}
    pr = event.get("pull_request")
    if pr:
        resource = find_resource(cloud, f"/scmRepositories/{repository}/pullRequests?limit=200",
                                 lambda value: value["number"] == pr["number"] and not value["isClosed"])
        relationships["pullRequest"] = {"data": {"type": "scmPullRequests", "id": resource}}
    else:
        resource = find_resource(cloud, f"/scmRepositories/{repository}/gitReferences?limit=200",
                                 lambda value: value["canonicalName"] == ref and not value["isDeleted"])
        relationships["sourceBranchOrTag"] = {"data": {"type": "scmGitReferences", "id": resource}}
    return relationships


def validate_commits(attributes, expected, destination=None):
    source = attributes.get("sourceCommit")
    if source and source["commitSha"] != expected:
        raise ValueError("Source changed after approval; run the workflow for the new commit")
    target = attributes.get("destinationCommit")
    if destination and target and target["commitSha"] != destination:
        raise ValueError("Target branch changed; run the workflow against the current target")
    if attributes["executionProgress"] == "COMPLETE" and not source:
        raise ValueError("Completed Cloud build has no source commit")


def main():
    env = os.environ
    event = json.loads(Path(env["GITHUB_EVENT_PATH"]).read_text())
    pr = event.get("pull_request")
    expected = pr["head"]["sha"] if pr else env["GITHUB_SHA"]
    destination = pr["base"]["sha"] if pr else None
    repo = env["GITHUB_REPOSITORY"]
    workflow = env["CLOUD_BUILD_WORKFLOW_ID"]
    github = lambda method, path, data=None: request(GITHUB, env["GH_TOKEN"], method, path, data)
    cloud = lambda method, path, data=None: request(APPLE, apple_token(env), method, path, data)
    target_url = f"{env['GITHUB_SERVER_URL']}/{repo}/actions/runs/{env['GITHUB_RUN_ID']}"

    def status(state, description):
        github("POST", f"/repos/{repo}/statuses/{expected}",
               {"state": state, "context": CONTEXT, "description": description[:140], "target_url": target_url})

    def interrupted(_signum, _frame):
        raise InterruptedError("Approval run canceled; cloud build status is available in Xcode Cloud")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    status("pending", "Approved; starting Xcode Cloud")
    try:
        if pr:
            current = github("GET", f"/repos/{repo}/pulls/{pr['number']}")
            if current["head"]["sha"] != expected or current["base"]["sha"] != destination:
                raise ValueError("Pull request changed while waiting for approval")
        workflow_data = cloud("GET", f"/ciWorkflows/{workflow}?include=repository")["data"]
        repository = workflow_data["relationships"]["repository"]["data"]["id"]
        relationships = build_relationships(cloud, workflow, repository, event, env["GITHUB_REF"])
        build = cloud("POST", "/ciBuildRuns", {"data": {"type": "ciBuildRuns", "relationships": relationships}})["data"]
        print(f"Xcode Cloud build {build['attributes']['number']}: {build['id']}", flush=True)
        Path(env["GITHUB_STEP_SUMMARY"]).write_text(
            f"Xcode Cloud build {build['attributes']['number']} · {build['id']}\n\nCommit: {expected}\n")
        deadline = time.monotonic() + 50 * 60
        previous = None
        while True:
            attributes = build["attributes"]
            validate_commits(attributes, expected, destination)
            progress = (attributes["executionProgress"], attributes.get("completionStatus"))
            if progress != previous:
                print(f"Cloud state: {progress[0]} {progress[1] or ''}", flush=True)
                previous = progress
            if progress[0] == "COMPLETE":
                if progress[1] != "SUCCEEDED":
                    raise ValueError(f"Xcode Cloud finished: {progress[1]}")
                status("success", "Xcode Cloud regression passed")
                return
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for Xcode Cloud; inspect its build report")
            time.sleep(30)
            build = cloud("GET", f"/ciBuildRuns/{build['id']}")["data"]
    except BaseException:
        status("failure", "Cloud regression did not complete successfully; see the approval run")
        raise


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        sys.exit(f"API request failed: HTTP {error.code} {error.reason}")
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
