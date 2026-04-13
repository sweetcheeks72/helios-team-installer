#!/usr/bin/env bats
# tests/memgraph_arch.bats — Architecture-aware Memgraph container tests
#
# Verifies that:
#  1. docker_platform() returns the correct platform for the host arch
#  2. setup_memgraph() propagates DOCKER_DEFAULT_PLATFORM to docker compose
#  3. The Memgraph docker-compose.yml declares a platform directive
#  4. A running Memgraph container (if present) matches the host architecture
#  5. The Memgraph Bolt port responds when a container is running

INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  source "$INSTALLER_DIR/lib/platform.sh"
}

# ---------------------------------------------------------------------------
# 1. docker_platform() returns the right platform string for this machine
# ---------------------------------------------------------------------------
@test "docker_platform returns linux/arm64 on arm64 host" {
  [[ "$(uname -m)" == "arm64" ]] || skip "Not an arm64 host"
  run docker_platform
  [ "$status" -eq 0 ]
  [ "$output" = "linux/arm64" ]
}

@test "docker_platform returns linux/amd64 on x86_64 host" {
  [[ "$(uname -m)" == "x86_64" ]] || skip "Not an x86_64 host"
  run docker_platform
  [ "$status" -eq 0 ]
  [ "$output" = "linux/amd64" ]
}

@test "docker_platform output matches expected pattern" {
  run docker_platform
  [ "$status" -eq 0 ]
  [[ "$output" == linux/* ]]
}

# ---------------------------------------------------------------------------
# 2. setup_memgraph() passes DOCKER_DEFAULT_PLATFORM to docker compose
# ---------------------------------------------------------------------------
@test "setup_memgraph sets DOCKER_DEFAULT_PLATFORM before compose up" {
  # Verify the installer sources docker_platform and exports the platform var
  # when calling compose — grep the setup_memgraph body for the pattern.
  local fn_body
  fn_body=$(sed -n '/^setup_memgraph()/,/^}/p' "$INSTALLER_DIR/install.sh")

  # Must set DOCKER_DEFAULT_PLATFORM (env var for compose platform substitution)
  echo "$fn_body" | grep -q 'DOCKER_DEFAULT_PLATFORM'
}

@test "setup_memgraph references docker_platform function" {
  local fn_body
  fn_body=$(sed -n '/^setup_memgraph()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$fn_body" | grep -q 'docker_platform'
}

# ---------------------------------------------------------------------------
# 3. Memgraph docker-compose.yml declares a platform directive
# ---------------------------------------------------------------------------
@test "memgraph compose file declares platform directive" {
  local compose_file="$HOME/.pi/agent/proxies/memgraph/docker-compose.yml"
  [[ -f "$compose_file" ]] || skip "Compose file not found at $compose_file"
  grep -q 'platform:' "$compose_file"
}

@test "memgraph compose platform uses DOCKER_DEFAULT_PLATFORM variable" {
  local compose_file="$HOME/.pi/agent/proxies/memgraph/docker-compose.yml"
  [[ -f "$compose_file" ]] || skip "Compose file not found at $compose_file"
  grep 'platform:' "$compose_file" | grep -q 'DOCKER_DEFAULT_PLATFORM'
}

# ---------------------------------------------------------------------------
# 4. Running Memgraph container arch matches the host (live check)
# ---------------------------------------------------------------------------
@test "Memgraph container health check works on current arch" {
  command -v docker &>/dev/null || skip "Docker not available"
  docker info &>/dev/null 2>&1 || skip "Docker daemon not running"

  local running
  running=$(docker ps --filter 'name=memgraph' --format '{{.Names}}' 2>/dev/null | head -1)
  [[ -n "$running" ]] || skip "No memgraph container running"

  local container_arch
  container_arch=$(docker inspect "$running" --format '{{.Architecture}}' 2>/dev/null) || container_arch=""

  # OrbStack does not populate the Architecture field — containers run natively.
  # Treat an empty field as architecture-correct (OrbStack handles it transparently).
  if [[ -z "$container_arch" ]]; then
    skip "Container Architecture field is empty (OrbStack native mode — arch is host-native)"
  fi

  local expected
  expected=$(current_arch)

  # arm64 containers may report as "aarch64" on some OCI runtimes
  [[ "$container_arch" == "$expected" ]] \
    || [[ "$container_arch" == "aarch64" && "$expected" == "arm64" ]]
}

# ---------------------------------------------------------------------------
# 5. Bolt port responds when container is running
# ---------------------------------------------------------------------------
@test "Memgraph bolt port responds on current arch" {
  command -v docker &>/dev/null || skip "Docker not available"
  docker info &>/dev/null 2>&1 || skip "Docker daemon not running"

  local running
  running=$(docker ps --filter 'name=memgraph' --format '{{.Names}}' 2>/dev/null | head -1)
  [[ -n "$running" ]] || skip "No memgraph container running"

  local result
  result=$(echo 'RETURN 1 AS ok;' \
    | docker exec -i "$running" mgconsole \
        --username "${MEMGRAPH_USER:-memgraph}" \
        --password "${MEMGRAPH_PASSWORD:-memgraph}" \
        --output-format csv 2>/dev/null | tail -1)
  [[ "$result" == *"1"* ]]
}
