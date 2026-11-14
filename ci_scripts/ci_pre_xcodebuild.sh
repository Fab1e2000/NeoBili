#!/bin/bash
set -euo pipefail
case "${CI_WORKFLOW:?Missing workflow name}:${CI_XCODEBUILD_ACTION:?Missing action}" in
  Build:build-for-testing)
    cd "${CI_PRIMARY_REPOSITORY_PATH:?Missing repository path}"
    bash scripts/verify.sh quick
    ;;
  Build:test-without-building)
    ;;
  Release:archive|Release:build)
    cd "${CI_PRIMARY_REPOSITORY_PATH:?Missing repository path}"
    python3 ci_scripts/release.py check
    ;;
  *)
    echo "Unexpected workflow/action: $CI_WORKFLOW/$CI_XCODEBUILD_ACTION" >&2
    exit 1
    ;;
esac
