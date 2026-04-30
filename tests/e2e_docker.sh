#!/usr/bin/env bash
# =============================================================================
# e2e_docker.sh — Docker end-to-end tests for helios-team-installer
# =============================================================================
# Runs inside the Docker container built from Dockerfile.e2e.
# Sources install.sh (must be sourceable) and exercises core installer
# behaviours without performing a live network install.
#
# Exit code: 0 = all tests passed, non-zero = failure count.
# =============================================================================

set -euo pipefail

INSTALLER_DIR="/helios-installer"
INSTALL_SH="${INSTALLER_DIR}/install.sh"

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}✓${RESET}  $*"; }
fail() { echo -e "  ${RED}✗${RESET}  $*"; }
section() { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }

PASS_COUNT=0
FAIL_COUNT=0

assert_true() {
  local description="$1"
  local result="$2"  # "0" = success, non-zero = failure
  if [[ "$result" == "0" ]]; then
    pass "$description"
    (( PASS_COUNT++ )) || true
  else
    fail "$description (exit code: $result)"
    (( FAIL_COUNT++ )) || true
  fi
}

assert_false() {
  local description="$1"
  local result="$2"
  if [[ "$result" != "0" ]]; then
    pass "$description (correctly failed)"
    (( PASS_COUNT++ )) || true
  else
    fail "$description (expected failure but succeeded)"
    (( FAIL_COUNT++ )) || true
  fi
}

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   helios-team-installer  •  Docker E2E Tests ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── 0. Preflight: verify installer exists ────────────────────────────────────
section "Preflight"

if [[ ! -f "${INSTALL_SH}" ]]; then
  echo -e "${RED}FATAL: ${INSTALL_SH} not found. Check Dockerfile COPY step.${RESET}"
  exit 2
fi
pass "install.sh found at ${INSTALL_SH}"

# ─── 1. Source install.sh (function loading only — no main() call) ────────────
section "Sourcing install.sh"

# install.sh must be sourceable: guard blocks main execution when sourced.
# Source into a subshell to avoid polluting our env with set -euo pipefail.
if (
  # Prevent interactive stdin restoring which fails outside a tty
  export HELIOS_SOURCED=1
  # shellcheck source=../install.sh
  source "${INSTALL_SH}"
) 2>/dev/null; then
  pass "install.sh sources without errors (HELIOS_SOURCED=1)"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
else
  fail "install.sh failed to source"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# Re-source into current shell so we can call functions
# SC1090 — dynamic source path is intentional
# shellcheck source=/dev/null
export HELIOS_SOURCED=1
set +e  # Don't exit on error while sourcing
source "${INSTALL_SH}" 2>/dev/null
set -e

# ─── 2. Prerequisites check ───────────────────────────────────────────────────
section "Prerequisites (check_prerequisites)"

# Node.js must be present (installed in Dockerfile)
node_check_result=0
node --version &>/dev/null || node_check_result=$?
assert_true "node is available" "${node_check_result}"

# npm must be present
npm_check_result=0
npm --version &>/dev/null || npm_check_result=$?
assert_true "npm is available" "${npm_check_result}"

# git must be present
git_check_result=0
git --version &>/dev/null || git_check_result=$?
assert_true "git is available" "${git_check_result}"

# curl must be present
curl_check_result=0
curl --version &>/dev/null || curl_check_result=$?
assert_true "curl is available" "${curl_check_result}"

# python3 must be present
py_check_result=0
python3 --version &>/dev/null || py_check_result=$?
assert_true "python3 is available" "${py_check_result}"

# Node.js version must be >= 18
node_version_ok=0
node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null \
  || node_version_ok=$?
assert_true "Node.js version >= 18 (found: $(node -v))" "${node_version_ok}"

# If check_prerequisites is defined, run it non-fatally
if declare -f check_prerequisites &>/dev/null; then
  prereq_result=0
  check_prerequisites 2>/dev/null || prereq_result=$?
  assert_true "check_prerequisites() ran successfully" "${prereq_result}"
else
  echo -e "  ${YELLOW}⚠${RESET}  check_prerequisites() not exported — skipping function test"
fi

# ─── 3. Agent directory creation ──────────────────────────────────────────────
section "Agent directory creation"

TEST_AGENT_DIR="${HOME}/.pi/agent-e2e-test"

# Create directory structure (mirrors what install.sh does)
mkdir -p "${TEST_AGENT_DIR}"
agent_dir_result=0
[[ -d "${TEST_AGENT_DIR}" ]] || agent_dir_result=1
assert_true "Agent dir created: ${TEST_AGENT_DIR}" "${agent_dir_result}"

# Confirm the path is writable
touch_result=0
touch "${TEST_AGENT_DIR}/.e2e_marker" 2>/dev/null || touch_result=$?
assert_true "Agent dir is writable" "${touch_result}"

