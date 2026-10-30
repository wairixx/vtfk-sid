#!/usr/bin/env bash
set -euo pipefail

BASE_IMAGE="ubuntu:24.04"
PUBLIC_BOX="capsule-web"
ISOLATED_BOX="capsule-local"

HOST_PORT=8080
SERVICE_PORT=80

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"

MISSION_NETWORK="mission-net"
MISSION_VOLUME="mission-logs"
AGENT_BOX="agent"
STORAGE_BOX="storage"
AGENT_IMAGE="camera-audit-slim"
STORAGE_IMAGE="python:3.12-slim"

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "Missing $SECRETS_FILE (copy secrets.env.example and set the key)." >&2
  exit 1
fi

remove_existing() {
  docker rm -f "$PUBLIC_BOX" "$ISOLATED_BOX" >/dev/null 2>&1 || true
}

install_main_packages() {
  docker exec "$PUBLIC_BOX" bash -c '
    apt-get update &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      python3 \
      curl \
      git \
      procps \
      iproute2
  '
}

start_web_server() {
  local container_name="$1"

  docker exec -d "$container_name" \
    python3 -m http.server "$SERVICE_PORT"
}

echo "[1/9] Cleaning previous containers..."
remove_existing

echo "[2/9] Creating container with published HTTP port..."
docker run -d \
  --name "$PUBLIC_BOX" \
  -p "${HOST_PORT}:${SERVICE_PORT}" \
  "$BASE_IMAGE" \
  sleep infinity >/dev/null

echo "[3/9] Installing development utilities..."
install_main_packages

echo "[4/9] Launching HTTP service..."
start_web_server "$PUBLIC_BOX"

echo "[5/9] Creating isolated container..."
docker run -d \
  --name "$ISOLATED_BOX" \
  "$BASE_IMAGE" \
  sleep infinity >/dev/null

docker exec "$ISOLATED_BOX" bash -c '
  apt-get update &&
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3
'

start_web_server "$ISOLATED_BOX"

echo "[6/9] Testing access without port publishing..."

# Release port 8080 on the host while the isolated container keeps running.
docker stop "$PUBLIC_BOX" >/dev/null

if curl -fsS --connect-timeout 2 "http://localhost:${HOST_PORT}/" >/dev/null 2>&1; then
  echo "Isolation test failed: host port is still reachable." >&2
  exit 1
else
  echo "Isolation test passed: unpublished container is not accessible."
fi

# Start the public container again and restore its HTTP service.
docker start "$PUBLIC_BOX" >/dev/null
start_web_server "$PUBLIC_BOX"

echo "[7/9] Waiting for published HTTP service..."

ready=false

for _ in $(seq 1 20); do
  if curl -fsS "http://localhost:${HOST_PORT}/" >/dev/null 2>&1; then
    ready=true
    break
  fi

  sleep 0.5
done

if [[ "$ready" != "true" ]]; then
  echo "HTTP service did not become ready." >&2
  exit 1
fi

echo
echo "Environment is ready."
echo "Published container : $PUBLIC_BOX"
echo "Isolated container  : $ISOLATED_BOX"

echo
echo "Docker port mapping:"
docker port "$PUBLIC_BOX"

echo
echo "Available utilities:"
docker exec "$PUBLIC_BOX" bash -c '
  curl --version | head -1
  git --version
  ps --version | head -1
  ip -Version
'

echo
echo "Final HTTP response:"
curl -I "http://localhost:${HOST_PORT}/"
echo
echo "[8/9] Creating mission network and shared volume..."
docker network inspect "$MISSION_NETWORK" >/dev/null 2>&1 \
  || docker network create --driver bridge "$MISSION_NETWORK" >/dev/null
docker volume inspect "$MISSION_VOLUME" >/dev/null 2>&1 \
  || docker volume create "$MISSION_VOLUME" >/dev/null

echo "[9/9] Starting storage and agent..."
docker rm -f "$AGENT_BOX" "$STORAGE_BOX" >/dev/null 2>&1 || true
docker build -q -f "$SCRIPT_DIR/Dockerfile.slim" -t "$AGENT_IMAGE" "$SCRIPT_DIR" >/dev/null

# storage serves the shared volume over HTTP (variant N % 4 == 0).
docker run -d \
  --name "$STORAGE_BOX" \
  --network "$MISSION_NETWORK" \
  -v "$MISSION_VOLUME:/data" \
  "$STORAGE_IMAGE" \
  python3 -m http.server 8000 --directory /data >/dev/null

# The capsule entrypoint exits at once, so keep the agent alive with sleep.
docker run -d \
  --name "$AGENT_BOX" \
  --network "$MISSION_NETWORK" \
  -v "$MISSION_VOLUME:/data" \
  --env-file "$SECRETS_FILE" \
  --entrypoint sleep \
  "$AGENT_IMAGE" \
  infinity >/dev/null

echo "Mission containers are running on $MISSION_NETWORK."
