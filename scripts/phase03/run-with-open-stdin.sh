#!/usr/bin/env bash
# Keep stdin open for a detached long-running command without requiring a TTY.
set -euo pipefail

[[ "$#" -ge 2 ]] || {
    echo "usage: $0 <fifo-path> <command> [args...]" >&2
    exit 2
}

FIFO="$1"
shift

rm -f -- "$FIFO"
mkfifo -m 600 "$FIFO"

# On Linux a FIFO may be opened read/write by one process.
# Keeping this descriptor open prevents stdin from reaching EOF.
exec 3<>"$FIFO"

# The descriptor remains valid after unlinking, so no filesystem artifact
# needs to survive for the lifetime of the relay.
rm -f -- "$FIFO"

exec "$@" <&3
