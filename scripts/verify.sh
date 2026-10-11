#!/bin/bash
# Shared validation entry point for local work, pre-push and CI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-help}
usage() {
  echo 'Usage: bash scripts/verify.sh quick|offline|targeted|full|network|performance [TestClass[/testMethod] ...]'
  echo 'quick: source boundaries, documentation links, diff whitespace and workflow checks (no Simulator).'
  echo 'offline: host regression; targeted: selected Simulator tests; full: offline + all Simulator regression.'
  echo 'network and performance are explicit specialist checks; full does not run them.'
}
case "$MODE" in help|--help|-h) usage; exit 0;; esac
shift
case "$MODE" in
  targeted)
    [[ $# -gt 0 ]] || { usage >&2; exit 2; }
    for SELECTOR in "$@"; do
      [[ "$SELECTOR" =~ ^[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*)?$ ]] || { echo "Invalid test selector: $SELECTOR" >&2; exit 2; }
    done
    ;;
  quick|offline|full|network|performance)
    [[ $# -eq 0 ]] || { usage >&2; exit 2; };;
  *) usage >&2; exit 2;;
esac
cd "$ROOT"
RESULT="$ROOT/DerivedData/Validation/$(date +%Y%m%d-%H%M%S)-$$-verify-$MODE"
mkdir -p "$RESULT"
printf 'Validation: %s\nResults: %s\n' "$MODE" "$RESULT"
printf 'check\tstatus\texit_code\tlog\n' > "$RESULT/summary.tsv"
{
  printf 'Mode: %s\n' "$MODE"
  printf 'Selectors:'; printf ' %s' "$@"; printf '\n'
  git rev-parse HEAD
  git status --short
} > "$RESULT/environment.txt"
FAILED=0
finish() {
  local STATUS=$?
  trap - EXIT
  printf 'Overall: %s\nSummary: %s\n' "$([[ "$STATUS" == 0 ]] && echo passed || echo failed)" "$RESULT/summary.tsv"
  exit "$STATUS"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run_step() {
  local NAME=$1 STATUS=0
  shift
  echo "Running $NAME"
  if "$@" 2>&1 | tee "$RESULT/$NAME.log"; then
    printf '%s\tpassed\t0\t%s\n' "$NAME" "$RESULT/$NAME.log" >> "$RESULT/summary.tsv"
  else
    STATUS=$?
    printf '%s\tfailed\t%s\t%s\n' "$NAME" "$STATUS" "$RESULT/$NAME.log" >> "$RESULT/summary.tsv"
    FAILED=1
  fi
}
case "$MODE" in
  quick)
    run_step architecture python3 scripts/check-architecture.py
    run_step documentation python3 scripts/check-doc-links.py
    run_step working-diff git diff --check
    run_step staged-diff git diff --cached --check
    run_step workflow python3 -B -m unittest discover -s scripts/tests -p 'test_verify.py'
    ;;
  offline) run_step offline zsh offline-harness/run.sh;;
  targeted) run_step simulator bash scripts/simulator.sh test "$@";;
  full)
    run_step workflow python3 -B -m unittest discover -s scripts/tests -p 'test_verify.py'
    run_step offline zsh offline-harness/run.sh
    run_step simulator bash scripts/simulator.sh test
    ;;
  network) run_step network bash scripts/simulator.sh network;;
  performance) run_step performance zsh offline-harness/performance.sh;;
esac
exit "$FAILED"
