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

# ---------------------------------------------------------------------------
# 13. Bootstrap scheduling — TASK-05/06/08 invariants
# ---------------------------------------------------------------------------

@test "schedule_bootstrap function exists in install.sh" {
  grep -q 'schedule_bootstrap' "$INSTALLER_DIR/install.sh"
}

@test "schedule_bootstrap is called from main()" {
  grep -q 'schedule_bootstrap' "$INSTALLER_DIR/install.sh"
  # Verify it appears in the main() body (after the main() header line)
  python3 -c "
import sys
with open('$INSTALLER_DIR/install.sh') as f:
    lines = f.readlines()
in_main = False
depth = 0
found = False
for line in lines:
    if line.strip().startswith('main()') and '{' in line:
        in_main = True
        depth = 1
        continue
    if in_main:
        depth += line.count('{') - line.count('}')
        if 'schedule_bootstrap' in line and not line.strip().startswith('#'):
            found = True
        if depth <= 0:
            break
if not found:
    print('ERROR: schedule_bootstrap not called in main()')
    sys.exit(1)
"
}

@test "BOOTSTRAP_CWD env var is passed to bootstrap job in install.sh" {
  grep -q 'BOOTSTRAP_CWD' "$INSTALLER_DIR/install.sh"
}

@test "bootstrap state dir path matches HELIOS_GRAPH_BOOTSTRAP_STATE_DIR in runtime contract" {
  # Both install.sh and persist_runtime_contract must agree on the state dir
  python3 -c "
import sys, re
with open('$INSTALLER_DIR/install.sh') as f:
    content = f.read()
# runtime contract must include HELIOS_GRAPH_BOOTSTRAP_STATE_DIR
if 'HELIOS_GRAPH_BOOTSTRAP_STATE_DIR' not in content:
    print('ERROR: HELIOS_GRAPH_BOOTSTRAP_STATE_DIR missing from install.sh')
    sys.exit(1)
# schedule_bootstrap must reference codebase-bootstrap
if 'codebase-bootstrap' not in content:
    print('ERROR: codebase-bootstrap dir not referenced in install.sh')
    sys.exit(1)
"
}


