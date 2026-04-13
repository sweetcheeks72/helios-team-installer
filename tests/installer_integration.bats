#!/usr/bin/env bats
# installer_integration.bats — Live resource integration tests for installer core functions
# Tests run against REAL resources: Docker containers, filesystem, network.
# Tests skip gracefully when resources are unavailable (CI-friendly).

setup() {
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/platform.sh"
  export INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export LOG_FILE="${BATS_TMPDIR}/integration-test.log"
  export PI_AGENT_DIR="$HOME/.pi/agent"
}

# ── Memgraph Integration ──────────────────────────────────────────────────────

@test "Memgraph container is running and healthy" {
  command -v docker &>/dev/null || skip "Docker not available"
  docker info &>/dev/null || skip "Docker not running"
  local container
  container=$(docker ps --filter 'name=memgraph' --format '{{.Names}}' | head -1)
  [[ -n "$container" ]] || skip "No memgraph container"
  # Health: bolt responds
  echo 'RETURN 1;' | docker exec -i "$container" mgconsole --output-format csv 2>/dev/null | grep -q '1'
}

@test "Memgraph schema can be applied" {
  command -v docker &>/dev/null || skip "Docker not available"
  local container schema
  container=$(docker ps --filter 'name=memgraph' --format '{{.Names}}' | head -1)
  [[ -n "$container" ]] || skip "No memgraph container"
  schema="$PI_AGENT_DIR/extensions/memgraph-schema/schema.cypher"
  [[ -f "$schema" ]] || skip "Schema file not found"
  # Apply schema (idempotent — CREATE INDEX is safe to re-run)
  docker exec -i "$container" mgconsole < "$schema" 2>&1 | tail -5
  # Verify at least one index exists
  local idx_count
  idx_count=$(echo 'SHOW INDEX INFO;' | docker exec -i "$container" mgconsole --output-format csv 2>/dev/null | wc -l)
  [[ "$idx_count" -gt 10 ]]
}

@test "Memgraph new performance indices are in schema" {
  local schema="$PI_AGENT_DIR/extensions/memgraph-schema/schema.cypher"
  [[ -f "$schema" ]] || schema="$HOME/helios-agent/extensions/memgraph-schema/schema.cypher"
  [[ -f "$schema" ]] || skip "No schema file found"
  # Verify our new indices are present
  grep -q 'EpisodicMemory(memoryClass)' "$schema"
  grep -q 'CausalLesson(evidenceState)' "$schema"
  grep -q 'CodeFile(path)' "$schema"
  grep -q 'CodeFile(relativePath)' "$schema"
  grep -q 'SessionEpisode(updatedAt)' "$schema"
}

# ── Runtime Contract ──────────────────────────────────────────────────────────

@test "memgraph.env runtime contract is valid" {
  local contract="$PI_AGENT_DIR/runtime/memgraph.env"
  [[ -f "$contract" ]] || skip "No memgraph.env"
  # Must contain required keys
  grep -q 'MEMGRAPH_CONTAINER=' "$contract"
  grep -q 'MEMGRAPH_BOLT_URL=' "$contract"
}

@test "runtime contract bolt URL is reachable" {
  local contract="$PI_AGENT_DIR/runtime/memgraph.env"
  [[ -f "$contract" ]] || skip "No memgraph.env"
  source "$contract"
  [[ -n "${MEMGRAPH_BOLT_URL:-}" ]] || skip "No BOLT URL in contract"
  # Extract host:port and test connectivity
  local host port
  host=$(echo "$MEMGRAPH_BOLT_URL" | sed 's|bolt://||' | cut -d: -f1)
  port=$(echo "$MEMGRAPH_BOLT_URL" | sed 's|bolt://||' | cut -d: -f2)
  # Use node to test TCP connection
  node -e "const net=require('net');const c=new net.Socket();c.setTimeout(3000);c.on('connect',()=>{console.log('OK');c.destroy();process.exit(0)});c.on('error',()=>process.exit(1));c.on('timeout',()=>process.exit(1));c.connect($port,'$host')"
}

# ── Settings & Config ─────────────────────────────────────────────────────────

@test "settings.json exists and is valid JSON" {
  local settings="$PI_AGENT_DIR/settings.json"
  [[ -f "$settings" ]] || skip "No settings.json"
  python3 -c "import json; json.load(open('$settings'))"
}

@test "settings.json has required fields" {
  local settings="$PI_AGENT_DIR/settings.json"
  [[ -f "$settings" ]] || skip "No settings.json"
  python3 -c "
import json
with open('$settings') as f: d = json.load(f)
assert 'defaultProvider' in d, 'missing defaultProvider'
assert 'packages' in d, 'missing packages'
assert 'skills' in d, 'missing skills'
assert 'extensions' in d, 'missing extensions'
print('All required fields present')
"
}

@test "provider configs are all valid JSON" {
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    python3 -c "import json; json.load(open('$cfg'))" || return 1
  done
}

# ── Tarball Integrity ─────────────────────────────────────────────────────────

@test "dist tarball exists and sha256 matches" {
  local tarball="$INSTALLER_DIR/dist/helios-agent-latest.tar.gz"
  local sha_file="${tarball}.sha256"
  [[ -f "$tarball" ]] || skip "No tarball"
  [[ -f "$sha_file" ]] || skip "No sha256 file"
  local expected actual
  expected=$(cat "$sha_file" | awk '{print $1}')
  actual=$(shasum -a 256 "$tarball" | awk '{print $1}')
  [[ "$expected" == "$actual" ]]
}
