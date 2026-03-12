#!/usr/bin/env bats
# unit_tests.bats — Static analysis tests for helios-team-installer
# Tests grep install.sh and provider-config JSONs to verify invariants.

INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ---------------------------------------------------------------------------
# 1. All 4 preserve loops include required items
# ---------------------------------------------------------------------------
@test "all 4 preserve loops include .env" {
  local count
  count=$(grep -c 'for preserve in.*\.env' "$INSTALLER_DIR/install.sh")
  [ "$count" -ge 4 ]
}

@test "all 4 preserve loops include settings.json" {
  local count
  count=$(grep -c 'for preserve in.*settings\.json' "$INSTALLER_DIR/install.sh")
  [ "$count" -ge 4 ]
}

@test "all 4 preserve loops include .helios" {
  local count
  count=$(grep -c 'for preserve in.*\.helios' "$INSTALLER_DIR/install.sh")
  [ "$count" -ge 4 ]
}

@test "all 4 preserve loops include auth.json" {
  local count
  count=$(grep -c 'for preserve in.*auth\.json' "$INSTALLER_DIR/install.sh")
  [ "$count" -ge 4 ]
}

@test "all 4 preserve loops include run-history.jsonl" {
  local count
  count=$(grep -c 'for preserve in.*run-history\.jsonl' "$INSTALLER_DIR/install.sh")
  [ "$count" -ge 4 ]
}

