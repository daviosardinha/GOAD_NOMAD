#!/usr/bin/env bash
# Read-only compact summary of the newest RDP release-acceptance evidence set.
set -Eeuo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
BASE="${KINGDOMS_RDP_RELEASE_EVIDENCE_ROOT:-$HOME/Kingdoms-evidence}"

latest="$(
    find "$BASE" -maxdepth 1 -type d -name 'rdp-release-acceptance-*' -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -1 |
        cut -d' ' -f2-
)"

[[ -n "$latest" && -d "$latest" ]] || {
    echo 'FAIL: no RDP release-acceptance evidence directory found' >&2
    exit 1
}

cd "$ROOT"

echo '===== RDP RELEASE FAILURE SUMMARY ====='
echo "SOURCE_HEAD=$(git rev-parse --short=12 HEAD)"
echo "EVIDENCE_DIR=$latest"

echo
echo '===== HIGH-SIGNAL MARKERS ====='
grep -RhsE     'RDP_MATRIX=|RDP_DENIAL_EVENT=|RDP_DENIAL_CORRELATION|EXPECTED_DENIALS_|RDP_FRESH_|TOKEN_|RDP_DESKTOP_LOGON_MATRIX=|RDP_RELEASE_ACCEPTANCE_COMPLETE=|\[FAIL\]|fatal:|FAILED!'     "$latest" 2>/dev/null |
    tail -120 || true

echo
echo '===== FILES WITH FAILURE SIGNALS ====='
mapfile -t failed_files < <(
    grep -RIlE '\[FAIL\]|fatal:|FAILED!|did not produce|unexpectedly|missing|failed' "$latest" 2>/dev/null |
        sort
)

if [[ "${#failed_files[@]}" -eq 0 ]]; then
    echo 'NO_FAILURE_SIGNAL_FILE_FOUND=True'
else
    for file in "${failed_files[@]}"; do
        echo
        echo "--- $file ---"
        tail -80 "$file" || true
    done
fi

echo
echo 'RDP_RELEASE_EVIDENCE_SUMMARY_COMPLETE=True'
