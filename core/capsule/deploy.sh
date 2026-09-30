#!/usr/bin/env bash
set -euo pipefail

BASE_IMAGE="ubuntu:24.04"
PUBLIC_BOX="capsule-web"
ISOLATED_BOX="capsule-local"

HOST_PORT=8080
SERVICE_PORT=80

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

echo "[1/7] Cleaning previous containers..."
remove_existing

echo "[2/7] Creating container with published HTTP port..."
docker run -d \
  --name "$PUBLIC_BOX" \
  -p "${HOST_PORT}:${SERVICE_PORT}" \
  "$BASE_IMAGE" \
  sleep infinity >/dev/null

echo "[3/7] Installing development utilities..."
install_main_packages

echo "[4/7] Launching HTTP service..."
start_web_server "$PUBLIC_BOX"

echo "[5/7] Creating isolated container..."
docker run -d \
  --name "$ISOLATED_BOX" \
  "$BASE_IMAGE" \
  sleep infinity >/dev/null

docker exec "$ISOLATED_BOX" bash -c '
  apt-get update &&
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3
'

start_web_server "$ISOLATED_BOX"

echo "[6/7] Testing access without port publishing..."

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

echo "[7/7] Waiting for published HTTP service..."

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