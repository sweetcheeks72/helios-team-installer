#!/usr/bin/env bats
# =============================================================================
# tarball_audit.bats — Audit tests for helios-agent-latest.tar.gz
#
# Verifies that build-release.sh correctly excludes user data and includes
# required structural files.
#
# Usage:
#   bats tests/tarball_audit.bats
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
TARBALL="${SCRIPT_DIR}/../dist/helios-agent-latest.tar.gz"
CHECKSUM_FILE="${SCRIPT_DIR}/../dist/helios-agent-latest.tar.gz.sha256"

setup() {
  # Skip all tests if the tarball does not exist yet
  if [[ ! -f "${TARBALL}" ]]; then
    skip "Tarball not found at ${TARBALL} — run build-release.sh first"
  fi
}

# ---------------------------------------------------------------------------
# Files that MUST NOT appear in the tarball (user data / secrets)
# ---------------------------------------------------------------------------

@test "tarball excludes auth.json" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'auth\.json'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes .env files" {
  run bash -c "tar -tzf '${TARBALL}' | grep -qE '(^|/)\.env($|/)'"
  [ "$status" -ne 0 ]
}

@test "tarball contains generated settings.json" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'settings\.json'"
  [ "$status" -eq 0 ]
}

@test "tarball excludes run-history.jsonl" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'run-history\.jsonl'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes .helios/ directory" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q '\.helios/'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes mcp-cache.json" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'mcp-cache\.json'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes sessions/ directory" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'sessions/'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes governance/events.jsonl" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'governance/events\.jsonl'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes provider-health-history.jsonl" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'provider-health-history\.jsonl'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes pi-messenger.json" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'pi-messenger\.json'"
  [ "$status" -ne 0 ]
}

@test "tarball excludes .disabled files" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q '\.disabled'"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Files that MUST appear in the tarball (structural / required)
# ---------------------------------------------------------------------------

@test "tarball contains VERSION file" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'VERSION'"
  [ "$status" -eq 0 ]
}

@test "tarball contains agents/ directory" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'agents/'"
  [ "$status" -eq 0 ]
}

@test "tarball contains skills/ directory" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'skills/'"
  [ "$status" -eq 0 ]
}

@test "tarball contains extensions/ directory" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'extensions/'"
  [ "$status" -eq 0 ]
}

@test "tarball contains bin/helios" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'bin/helios'"
  [ "$status" -eq 0 ]
}

@test "tarball contains governance/credibility.json" {
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'governance/credibility\.json'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# SHA256 checksum integrity
# ---------------------------------------------------------------------------

@test "tarball SHA256 checksum matches .sha256 file" {
  # Skip if checksum file is missing
  if [[ ! -f "${CHECKSUM_FILE}" ]]; then
    skip "Checksum file not found: ${CHECKSUM_FILE}"
  fi

  # Compute actual checksum of the tarball
  if command -v sha256sum &>/dev/null; then
    ACTUAL_CHECKSUM="$(sha256sum "${TARBALL}" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    ACTUAL_CHECKSUM="$(shasum -a 256 "${TARBALL}" | awk '{print $1}')"
  else
    skip "No sha256sum or shasum available on this system"
  fi

  # Extract expected checksum from the .sha256 file (first token on first line)
  EXPECTED_CHECKSUM="$(awk '{print $1}' "${CHECKSUM_FILE}")"

  run bash -c "[[ '${ACTUAL_CHECKSUM}' == '${EXPECTED_CHECKSUM}' ]]"
  [ "$status" -eq 0 ]
}
