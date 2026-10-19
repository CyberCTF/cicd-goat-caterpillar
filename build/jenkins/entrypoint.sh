#!/bin/bash
# Wonderland Jenkins entrypoint. Stages the per-player flag into a root-only directory ($SECRETS),
# where the init-groovy hook reads it and loads it into the `flag2` credential — WITHOUT the flag ever
# being an image layer, a spec value or a process environment variable (a pipeline must bind the
# credential to read it, which is the whole point of the challenge).
#
# Isoloom mounts the per-player input as a read-only file at /run/lab/secrets/flag2. When it is empty
# (an offline start — local, CI) the inert development placeholder is staged instead, so the lab still
# comes up and is solvable.
set -eu

DEV='cat-dev-flag-not-a-real-secret-0000'
SRC_FLAG='/run/lab/secrets/flag2'
SECRETS_DIR="${SECRETS:-/run/lab/casc_secrets}"

mkdir -p "$SECRETS_DIR"
if [ -s "$SRC_FLAG" ]; then
  tr -d '\r\n' < "$SRC_FLAG" > "$SECRETS_DIR/flag2"
else
  printf '%s' "$DEV" > "$SECRETS_DIR/flag2"
fi
chmod 0400 "$SECRETS_DIR/flag2"

exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