@test "schedule_bootstrap writes queued state files before launching background job" {
  python3 -c "
import sys
with open('$INSTALLER_DIR/install.sh') as f:
    lines = f.readlines()
in_fn = False
depth = 0
fn_lines = []
for line in lines:
    if line.strip().startswith('schedule_bootstrap()') and '{' in line:
        in_fn = True
        depth = 1
        continue
    if in_fn:
        depth += line.count('{') - line.count('}')
        if depth <= 0:
            break
        fn_lines.append(line)
fn_body = ''.join(fn_lines)
json_pos = fn_body.find('json.dump')
nohup_pos = fn_body.find('nohup')
if json_pos < 0:
    print('ERROR: json.dump (state write) not found in schedule_bootstrap')
    sys.exit(1)
if nohup_pos < 0:
    print('ERROR: nohup (background launch) not found in schedule_bootstrap')
    sys.exit(1)
if json_pos > nohup_pos:
    print('ERROR: json.dump must come BEFORE nohup in schedule_bootstrap')
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# 14. verify.sh bootstrap section invariants
# ---------------------------------------------------------------------------

@test "verify.sh has bootstrap state section" {
  grep -q 'Bootstrap State' "$INSTALLER_DIR/verify.sh"
}

@test "verify.sh checks runtime contract file" {
  grep -q 'runtime_contract' "$INSTALLER_DIR/verify.sh"
}

@test "verify.sh check_bootstrap_target function exists" {
  grep -q 'check_bootstrap_target' "$INSTALLER_DIR/verify.sh"
}

@test "verify.sh prints self-heal commands for bootstrap failures" {
  python3 -c "
import sys
with open('$INSTALLER_DIR/verify.sh') as f:
    content = f.read()
# Should have self-heal command for at least one bootstrap failure case
if 'bootstrap-codebases.js' not in content:
    print('ERROR: bootstrap-codebases.js not referenced in verify.sh self-heal')
    sys.exit(1)
if 'index-codebase.js' not in content:
    print('ERROR: index-codebase.js not referenced in verify.sh self-heal')
    sys.exit(1)
"
}

@test "verify.sh bootstrap check covers both ~/.pi/agent and CWD" {
  python3 -c "
import sys
with open('$INSTALLER_DIR/verify.sh') as f:
    content = f.read()
if '~/.pi/agent' not in content and 'PI_AGENT_DIR' not in content:
    print('ERROR: verify.sh does not check bootstrap for ~/.pi/agent')
    sys.exit(1)
if 'CWD' not in content:
    print('ERROR: verify.sh does not check bootstrap for CWD')
    sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# 15. codebase-index.ts no longer hardcodes familiar-graph-1
# ---------------------------------------------------------------------------

@test "codebase-index.ts does not hardcode familiar-graph-1" {
  # Check the authoritative helios-package copy specifically
  local ext_file=""
  for candidate in \
    "$INSTALLER_DIR/../helios-package/extensions/codebase-index.ts" \
    "$INSTALLER_DIR/../helios/extensions/codebase-index.ts"; do
    if [[ -f "$candidate" ]]; then
      ext_file="$candidate"
      break
    fi
  done
  if [[ -z "$ext_file" ]]; then
    skip "codebase-index.ts not found relative to installer"
  fi
  # helios-package copy should NOT have the hardcoded exec command
  ext_file="$INSTALLER_DIR/../helios-package/extensions/codebase-index.ts"
  if [[ ! -f "$ext_file" ]]; then
    skip "helios-package/extensions/codebase-index.ts not found"
  fi
  # It should NOT have the literal hardcoded exec command
  if grep -q "familiar-graph-1 mgconsole" "$ext_file"; then
    echo "FAIL: helios-package/extensions/codebase-index.ts still hardcodes familiar-graph-1 in mgconsole exec"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 16. L4: install.sh env parsing handles values with embedded '='
# ---------------------------------------------------------------------------

@test "wire_env_to_shell uses IFS= read (first-equals-split) not IFS='=' read" {
  # The old IFS='=' read -r key val is fragile for values like AWS_SECRET=abc=xyz.
  # After L4 fix the function reads the whole line and splits on the first '=' explicitly.
  python3 -c "
import sys, re
with open('$INSTALLER_DIR/install.sh') as f:
    content = f.read()

# Find the wire_env_to_shell function body
m = re.search(r'wire_env_to_shell\(\)[^{]*\{(.{0,4000})', content, re.DOTALL)
if not m:
    print('ERROR: wire_env_to_shell() not found')
    sys.exit(1)
fn_body = m.group(1)[:2000]  # limit scan

# Bad old pattern: IFS='=' read -r key val
if re.search(r\"IFS='=' read\", fn_body):
    print('ERROR: wire_env_to_shell still uses IFS=\\\"=\\\" read (broken for values with \\\"=\\\")')
    sys.exit(1)

# Must use first-equals split approach
if '%%=*' not in fn_body and '#*=' not in fn_body:
    print('ERROR: wire_env_to_shell must split key/val on first = using %%=* and #*=')
    sys.exit(1)
"
}

@test "wire_env_to_shell preserves values containing '='" {
  # Functional test: export via a temp env file with a value containing '='
  local tmp_env
  tmp_env=$(mktemp)
  echo "TEST_KEY_WITH_EQ=hello=world" > "$tmp_env"
  echo "NORMAL_KEY=simple" >> "$tmp_env"

  local result
  result=$(bash -c "
$(grep -A 30 'wire_env_to_shell\(\)' '$INSTALLER_DIR/install.sh' | grep -v 'wire_env_to_shell\(\)' | head -20)
env_file='$tmp_env'
while IFS= read -r _env_line; do
  _env_line=\"\${_env_line#\"\${_env_line%%[! ]*}\"}\"
  [[ -z \"\$_env_line\" || \"\$_env_line\" == \#* ]] && continue
  _env_key=\"\${_env_line%%=*}\"
  _env_val=\"\${_env_line#*=}\"
  _env_key=\"\${_env_key#export }\"
  _env_key=\"\${_env_key#\"\${_env_key%%[! ]*}\"}\"
  _env_key=\"\${_env_key%\"\${_env_key##*[! ]}\"}\"
  _env_val=\"\${_env_val#\"\${_env_val%%[! ]*}\"}\"
  _env_val=\"\${_env_val%\"\${_env_val##*[! ]}\"}\"
  _env_val=\"\${_env_val#\\\"}\" ; _env_val=\"\${_env_val%\\\"}\"
  _env_val=\"\${_env_val#\'}\" ; _env_val=\"\${_env_val%\'}\"
  [[ \"\$_env_key\" =~ ^[A-Z_][A-Z_0-9]*$ ]] && [[ -n \"\$_env_val\" ]] && export \"\$_env_key=\$_env_val\"
done < \"\$env_file\"
echo \"\$TEST_KEY_WITH_EQ\"
" 2>/dev/null)
  rm -f "$tmp_env"
  [ "$result" = "hello=world" ]
}

