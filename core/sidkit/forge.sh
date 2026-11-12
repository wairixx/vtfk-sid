#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MISSION_VOLUME="mission-logs"
SIDKIT_IMAGE="sidkit"
BASE_IMAGE="debian:12-slim"

# Seed for variant 0 (N = 12, 12 % 4 = 0).
SEED="techno-b7-alpha"

echo "[1/3] Preparing shared volume..."
docker volume inspect "$MISSION_VOLUME" >/dev/null 2>&1 || docker volume create "$MISSION_VOLUME" >/dev/null

# Write the seed only once, so a seed already placed in the volume is kept.
docker run --rm -v "$MISSION_VOLUME:/data" "$BASE_IMAGE" \
  sh -c "test -s /data/seed.txt || printf '%s\n' '$SEED' > /data/seed.txt"

echo "[2/3] Building sidkit image..."
docker build -q -t "$SIDKIT_IMAGE" "$SCRIPT_DIR" >/dev/null

echo "[3/3] Forging key into $MISSION_VOLUME..."
docker run --rm -v "$MISSION_VOLUME:/data" "$SIDKIT_IMAGE"
