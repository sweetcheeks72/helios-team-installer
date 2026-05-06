#!/usr/bin/env bats
# cto_audit_fixes.bats — Verifies every CTO-audit fix landed correctly
# Run: bats tests/cto_audit_fixes.bats

INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ---------------------------------------------------------------------------
# Error Recovery Fixes (lib/error-recovery.sh)
# ---------------------------------------------------------------------------

@test "C1: no dual heartbeat — heartbeat_pid removed" {
  ! grep -q 'heartbeat_pid' "$INSTALLER_DIR/lib/error-recovery.sh"
}

@test "C1: _hb_loop mechanism exists" {
  grep -q '_hb_loop' "$INSTALLER_DIR/lib/error-recovery.sh"
}

@test "C2: known-fix descriptions wrapped in echo" {
  # Every 'Close other apps' and 'Free up disk' should be echo commands
  local count
  count=$(grep -c "echo.*Close other apps\|echo.*Free up disk" "$INSTALLER_DIR/lib/error-recovery.sh")
  [[ $count -ge 4 ]]
}

@test "C2: no bare descriptive text in known-fix commands" {
  # These should NOT exist as standalone array entries (must be inside echo)
  ! grep -E '^[[:space:]]+"Close other apps' "$INSTALLER_DIR/lib/error-recovery.sh"
}

@test "C2: Memgraph kill guard checks process name" {
  grep -qE 'grep.*memgraph|grep.*-qi.*memgraph' "$INSTALLER_DIR/lib/error-recovery.sh"
}

@test "H4: no hardcoded TOTAL_STEPS assignment" {
  ! grep -qE '^TOTAL_STEPS=[0-9]' "$INSTALLER_DIR/lib/error-recovery.sh"
}

# ---------------------------------------------------------------------------
# Install.sh Fixes
# ---------------------------------------------------------------------------

@test "H1: preserve-files.sh not sourced" {
  ! grep -q 'source.*preserve-files\.sh\|\. .*preserve-files\.sh' "$INSTALLER_DIR/install.sh"
}

@test "H2: Homebrew URL pinned to aec7285" {
  grep -q 'Homebrew/install/aec7285' "$INSTALLER_DIR/install.sh"
}

@test "H2: Homebrew URL not pointing to HEAD" {
  # Only the actual curl install invocation matters, not help/echo text
  ! grep -v 'echo\|info\|warn\|Install manually\|BOLD' "$INSTALLER_DIR/install.sh" | grep -q 'Homebrew/install/HEAD'
}

@test "H3: timeout fallback has bg-kill pattern" {
  grep -q 'kill -9.*cmd_pid' "$INSTALLER_DIR/install.sh"
}

@test "H5: update mode checks VERSION not .env" {
  grep -qE 'VERSION.*update_mode|PI_AGENT_DIR.*VERSION' "$INSTALLER_DIR/install.sh"
}

@test "M2: chmod 600 on credential files" {
  local count
  count=$(grep -c 'chmod 600' "$INSTALLER_DIR/install.sh")
  [[ $count -ge 2 ]]
}

@test "M3: bootstrap PID liveness check" {
  grep -q 'kill -0.*bg_pid' "$INSTALLER_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# Security (lib/secrets-manager.sh + provider-configs)
# ---------------------------------------------------------------------------

@test "M1: secrets-manager uses salt" {
  grep -q 'secrets-salt' "$INSTALLER_DIR/lib/secrets-manager.sh"
}

@test "M1: salt generated from urandom" {
  grep -q 'urandom' "$INSTALLER_DIR/lib/secrets-manager.sh"
}

@test "no hardcoded API keys in installer files" {
  ! grep -rE 'sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}' \
    "$INSTALLER_DIR/install.sh" \
    "$INSTALLER_DIR/bootstrap.sh" \
    "$INSTALLER_DIR/lib/" \
    "$INSTALLER_DIR/provider-configs/"
}
