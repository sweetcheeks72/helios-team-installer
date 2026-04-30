#!/usr/bin/env bats
# tests/npm_recovery.bats — Test npm cache recovery logic
#
# Tests that the installer handles npm cache corruption gracefully.

INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # Create temp dir for test
  TEST_DIR="$(mktemp -d)"
  
  # Create minimal package.json
  cat > "$TEST_DIR/package.json" << 'EOF'
{
  "name": "npm-recovery-test",
  "version": "1.0.0",
  "private": true,
  "dependencies": {}
}
EOF

  # Source installer functions
  # We need to source just the helper functions, not run the installer
  export PI_AGENT_DIR="$TEST_DIR"
  export INSTALL_WARNINGS=()
  export INSTALL_LOG="/dev/null"
}

teardown() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

@test "npm_install_with_recovery function exists in install.sh" {
  grep -q 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh"
}

@test "install_agent_deps uses npm_install_with_recovery" {
  grep -A50 'install_agent_deps' "$INSTALLER_DIR/install.sh" | grep -q 'npm_install_with_recovery'
}

@test "npm cache repair includes chown logic" {
  grep -A30 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep -q 'chown'
}

@test "npm cache dir detection uses npm config" {
  # Verify that the function detects cache dir using npm config get cache
  grep -A20 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep -q 'npm config get cache'
}

@test "npm cache ownership check uses \$npm_cache_dir variable" {
  # Verify that we use the detected cache dir, not hardcoded $HOME/.npm
  local line
  line=$(grep -A25 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep 'if \[\[ -d' | head -1)
  echo "$line" | grep -q '\$npm_cache_dir'
}

@test "npm cache repair includes cache clean" {
  grep -A35 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep -q 'npm cache clean'
}

@test "npm cache repair includes cache verify" {
  grep -A35 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep -q 'npm cache verify'
}

@test "build-release.sh has cache pre-flight" {
  grep -q 'npm cache verify' "$INSTALLER_DIR/build-release.sh"
}

@test "peer deps section uses npm_install_with_recovery" {
  # Find the peer deps section and verify it uses the recovery function
  grep -B2 -A5 'peer dep' "$INSTALLER_DIR/install.sh" | grep -q 'npm_install_with_recovery'
}

@test "fallback npm install has retry logic" {
  # The install_agent_deps function should NOT have bare run_with_spinner for npm install
  # (it should use npm_install_with_recovery instead)
  local bare_spinner_count
  bare_spinner_count=$(sed -n '/^install_agent_deps/,/^}/p' "$INSTALLER_DIR/install.sh" | \
    grep 'run_with_spinner.*npm install' | grep -v 'rebuild\|Rebuild' | wc -l)
  # Should be 0 — all npm install calls should go through npm_install_with_recovery
  [ "$bare_spinner_count" -eq 0 ]
}

# ─── Behavioral Tests (actually call the function) ───────────────────────────

# Helper: source install.sh functions without running the installer
source_installer_functions() {
  # Extract just the npm_install_with_recovery function and its dependencies
  # We need: warn, info, error, success, run_with_spinner helpers
  
  # Stub out the UI helpers for testing
  warn() { echo "WARN: $*" >&2; }
  info() { echo "INFO: $*"; }
  error() { echo "ERROR: $*" >&2; }
  success() { echo "OK: $*"; }
  
  # Stub run_with_spinner to just run the command
  run_with_spinner() {
    local msg="$1"; shift
    echo "[spinner] $msg"
    "$@"
  }
  
  # Source the actual npm_install_with_recovery function
  eval "$(sed -n '/^npm_install_with_recovery() {/,/^}/p' "$INSTALLER_DIR/install.sh")"
}

@test "behavioral: npm_install_with_recovery succeeds on valid package.json" {
  source_installer_functions
  
  # Should succeed on first attempt (no recovery needed)
  run npm_install_with_recovery "$TEST_DIR" "test install"
  [ "$status" -eq 0 ]
}

@test "behavioral: npm_install_with_recovery bails out when chown fails and cache is not owned" {
  source_installer_functions
  
  # Create a fake npm cache dir owned by a different user (simulate the problem)
  local fake_cache="$TEST_DIR/fake-npm-cache"
  mkdir -p "$fake_cache"
  
  # Override npm config get cache to return our fake cache
  npm() {
    if [[ "$1" == "config" && "$2" == "get" && "$3" == "cache" ]]; then
      echo "$fake_cache"
    elif [[ "$1" == "cache" ]]; then
      # Stub out cache clean/verify
      return 0
    else
      command npm "$@"
    fi
  }
  export -f npm
  
  # Override chown to always fail (simulating permission denied)
  chown() {
    return 1
  }
  export -f chown
  
  # Override stat to return a different owner
  stat() {
    if [[ "$1" == "-f" || "$1" == "-c" ]]; then
      echo "root"  # Different user
    else
      command stat "$@"
    fi
  }
  export -f stat
  
  # Create a package.json that will fail npm install on first try
  cat > "$TEST_DIR/package.json" << 'EOF'
{
  "name": "fail-test",
  "version": "1.0.0",
  "dependencies": {
    "nonexistent-package-12345": "*"
  }
}
EOF
  
  # Should fail and bail out with return 1 after chown fails
  run npm_install_with_recovery "$TEST_DIR" "test install"
  [ "$status" -eq 1 ]
  
  # Should contain error message about running sudo chown
  echo "$output" | grep -q "sudo chown"
}
