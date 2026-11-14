#!/bin/bash
set -euo pipefail
if [[ "${CI_XCODEBUILD_EXIT_CODE:?Missing build exit code}" != 0 ]]; then
  exit "$CI_XCODEBUILD_EXIT_CODE"
fi
case "${CI_WORKFLOW:?Missing workflow name}:${CI_XCODEBUILD_ACTION:?Missing action}" in
  Build:build-for-testing|Build:test-without-building)
    ;;
  Release:archive|Release:build)
    python3 "$(dirname "$0")/release.py" publish
    ;;
  *)
    echo "Unexpected workflow/action: $CI_WORKFLOW/$CI_XCODEBUILD_ACTION" >&2
    exit 1
    ;;
esac
