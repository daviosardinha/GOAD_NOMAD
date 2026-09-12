#!/usr/bin/env bash
# Operator prerequisites only; never run on a Windows lab host.
set -Eeuo pipefail
readonly KERBRUTE_COMMIT=9dad6e171abdc7491f587c793aa05411264a3393 # upstream v1.0.3 (peeled commit)
readonly DEST="${HOME}/.local/bin/kerbrute"
readonly RECEIPT="${HOME}/.local/share/kingdoms/kerbrute.sha256"

if [[ "${1:-}" == --install-prerequisites ]]; then
    command -v apt-get >/dev/null || { echo 'Automatic prerequisites require Debian/Kali.' >&2; exit 1; }
    sudo apt-get update
    sudo apt-get install -y ca-certificates git golang-go python3 smbclient ldap-utils curl nmap
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--install-prerequisites]" >&2
    exit 2
fi

for tool in git go python3 smbclient rpcclient ldapsearch curl nmap sha256sum timeout; do
    command -v "$tool" >/dev/null || {
        echo "Missing $tool. On Kali run: bash scripts/setup-phase01-tools.sh --install-prerequisites" >&2
        exit 1
    }
done

mkdir -p "$(dirname "$DEST")" "$(dirname "$RECEIPT")"
if [[ -x "$DEST" && -f "$RECEIPT" ]] &&
   [[ "$(head -n1 "$RECEIPT")" == "$KERBRUTE_COMMIT" ]] &&
   tail -n +2 "$RECEIPT" | sha256sum --check --status; then
    echo '[PASS] Pinned Kerbrute installation matches its build receipt.'
    exit 0
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
git -C "$BUILD_DIR" init -q
git -C "$BUILD_DIR" remote add origin https://github.com/ropnop/kerbrute.git
timeout 180 git -C "$BUILD_DIR" fetch --depth 1 origin "$KERBRUTE_COMMIT"
git -C "$BUILD_DIR" checkout --detach -q FETCH_HEAD
[[ "$(git -C "$BUILD_DIR" rev-parse HEAD)" == "$KERBRUTE_COMMIT" ]]
(
    cd "$BUILD_DIR"
    # go.sum verifies upstream's locked module dependencies; no @latest build.
    export CGO_ENABLED=0 GOTOOLCHAIN=local
    timeout 300 go mod download
    go mod verify
    timeout 300 go build -mod=readonly -trimpath -o kerbrute .
    git diff --exit-code -- go.mod go.sum
)
"$BUILD_DIR/kerbrute" userenum --help >/dev/null
install -m 0755 "$BUILD_DIR/kerbrute" "$DEST"
{ printf '%s\n' "$KERBRUTE_COMMIT"; sha256sum "$DEST"; } > "$RECEIPT"
echo "[PASS] Kerbrute v1.0.3 ($KERBRUTE_COMMIT) installed at $DEST"
echo 'The Phase 01 validator uses this binary directly; interactive shells need ~/.local/bin on PATH.'
