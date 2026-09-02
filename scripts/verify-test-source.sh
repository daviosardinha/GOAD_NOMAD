#!/usr/bin/env bash
set -Eeuo pipefail

# GOAD Kingdoms test-source gate.
#
# Policy: Git is the source of truth. Changes are committed and pushed first;
# test machines then fetch/pull that exact source before any validation run.
# This script fails closed when the local checkout cannot be proven to match
# its upstream branch (or an explicitly requested detached commit).

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

usage() {
    cat <<'EOF'
Usage:
  bash scripts/verify-test-source.sh [expected_commit]

Examples:
  bash scripts/verify-test-source.sh
  bash scripts/verify-test-source.sh 0123456789abcdef0123456789abcdef01234567

The gate verifies:
  - this is a Git checkout;
  - the worktree/index are clean;
  - HEAD matches expected_commit when supplied;
  - an attached branch has an upstream;
  - remote refs can be fetched;
  - the local branch is neither ahead, behind, nor diverged from upstream.

A detached HEAD is accepted only when expected_commit is supplied and matches
HEAD exactly. This permits reproducibility tests pinned to an immutable commit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

EXPECTED_COMMIT="${1:-${GOAD_KINGDOMS_EXPECTED_COMMIT:-}}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail 'not inside a Git worktree'
cd "${ROOT}"

HEAD_SHA="$(git rev-parse HEAD)"

if [[ -n "$(git status --porcelain=v1 --untracked-files=normal)" ]]; then
    echo '[INFO] Local differences:' >&2
    git status --short >&2
    fail 'working tree is not clean; commit/push changes in Git before testing'
fi
pass 'working tree is clean'

if [[ -n "${EXPECTED_COMMIT}" ]]; then
    EXPECTED_SHA="$(git rev-parse "${EXPECTED_COMMIT}^{commit}" 2>/dev/null)" \
        || fail "expected commit cannot be resolved locally: ${EXPECTED_COMMIT}"
    [[ "${HEAD_SHA}" == "${EXPECTED_SHA}" ]] \
        || fail "HEAD ${HEAD_SHA} does not match expected commit ${EXPECTED_SHA}"
    pass "HEAD matches expected commit ${HEAD_SHA}"
fi

BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

if [[ -z "${BRANCH}" ]]; then
    [[ -n "${EXPECTED_COMMIT}" ]] \
        || fail 'detached HEAD requires an explicit expected_commit for reproducible testing'
    pass "detached HEAD is pinned to expected commit ${HEAD_SHA}"
    printf '\nGOAD KINGDOMS SOURCE GATE: READY\n'
    printf 'HEAD: %s\n' "${HEAD_SHA}"
    printf 'Mode: detached/pinned\n'
    exit 0
fi

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
[[ -n "${UPSTREAM}" ]] || fail "branch ${BRANCH} has no upstream; push it and set tracking before testing"

printf '[INFO] Fetching remote refs before comparison...\n'
git fetch --all --prune --quiet || fail 'git fetch failed; cannot prove local source matches Git'

read -r AHEAD BEHIND < <(git rev-list --left-right --count "HEAD...@{upstream}")

if [[ "${AHEAD}" -ne 0 || "${BEHIND}" -ne 0 ]]; then
    printf '[INFO] Branch:   %s\n' "${BRANCH}" >&2
    printf '[INFO] Upstream: %s\n' "${UPSTREAM}" >&2
    printf '[INFO] Ahead:    %s\n' "${AHEAD}" >&2
    printf '[INFO] Behind:   %s\n' "${BEHIND}" >&2
    fail 'local source does not exactly match upstream; sync Git before testing'
fi

UPSTREAM_SHA="$(git rev-parse '@{upstream}')"
[[ "${HEAD_SHA}" == "${UPSTREAM_SHA}" ]] \
    || fail "HEAD ${HEAD_SHA} differs from upstream ${UPSTREAM_SHA}"

pass "branch ${BRANCH} exactly matches ${UPSTREAM}"

printf '\nGOAD KINGDOMS SOURCE GATE: READY\n'
printf 'Branch:   %s\n' "${BRANCH}"
printf 'Upstream: %s\n' "${UPSTREAM}"
printf 'HEAD:     %s\n' "${HEAD_SHA}"