# ---------------------------------------------------------------------------
# 2. All provider configs have helios-tui.ts in extensions
# ---------------------------------------------------------------------------
@test "all provider configs have helios-tui.ts" {
  local failed=0
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    result=$(python3 -c "
import json, sys
with open('$cfg') as f:
    d = json.load(f)
exts = d.get('extensions', [])
if not any('helios-tui' in e for e in exts):
    print('MISSING helios-tui in ' + '$cfg')
    sys.exit(1)
" 2>&1)
    if [ $? -ne 0 ]; then
      echo "$result"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. No provider config has mcp-startup-visibility
# ---------------------------------------------------------------------------
@test "no provider config has mcp-startup-visibility" {
  local failed=0
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    result=$(python3 -c "
import json, sys
with open('$cfg') as f:
    content = f.read()
if 'mcp-startup-visibility' in content:
    print('FOUND mcp-startup-visibility in $cfg')
    sys.exit(1)
" 2>&1)
    if [ $? -ne 0 ]; then
      echo "$result"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 4. All provider configs have theme and interview keys
# ---------------------------------------------------------------------------
@test "all provider configs have theme key" {
  local failed=0
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    result=$(python3 -c "
import json, sys
with open('$cfg') as f:
    d = json.load(f)
if 'theme' not in d:
    print('MISSING theme key in $cfg')
    sys.exit(1)
" 2>&1)
    if [ $? -ne 0 ]; then
      echo "$result"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "all provider configs have interview key" {
  local failed=0
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    result=$(python3 -c "
import json, sys
with open('$cfg') as f:
    d = json.load(f)
if 'interview' not in d:
    print('MISSING interview key in $cfg')
    sys.exit(1)
" 2>&1)
    if [ $? -ne 0 ]; then
      echo "$result"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. ShellCheck passes on install.sh and build-release.sh
# ---------------------------------------------------------------------------
@test "shellcheck passes on install.sh" {
  if ! command -v shellcheck &>/dev/null; then
    skip "shellcheck not installed"
  fi
  run shellcheck -S warning -e SC2034,SC1090,SC1091,SC2155,SC2088 "$INSTALLER_DIR/install.sh"
  [ "$status" -eq 0 ]
}

@test "shellcheck passes on build-release.sh" {
  if ! command -v shellcheck &>/dev/null; then
    skip "shellcheck not installed"
  fi
  run shellcheck -S warning -e SC2034,SC1090,SC1091,SC2155 "$INSTALLER_DIR/build-release.sh"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. No tar commands swallow stderr
# ---------------------------------------------------------------------------
@test "no tar commands swallow stderr (tar.*2>/dev/null)" {
  # Use python3 to match 'tar' as a standalone command word (not 'tarball' etc.)
  python3 -c "
import re, sys
with open('$INSTALLER_DIR/install.sh') as f:
    lines = f.readlines()
bad = []
for i, line in enumerate(lines, 1):
    # Match 'tar' as a command: start of line (with optional whitespace/pipe/;/&) followed by 'tar '
    if re.search(r'(?:^|[\s;|&\$(])tar\s+[^|]*2>/dev/null', line):
        bad.append((i, line.rstrip()))
if bad:
    for lineno, text in bad:
        print(f'line {lineno}: {text}')
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# 7. install.sh has BASH_SOURCE main guard
# ---------------------------------------------------------------------------
@test "install.sh has BASH_SOURCE main guard" {
  grep -qE '\[\[.*\$\{?BASH_SOURCE\[0\]\}?.*==.*\$\{?0\}?.*\]\]' "$INSTALLER_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# 8. main() gates on setup_helios_agent failure (exit 1)
# ---------------------------------------------------------------------------
@test "main() gates on setup_helios_agent failure with exit 1" {
  # Verify setup_helios_agent || { ... exit 1 } pattern exists
  grep -qE 'setup_helios_agent' "$INSTALLER_DIR/install.sh"
  # Verify exit 1 follows the setup_helios_agent call in main context
  python3 -c "
import re, sys
with open('$INSTALLER_DIR/install.sh') as f:
    content = f.read()
# Find main() body and check it has setup_helios_agent ... exit 1 nearby
main_match = re.search(r'main\(\)[^{]*\{(.{0,3000})', content, re.DOTALL)
if not main_match:
    print('ERROR: main() function not found')
    sys.exit(1)
main_body = main_match.group(1)
if 'setup_helios_agent' not in main_body:
    print('ERROR: setup_helios_agent not called in main()')
    sys.exit(1)
if 'exit 1' not in main_body:
    print('ERROR: exit 1 not found in main() body after setup_helios_agent')
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# 9. install_helios_cli handles bin/fd
# ---------------------------------------------------------------------------
@test "install_helios_cli handles bin/fd" {
  grep -qE 'bin/fd' "$INSTALLER_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# 10. select_provider uses additive merge
# ---------------------------------------------------------------------------
@test "select_provider uses additive merge" {
  grep -qiE 'additive' "$INSTALLER_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# 11. Memgraph container resolution includes legacy fallback familiar-graph-1
# ---------------------------------------------------------------------------
@test "container resolution loop includes familiar-graph-1 fallback" {
  # The for-loop that checks for existing containers must include legacy name
  grep -qE 'for name in.+familiar-graph-1' "$INSTALLER_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# 12. Runtime contract persistence is present in install.sh
# ---------------------------------------------------------------------------
@test "persist_runtime_contract function exists in install.sh" {
  grep -q 'persist_runtime_contract' "$INSTALLER_DIR/install.sh"
}

@test "install.sh references memgraph.env runtime contract path" {
  grep -q 'memgraph.env' "$INSTALLER_DIR/install.sh"
}

@test "mg_running detection covers familiar-graph-1" {
  # The schema-apply step must also handle the legacy container name
  # (i.e., it should NOT be a bare grep-E "^memgraph$" any more)
  python3 -c "
import sys
with open('$INSTALLER_DIR/install.sh') as f:
    content = f.read()
# Bad pattern: grep -E that only matches memgraph and NOT familiar-graph-1 in the schema-apply block
import re
bad = re.search(r'grep\s+-[qE]+\s+[\'\"]\^memgraph\\\$[\'\"]\s', content)
if bad:
    print('ERROR: bare grep for ^memgraph$ still present — legacy name not handled')
    sys.exit(1)
"
}
