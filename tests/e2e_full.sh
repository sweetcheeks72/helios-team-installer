#!/usr/bin/env bash
# e2e_full.sh — Full end-to-end installer verification
# Extracts the tarball to a temp dir and verifies Pi would start correctly.
# Exit 0 = all pass, non-zero = failure count.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find the latest tarball
TARBALL=""
for f in "$REPO_ROOT/dist/helios-agent-latest-darwin-arm64.tar.gz" \
         "$REPO_ROOT/dist/helios-agent-latest.tar.gz"; do
  [[ -f "$f" ]] && TARBALL="$f" && break
done

if [[ -z "$TARBALL" ]]; then
  echo "ERROR: No tarball found in dist/"
  exit 2
fi

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

PASS=0
FAIL=0

pass() { echo "  ✓ $*"; ((PASS++)); }
fail() { echo "  ✗ $*"; ((FAIL++)); }
check() {
  local desc="$1"; shift
  if "$@" 2>/dev/null; then pass "$desc"; else fail "$desc"; fi
}

echo "=== Helios Installer E2E Test ==="
echo "Tarball: $(basename $TARBALL)"
echo "Test dir: $TEST_DIR"
echo ""

# 1. Extract tarball
echo "▶ Extraction"
tar xzf "$TARBALL" -C "$TEST_DIR" 2>/dev/null
ROOT=$(ls -d "$TEST_DIR"/helios-agent-* 2>/dev/null | head -1)
if [[ -z "$ROOT" ]]; then
  # Try strip-components
  mkdir -p "$TEST_DIR/agent"
  tar xzf "$TARBALL" --strip-components=1 -C "$TEST_DIR/agent" 2>/dev/null
  ROOT="$TEST_DIR/agent"
fi
check "Tarball extracts" test -d "$ROOT"
check "package.json exists" test -f "$ROOT/package.json"
echo ""

# 2. Core dependencies
echo "▶ Core Dependencies"
check "@helios-agent/pi-coding-agent" test -f "$ROOT/node_modules/@helios-agent/pi-coding-agent/package.json"
check "pi-coding-agent dist/index.js" test -f "$ROOT/node_modules/@helios-agent/pi-coding-agent/dist/index.js"
check "@helios-agent/pi-ai" test -d "$ROOT/node_modules/@helios-agent/pi-ai"
check "@helios-agent/pi-tui" test -d "$ROOT/node_modules/@helios-agent/pi-tui"
check "@helios-agent/pi-agent-core" test -d "$ROOT/node_modules/@helios-agent/pi-agent-core"
check "awilix" test -d "$ROOT/node_modules/awilix"
check "neo4j-driver" test -d "$ROOT/node_modules/neo4j-driver"
check "zod" test -d "$ROOT/node_modules/zod"
echo ""

# 3. ESM Import test
echo "▶ ESM Import Resolution"
if node --input-type=module -e "
import { pathToFileURL } from 'url';
const p = '$ROOT/node_modules/@helios-agent/pi-coding-agent/dist/index.js';
const m = await import(pathToFileURL(p));
if (Object.keys(m).length < 10) process.exit(1);
" 2>/dev/null; then
  pass "pi-coding-agent ESM import ($(node --input-type=module -e "import{pathToFileURL}from'url';const m=await import(pathToFileURL('$ROOT/node_modules/@helios-agent/pi-coding-agent/dist/index.js'));console.log(Object.keys(m).length)" 2>/dev/null) exports)"
else
  fail "pi-coding-agent ESM import"
fi
echo ""

# 4. Git packages
echo "▶ Git Packages"
PKG_DIR="$ROOT/git/github.com/helios-agi"
if [[ -d "$PKG_DIR" ]]; then
  PKG_COUNT=$(find "$PKG_DIR" -maxdepth 1 -type d | tail -n +2 | wc -l | tr -d ' ')
  if [[ $PKG_COUNT -ge 15 ]]; then
    pass "Git packages: $PKG_COUNT (≥15)"
  else
    fail "Git packages: $PKG_COUNT (<15)"
  fi
  check "pi-powerline-footer" test -f "$PKG_DIR/pi-powerline-footer/index.ts"
  check "pi-subagents" test -d "$PKG_DIR/pi-subagents"
  check "pi-interactive-shell" test -d "$PKG_DIR/pi-interactive-shell"
  check "pi-design-deck" test -d "$PKG_DIR/pi-design-deck"
else
  fail "Git packages directory missing"
fi
echo ""

# 5. Powerline footer fix
echo "▶ Powerline Footer ESM Fix"
if grep -q 'await import.*pi-coding-agent' "$PKG_DIR/pi-powerline-footer/index.ts" 2>/dev/null; then
  pass "Powerline footer uses await import() (not require())"
else
  fail "Powerline footer still uses require() — ESM crash risk"
fi
echo ""

# 6. Settings & config
echo "▶ Configuration"
check "settings.json" test -f "$ROOT/settings.json"
check "extensions/ directory" test -d "$ROOT/extensions"
check "skills/ directory" test -d "$ROOT/skills"
check "VERSION file" test -f "$ROOT/VERSION"
if [[ -f "$ROOT/settings.json" ]]; then
  SETTING_PKGS=$(python3 -c "import json; d=json.load(open('$ROOT/settings.json')); print(len(d.get('packages',[])))" 2>/dev/null || echo 0)
  if [[ $SETTING_PKGS -ge 15 ]]; then
    pass "settings.json packages: $SETTING_PKGS (≥15)"
  else
    fail "settings.json packages: $SETTING_PKGS (<15)"
  fi
fi
echo ""

# 7. Install skip logic (would installer skip npm install?)
echo "▶ Install Skip Logic"
if [[ -d "$ROOT/node_modules/awilix" ]] && [[ -d "$ROOT/node_modules/neo4j-driver" ]]; then
  pass "Verify check would PASS — npm install would be skipped"
else
  fail "Verify check would FAIL — npm install would run (risk of corruption)"
fi
echo ""

# 8. Node modules count
echo "▶ Node Modules Health"
NM_COUNT=$(find "$ROOT/node_modules" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
if [[ $NM_COUNT -ge 100 ]]; then
  pass "node_modules: $NM_COUNT packages (≥100)"
else
  fail "node_modules: $NM_COUNT packages (<100)"
fi
echo ""

# Summary
echo "═══════════════════════════════════════"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo "✓ ALL $TOTAL TESTS PASSED"
else
  echo "✗ $FAIL/$TOTAL TESTS FAILED"
fi
echo "═══════════════════════════════════════"

exit $FAIL
