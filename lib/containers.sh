#!/usr/bin/env bash
# lib/containers.sh — Container name resolution for helios installer
# Sourced by install.sh and verify.sh

# Resolve the running Memgraph container name.
# Priority: memgraph → familiar-graph-1 → compose label → empty string
# Usage: mg_name=$(resolve_memgraph_container)
resolve_memgraph_container() {
  local name
  # Check running containers first
  for name in memgraph familiar-graph-1; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${name}$"; then
      echo "$name"
      return 0
    fi
  done
  # Check stopped containers
  for name in memgraph familiar-graph-1; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "^${name}$"; then
      echo "$name"
      return 0
    fi
  done
  # Check compose labels
  local compose_name
  compose_name=$(docker ps -a --format '{{.Names}}\t{{.Labels}}' 2>/dev/null \
    | grep "com.docker.compose.service=memgraph" \
    | head -1 | cut -f1)
  if [[ -n "$compose_name" ]]; then
    echo "$compose_name"
    return 0
  fi
  # Default fallback
  echo "memgraph"
  return 1
}

# Check if any Memgraph container is running
is_memgraph_running() {
  local name
  name=$(resolve_memgraph_container)
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${name}$"
}
