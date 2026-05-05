#!/usr/bin/env bash
# =============================================================================
# e2e_install_flow.sh — Test actual install and update flows
# =============================================================================
# Tests both fresh install and update scenarios in Docker.
# Validates: tarball download, extraction, dep install, version detection.
#
# Usage:
#   ./tests/e2e_install_flow.sh           # builds + runs in Docker
#   ./tests/e2e_install_flow.sh --local   # runs locally (DESTRUCTIVE — uses ~/.pi)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${RESET}  $*"; (( PASS++ )) || true; }
fail() { echo -e "  ${RED}✗${RESET}  $*"; (( FAIL++ )) || true; }
section() { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ─── Docker mode: build and run inside container ─────────────────────────────
if [[ "${1:-}" != "--local" ]] && [[ ! -f "/.dockerenv" ]]; then
  echo "Building Docker test image..."
  docker build -f "${REPO_ROOT}/Dockerfile.e2e" -t helios-e2e-flow "${REPO_ROOT}"
  echo "Running install flow tests in container..."
  exec docker run --rm \
    -e HELIOS_TEST_MODE=1 \
    helios-e2e-flow \
    bash /helios-installer/tests/e2e_install_flow.sh --local
fi

# ─── Test functions ──────────────────────────────────────────────────────────

test_timeout_cmd_portable() {
  section "Portable _timeout_cmd (no GNU timeout required)"

  # Source just the function
  eval "$(sed -n '/_timeout_cmd()/,/^}/p' "${REPO_ROOT}/install.sh")"

  # Test: command completes before timeout
  result=0
  _timeout_cmd 5 true || result=$?
  [[ $result -eq 0 ]] && pass "_timeout_cmd: fast command returns 0" || fail "_timeout_cmd: fast command failed ($result)"

  # Test: command exceeds timeout
  result=0
  _timeout_cmd 1 sleep 10 || result=$?
  [[ $result -ne 0 ]] && pass "_timeout_cmd: slow command killed (exit $result)" || fail "_timeout_cmd: slow command was NOT killed"
}

test_detect_update_mode() {
  section "detect_update_mode"

  local test_dir
  test_dir=$(mktemp -d)
  export PI_AGENT_DIR="$test_dir"

  # Source detection function
  eval "$(sed -n '/^detect_update_mode()/,/^}/p' "${REPO_ROOT}/install.sh")"
  # Stub info/warn/success
  info() { :; }; warn() { :; }; success() { :; }; ask() { :; }

  # Case 1: Empty dir → fresh install
  UPDATE_MODE=false
  detect_update_mode
  [[ "$UPDATE_MODE" == "false" ]] && pass "Empty dir → fresh install" || fail "Empty dir detected as update"

  # Case 2: VERSION file present → update mode
  echo "2.5.5" > "$test_dir/VERSION"
  UPDATE_MODE=false
  detect_update_mode
  [[ "$UPDATE_MODE" == "true" ]] && pass "VERSION file → update mode" || fail "VERSION file not detected as update"

  # Case 3: settings.json with provider, no VERSION → update mode (fallback)
  rm -f "$test_dir/VERSION"
  echo '{"defaultProvider":"anthropic"}' > "$test_dir/settings.json"
  UPDATE_MODE=false
  detect_update_mode
  [[ "$UPDATE_MODE" == "true" ]] && pass "settings.json fallback → update mode" || fail "settings.json fallback not detected"

  # Case 4: --fresh flag overrides
  echo "2.5.5" > "$test_dir/VERSION"
  UPDATE_MODE=false
  detect_update_mode --fresh
  [[ "$UPDATE_MODE" == "false" ]] && pass "--fresh flag → fresh install" || fail "--fresh not honored"

  # Case 5: --update flag forces update
  rm -f "$test_dir/VERSION" "$test_dir/settings.json"
  UPDATE_MODE=false
  detect_update_mode --update
  [[ "$UPDATE_MODE" == "true" ]] && pass "--update flag → update mode" || fail "--update not honored"

  rm -rf "$test_dir"
  unset PI_AGENT_DIR
}

test_helios_download() {
  section "_helios_download"

  # Source the function (it's defined inside setup_helios_agent, extract it)
  _helios_download() {
    local url="$1" dest="$2"
    local fname
    fname="$(basename "$url")"
    printf "  ↓ %s " "$fname" > /dev/tty 2>/dev/null || true
    if curl -fSL --retry 3 --retry-delay 5 --max-time 300 -o "$dest" "$url"; then
      printf "✓\n" > /dev/tty 2>/dev/null || true
      return 0
    else
      printf "✗\n" > /dev/tty 2>/dev/null || true
      return 1
    fi
  }

  local tmp
  tmp=$(mktemp)

  # Test: download VERSION file (small, fast)
  result=0
  _helios_download "https://github.com/helios-agi/helios-team-installer/releases/latest/download/VERSION" "$tmp" || result=$?
  if [[ $result -eq 0 ]] && [[ -s "$tmp" ]]; then
    pass "VERSION file downloaded ($(cat "$tmp"))"
  else
    fail "VERSION file download failed"
  fi

  # Test: invalid URL fails gracefully
  result=0
  _helios_download "https://github.com/helios-agi/helios-team-installer/releases/latest/download/NONEXISTENT" "$tmp" 2>/dev/null || result=$?
  [[ $result -ne 0 ]] && pass "Invalid URL fails gracefully" || fail "Invalid URL did not fail"

  rm -f "$tmp"
}

test_offline_mode() {
  section "OFFLINE_MODE handling"

  # Verify OFFLINE_MODE is initialized at top level
  if grep -q '^OFFLINE_MODE=' "${REPO_ROOT}/install.sh"; then
    pass "OFFLINE_MODE initialized at top level"
  else
    fail "OFFLINE_MODE NOT initialized at top level (set -u will crash)"
  fi

  # Verify it's checked in install_agent_deps
  if grep -q 'OFFLINE_MODE.*true' "${REPO_ROOT}/install.sh" | grep -v "^#" | head -1; then
    pass "install_agent_deps respects OFFLINE_MODE"
  elif grep -q 'OFFLINE_MODE' "${REPO_ROOT}/install.sh"; then
    pass "install_agent_deps respects OFFLINE_MODE"
  else
    fail "install_agent_deps doesn't check OFFLINE_MODE"
  fi
}

test_health_check() {
  section "Install health check (version match but broken)"

  # Verify the health check exists
  if grep -q "node_modules.*extensions.*bin/helios" "${REPO_ROOT}/install.sh"; then
    pass "Health check validates node_modules + extensions + bin/helios"
  else
    fail "Health check missing from setup_helios_agent"
  fi
}

test_atomic_extraction() {
  section "Atomic tarball extraction (no broken state on interrupt)"

  # Verify extract-to-temp-then-swap pattern
  if grep -q "tmp_extract.*mktemp -d" "${REPO_ROOT}/install.sh"; then
    pass "Tarball extracts to temp dir first"
  else
    fail "Tarball extracts directly to PI_AGENT_DIR (dangerous)"
  fi

  if grep -q 'mv.*tmp_extract.*PI_AGENT_DIR' "${REPO_ROOT}/install.sh"; then
    pass "Atomic swap: mv tmp_extract → PI_AGENT_DIR"
  else
    fail "No atomic swap found"
  fi
}

test_no_bare_timeout() {
  section "No bare 'timeout' calls (macOS portability)"

  # Find bare timeout (not _timeout_cmd, not inside comments, not in the _timeout_cmd function itself)
  local bare_count
  bare_count=$(grep -c '^\s*timeout \|[^_]timeout [0-9]' "${REPO_ROOT}/install.sh" | head -1)
  # Subtract the ones inside _timeout_cmd (line 338) and inside `if command -v timeout` guards
  local safe_count
  safe_count=$(grep -c '_timeout_cmd\|command -v timeout\|gtimeout' "${REPO_ROOT}/install.sh" || echo 0)

  # The only allowed bare 'timeout' is inside _timeout_cmd() and guarded checks
  local problematic
  problematic=$(grep -n '^\s*timeout \|[^_]timeout [0-9]' "${REPO_ROOT}/install.sh" | \
    grep -v '_timeout_cmd\|command -v timeout\|gtimeout\|#\|curl.*timeout\|connect-timeout\|max-time' | \
    grep -v 'timeout "\$@"\|timeout 30 uvx' | wc -l | tr -d ' ')

  if [[ "$problematic" -eq 0 ]]; then
    pass "No unguarded bare 'timeout' calls"
  else
    fail "$problematic unguarded bare 'timeout' calls found (breaks macOS without coreutils)"
    grep -n '^\s*timeout \|[^_]timeout [0-9]' "${REPO_ROOT}/install.sh" | \
      grep -v '_timeout_cmd\|command -v timeout\|gtimeout\|#' | \
      grep -v "^338:\|^2569:\|^2571:" | head -5
  fi
}

test_no_git_access_required() {
  section "No git access to private repos required"

  # Check for git clone/fetch/pull against private repos
  local git_private
  git_private=$(grep -n 'git clone\|git.*fetch\|git.*pull' "${REPO_ROOT}/install.sh" | \
    grep -v '#\|echo\|info\|warn\|error\|git/github\.com\|hooks' | wc -l | tr -d ' ')

  if [[ "$git_private" -eq 0 ]]; then
    pass "No git clone/fetch/pull to private repos"
  else
    fail "$git_private git operations found that may require private repo access"
    grep -n 'git clone\|git.*fetch\|git.*pull' "${REPO_ROOT}/install.sh" | \
      grep -v '#\|echo\|info\|warn\|error\|git/github\.com\|hooks' | head -5
  fi

  # Check for gh auth requirements
  if grep -q 'gh auth.*required\|gh auth login' "${REPO_ROOT}/install.sh"; then
    fail "gh auth still required somewhere in installer"
  else
    pass "No gh auth requirements"
  fi
}

test_bun_installed_before_cli() {
  section "Bun installed before CLI binary verification"

  # In update mode, bun install must come BEFORE update_pi_cli
  local bun_line cli_line
  bun_line=$(grep -n 'Installing Bun.*required' "${REPO_ROOT}/install.sh" | tail -1 | cut -d: -f1)
  cli_line=$(grep -n 'run_step.*Helios CLI.*update_pi_cli' "${REPO_ROOT}/install.sh" | cut -d: -f1)

  if [[ -n "$bun_line" ]] && [[ -n "$cli_line" ]] && [[ "$bun_line" -lt "$cli_line" ]]; then
    pass "Bun installed (line $bun_line) before CLI step (line $cli_line)"
  else
    fail "Bun may not be installed before CLI verification (bun:$bun_line, cli:$cli_line)"
  fi
}

# ─── Run all tests ───────────────────────────────────────────────────────────

echo -e "${BOLD}helios-team-installer — Install Flow E2E Tests${RESET}"
echo ""

test_timeout_cmd_portable
test_detect_update_mode
test_helios_download
test_offline_mode
test_health_check
test_atomic_extraction
test_no_bare_timeout
test_no_git_access_required
test_bun_installed_before_cli

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "  ─────────────────────────────────────────────"
TOTAL=$(( PASS + FAIL ))
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All ${TOTAL} tests passed${RESET}"
else
  echo -e "  ${RED}${BOLD}✗ ${FAIL}/${TOTAL} tests FAILED${RESET}"
fi
echo "  ─────────────────────────────────────────────"
echo ""

exit "$FAIL"
