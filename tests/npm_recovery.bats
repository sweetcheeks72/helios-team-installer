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
  grep -A20 'npm_install_with_recovery()' "$INSTALLER_DIR/install.sh" | grep -q 'chown'
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