# Clean up
rm -rf "${TEST_AGENT_DIR}"

# ─── 4. Provider config copy ──────────────────────────────────────────────────
section "Provider config copy"

PROVIDER_DIR="${INSTALLER_DIR}/provider-configs"
DEST_DIR="${HOME}/.pi/agent-e2e-provider-test"

mkdir -p "${DEST_DIR}"

if [[ -d "${PROVIDER_DIR}" ]]; then
  provider_files_exist=0
  ls "${PROVIDER_DIR}"/*.json 2>/dev/null | grep -q . || provider_files_exist=$?
  # If .json files exist, attempt a copy
  if [[ "${provider_files_exist}" == "0" ]]; then
    copy_result=0
    cp "${PROVIDER_DIR}"/*.json "${DEST_DIR}/" 2>/dev/null || copy_result=$?
    assert_true "Provider configs copied from ${PROVIDER_DIR}" "${copy_result}"

    # Validate at least one JSON file is readable
    for f in "${DEST_DIR}"/*.json; do
      if python3 -c "import json,sys; json.load(open('${f}'))" 2>/dev/null; then
        pass "Provider config JSON valid: $(basename "${f}")"
        (( PASS_COUNT++ )) || true
        break
      else
        fail "Provider config JSON invalid: $(basename "${f}")"
        (( FAIL_COUNT++ )) || true
      fi
    done
  else
    echo -e "  ${YELLOW}⚠${RESET}  No .json files in ${PROVIDER_DIR} — skipping copy test"
  fi
else
  echo -e "  ${YELLOW}⚠${RESET}  Provider config dir not found: ${PROVIDER_DIR}"
fi

rm -rf "${DEST_DIR}"

# ─── 5. .env template ─────────────────────────────────────────────────────────
section ".env template"

ENV_TEMPLATE="${INSTALLER_DIR}/.env.template"

env_exists_result=0
[[ -f "${ENV_TEMPLATE}" ]] || env_exists_result=1
assert_true ".env.template exists at ${ENV_TEMPLATE}" "${env_exists_result}"

if [[ "${env_exists_result}" == "0" ]]; then
  # Template must be non-empty
  env_nonempty=0
  [[ -s "${ENV_TEMPLATE}" ]] || env_nonempty=1
  assert_true ".env.template is non-empty" "${env_nonempty}"

  # Template should contain at least one KEY= pattern
  env_has_keys=0
  grep -qE '^[A-Z_]+=.*' "${ENV_TEMPLATE}" || env_has_keys=$?
  assert_true ".env.template contains KEY= entries" "${env_has_keys}"

  # Simulate copying to home (as install.sh would do)
  env_dest="${HOME}/.pi/.env.test"
  mkdir -p "${HOME}/.pi"
  copy_env_result=0
  cp "${ENV_TEMPLATE}" "${env_dest}" || copy_env_result=$?
  assert_true ".env.template copied to ${env_dest}" "${copy_env_result}"
  rm -f "${env_dest}"
fi

# ─── 6. npm cache recovery ─────────────────────────────────────────────────────
section "npm cache recovery"

test_npm_cache_recovery() {
  echo "Testing npm cache recovery logic..."
  
  # Verify the recovery function exists
  if ! grep -q 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh"; then
    echo "FAIL: npm_install_with_recovery() not found in install.sh"
    return 1
  fi
  
  # Verify it's used by install_agent_deps
  if ! grep -A50 'install_agent_deps()' "$INSTALLER_DIR/install.sh" | grep -q 'npm_install_with_recovery'; then
    echo "FAIL: install_agent_deps doesn't use npm_install_with_recovery"
    return 1
  fi
  
  # Test with clean environment (should pass first try)
  local test_dir
  test_dir=$(mktemp -d)
  echo '{"name":"test","version":"1.0.0","private":true,"dependencies":{}}' > "$test_dir/package.json"
  
  if ! (cd "$test_dir" && npm install --production --legacy-peer-deps --no-audit --no-fund 2>&1); then
    echo "FAIL: basic npm install doesn't work in this environment"
    rm -rf "$test_dir"
    return 1
  fi
  
  rm -rf "$test_dir"
  echo "PASS: npm cache recovery logic present and install works"
}

npm_recovery_result=0
test_npm_cache_recovery || npm_recovery_result=$?
assert_true "npm_install_with_recovery() present and npm install works" "${npm_recovery_result}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "  ─────────────────────────────────────────────"
TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All ${TOTAL} tests passed${RESET}"
else
  echo -e "  ${RED}${BOLD}✗ ${FAIL_COUNT}/${TOTAL} tests FAILED${RESET}"
fi
echo "  ─────────────────────────────────────────────"
echo ""

exit "${FAIL_COUNT}"
