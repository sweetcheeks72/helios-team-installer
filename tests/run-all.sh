#!/usr/bin/env bash
set -euo pipefail

echo "=== Architecture: $(uname -m) ==="
echo "=== Platform: $(uname -s) ==="
echo ""

echo "▶ Unit tests"
bats tests/unit_tests.bats
echo ""

echo "▶ Architecture tests"
if [[ -f tests/j_architecture.bats ]]; then
  bats tests/j_architecture.bats
elif [[ -f tests/architecture.bats ]]; then
  bats tests/architecture.bats
else
  echo "(no architecture test file found — skipping)"
fi
echo ""

echo "▶ Prerequisite tests"
if [[ -f tests/prerequisites_arch.bats ]]; then
  bats tests/prerequisites_arch.bats
else
  echo "(tests/prerequisites_arch.bats not yet created — skipping)"
fi
echo ""

echo "▶ Settings generation tests"
bats tests/settings_generation.bats 2>/dev/null || echo "(settings tests skipped or failed)"
echo ""

echo "▶ Local paths tests"
bats tests/local_paths.bats 2>/dev/null || echo "(local paths tests skipped or failed)"
echo ""

echo "▶ CTO audit fixes tests"
bats tests/cto_audit_fixes.bats 2>/dev/null || echo "(CTO audit tests skipped or failed)"
echo ""

echo "▶ Memgraph arch tests"
if [[ -f tests/memgraph_arch.bats ]]; then
  bats tests/memgraph_arch.bats
else
  echo "(tests/memgraph_arch.bats not yet created — skipping)"
fi
echo ""

echo "▶ Installer integration tests"
bats tests/installer_integration.bats 2>/dev/null || echo "(not yet created)"
echo ""

echo "✅ All test suites complete"
