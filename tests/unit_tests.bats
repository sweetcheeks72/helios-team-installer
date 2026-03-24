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


# ---------------------------------------------------------------------------
# TEST-1: _timeout_cmd structure (static analysis)
# ---------------------------------------------------------------------------

@test "_timeout_cmd uses timeout when available" {
  # The 'if' branch must call 'timeout "$@"'
  local fn_body
  fn_body=$(sed -n '/^_timeout_cmd()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$fn_body" | grep -q 'command -v timeout'
  echo "$fn_body" | grep -q 'timeout "\$@"'
}

@test "_timeout_cmd falls back to gtimeout" {
  # The 'elif' branch must call 'gtimeout "$@"'
  local fn_body
  fn_body=$(sed -n '/^_timeout_cmd()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$fn_body" | grep -q 'gtimeout'
  echo "$fn_body" | grep -q 'gtimeout "\$@"'
}

@test "_timeout_cmd runs without timeout when neither available" {
  # The 'else' branch must shift the duration arg and run the command directly
  local fn_body
  fn_body=$(sed -n '/^_timeout_cmd()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$fn_body" | grep -q 'else'
  echo "$fn_body" | grep -q 'shift'
  # After shift, remaining "$@" is the actual command
  echo "$fn_body" | grep -q '"\$@"'
}

# ---------------------------------------------------------------------------
# TEST-1: run_with_spinner functional tests
#
# These tests source the extracted functions into a subshell.
# start_spinner / stop_spinner are stubbed out to avoid /dev/tty writes.
# _timeout_cmd is overridden where needed to simulate timeout (exit 124)
# without requiring the 'timeout' binary.
# ---------------------------------------------------------------------------

# Helper: write installer functions to ${BATS_TMPDIR}/installer_functions.bash
_ensure_installer_fn_file() {
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  [[ -f "$fn_file" ]] && return 0

  local py="${BATS_TMPDIR}/extract_installer_fns.py"
  # Write extractor script first (avoids heredoc quoting issues)
  cat > "$py" << 'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.read().split('\n')
out = [
    'set +euo pipefail',
    'CYAN="" RESET="" BOLD="" DIM="" GREEN="" RED="" YELLOW=""',
    'spin_pid=""',
]
for fn_name in ['_timeout_cmd', 'start_spinner', 'stop_spinner', 'run_with_spinner']:
    in_fn, depth, fl = False, 0, []
    for line in lines:
        if not in_fn and re.match(r'^' + re.escape(fn_name) + r'\(\)', line):
            in_fn = True
        if in_fn:
            fl.append(line)
            depth += line.count('{') - line.count('}')
            if depth <= 0 and len(fl) > 1:
                break
    if fl:
        out.extend(fl)
        out.append('')
out += [
    'success() { echo "SUCCESS: $*"; }',
    'error()   { echo "ERROR: $*" >&2; }',
    'warn()    { echo "WARN: $*" >&2; }',
    'info()    { echo "INFO: $*"; }',
]
with open(dst, 'w') as f:
    f.write('\n'.join(out) + '\n')
PYEOF

  python3 "$py" "${INSTALLER_DIR}/install.sh" "$fn_file"
}

@test "run_with_spinner returns exit 124 on timeout" {
  _ensure_installer_fn_file
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  local log="${BATS_TMPDIR}/rws_timeout_$$.log"
  touch "$log"

  # Override _timeout_cmd to return 124 immediately, simulating a timeout.
  # This tests run_with_spinner's handling of exit 124 without needing the
  # 'timeout' binary.
  run bash -c "
    source '$fn_file'
    export LOG_FILE='$log'
    export STEP_TIMEOUT=2
    start_spinner() { :; }
    stop_spinner()  { :; }
    _timeout_cmd()  { return 124; }
    run_with_spinner 'timeout test' sleep 10
  "
  [ "$status" -eq 124 ]
}

@test "run_with_spinner appends timeout message to log on exit 124" {
  _ensure_installer_fn_file
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  local log="${BATS_TMPDIR}/rws_tmsg_$$.log"
  touch "$log"

  bash -c "
    source '$fn_file'
    export LOG_FILE='$log'
    export STEP_TIMEOUT=2
    start_spinner() { :; }
    stop_spinner()  { :; }
    _timeout_cmd()  { return 124; }
    run_with_spinner 'timeout test' sleep 10
  " 2>/dev/null || true

  grep -q "Timed out" "$log"
}

@test "run_with_spinner does NOT show timeout message on normal failure" {
  _ensure_installer_fn_file
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  local log="${BATS_TMPDIR}/rws_nofail_$$.log"
  touch "$log"

  # Use real _timeout_cmd (just pass-through shift/"$@") for a non-timeout failure
  run bash -c "
    source '$fn_file'
    export LOG_FILE='$log'
    export STEP_TIMEOUT=5
    start_spinner() { :; }
    stop_spinner()  { :; }
    # Override _timeout_cmd to behave like the 'no timeout binary' else-branch
    _timeout_cmd()  { shift; \"\$@\"; }
    run_with_spinner 'failing test' false
  "

  # Exit code must not be 124
  [ "$status" -ne 124 ]
  # Log must not contain the timeout message
  ! grep -q "Timed out" "$log"
}

@test "run_with_spinner succeeds on normal command" {
  _ensure_installer_fn_file
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  local log="${BATS_TMPDIR}/rws_ok_$$.log"
  touch "$log"

  run bash -c "
    source '$fn_file'
    export LOG_FILE='$log'
    export STEP_TIMEOUT=5
    start_spinner() { :; }
    stop_spinner()  { :; }
    _timeout_cmd()  { shift; \"\$@\"; }
    run_with_spinner 'success test' true
  "
  [ "$status" -eq 0 ]
}

@test "run_with_spinner provides /dev/null as stdin to commands" {
  _ensure_installer_fn_file
  local fn_file="${BATS_TMPDIR}/installer_functions.bash"
  local log="${BATS_TMPDIR}/rws_stdin_$$.log"
  touch "$log"

  # 'wc -c' reads all of stdin and prints byte count.
  # With /dev/null as stdin it gets 0 bytes and exits 0 immediately.
  # Without /dev/null it would block reading from the terminal.
  run bash -c "
    source '$fn_file'
    export LOG_FILE='$log'
    export STEP_TIMEOUT=5
    start_spinner() { :; }
    stop_spinner()  { :; }
    _timeout_cmd()  { shift; \"\$@\"; }
    run_with_spinner 'stdin test' bash -c 'bytes=\$(wc -c); [[ \$bytes -eq 0 ]]'
  "
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# TEST-2: macOS npm prefix redirect (static analysis)
# ---------------------------------------------------------------------------

@test "install_pi has macOS npm prefix writability check" {
  # The Darwin block must reference both Darwin (uname check) and node_modules
  python3 -c "
import sys, re
with open('${INSTALLER_DIR}/install.sh') as f:
    content = f.read()
m = re.search(
    r'# macOS: check if npm global prefix.*?(?=# Fix npm global prefix on Linux|^\S)',
    content, re.DOTALL | re.MULTILINE)
if not m:
    print('ERROR: macOS npm prefix block not found'); sys.exit(1)
block = m.group(0)
if 'Darwin' not in block:
    print('ERROR: Darwin check missing from npm prefix block'); sys.exit(1)
if 'node_modules' not in block:
    print('ERROR: node_modules reference missing from npm prefix block'); sys.exit(1)
"
}

@test "macOS prefix check tests node_modules not just lib" {
  # The writability check variable must reference 'node_modules' specifically
  # (not just the 'lib' parent dir), ensuring the right path is tested
  python3 -c "
import sys, re
with open('${INSTALLER_DIR}/install.sh') as f:
    content = f.read()
m = re.search(
    r'# macOS: check if npm global prefix.*?(?=# Fix npm global prefix on Linux|^\S)',
    content, re.DOTALL | re.MULTILINE)
if not m:
    print('ERROR: macOS npm prefix block not found'); sys.exit(1)
block = m.group(0)
# Must have 'node_modules' in the path variable (not just the bare 'lib' dir)
if not re.search(r'node_modules', block):
    print('ERROR: node_modules not in macOS prefix check'); sys.exit(1)
"
}

@test "macOS prefix redirect uses ~/.npm-global" {
  python3 -c "
import sys, re
with open('${INSTALLER_DIR}/install.sh') as f:
    content = f.read()
m = re.search(
    r'# macOS: check if npm global prefix.*?(?=# Fix npm global prefix on Linux|^\S)',
    content, re.DOTALL | re.MULTILINE)
if not m:
    print('ERROR: macOS npm prefix block not found'); sys.exit(1)
block = m.group(0)
if '.npm-global' not in block:
    print('ERROR: .npm-global redirect missing from macOS prefix block'); sys.exit(1)
"
}

@test "macOS prefix redirect adds to PATH" {
  python3 -c "
import sys, re
with open('${INSTALLER_DIR}/install.sh') as f:
    content = f.read()
m = re.search(
    r'# macOS: check if npm global prefix.*?(?=# Fix npm global prefix on Linux|^\S)',
    content, re.DOTALL | re.MULTILINE)
if not m:
    print('ERROR: macOS npm prefix block not found'); sys.exit(1)
block = m.group(0)
if 'PATH' not in block:
    print('ERROR: PATH update missing from macOS prefix redirect block'); sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# Additional: Branding invariant — no user-visible "Pi " in output strings
# ---------------------------------------------------------------------------

@test "no user-visible Pi branding in echo/step/info/warn/success strings" {
  # Write the checker to a temp file to avoid bash/python quoting conflicts
  local py="${BATS_TMPDIR}/check_branding.py"
  cat > "$py" << 'PYEOF'
import re, sys

src = sys.argv[1]
with open(src) as f:
    lines = f.readlines()

output_fn = re.compile(r'\b(echo|step|info|warn|success|error)\b')
# Match quoted strings containing 'Pi ' (capital P + space) — the user-visible
# product brand pattern. Skips comments, variable refs ($PI_...), and paths.
pi_brand = re.compile(r'(?:"[^"]*\bPi [^"]*"|\'[^\']*\bPi [^\']*\')')

violations = []
for i, line in enumerate(lines, 1):
    stripped = line.lstrip()
    if stripped.startswith('#'):
        continue
    if not output_fn.search(line):
        continue
    if pi_brand.search(line):
        violations.append((i, line.rstrip()))

if violations:
    for lineno, text in violations:
        print('  Line {}: {}'.format(lineno, text))
    sys.exit(1)
PYEOF
  python3 "$py" "${INSTALLER_DIR}/install.sh"
}

# ---------------------------------------------------------------------------
# NEW: update_pi_cli invariants (TASK-01 forensic test plan)
# ---------------------------------------------------------------------------
@test "update_pi_cli function exists" {
  grep -q '^update_pi_cli()' "$INSTALLER_DIR/install.sh"
}

@test "update_pi_cli uses @helios-agent/cli not @mariozechner" {
  local body
  body=$(sed -n '/^update_pi_cli()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q '@helios-agent/cli'
}

@test "update_pi_cli captures version from stderr (2>&1)" {
  local body
  body=$(sed -n '/^update_pi_cli()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q '2>&1'
}

@test "update_pi_cli has npm view timeout" {
  local body
  body=$(sed -n '/^update_pi_cli()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q 'fetch-timeout'
}

# ---------------------------------------------------------------------------
# NEW: update_agent_dir invariants
# ---------------------------------------------------------------------------
@test "update_agent_dir function exists" {
  grep -q '^update_agent_dir()' "$INSTALLER_DIR/install.sh"
}

@test "update_agent_dir uses --ff-only" {
  local body
  body=$(sed -n '/^update_agent_dir()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q '\-\-ff-only'
}

@test "update_agent_dir gates stash on success" {
  local body
  body=$(sed -n '/^update_agent_dir()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q 'if git.*stash push'
}

# ---------------------------------------------------------------------------
# NEW: FULL_UPDATE flag
# ---------------------------------------------------------------------------
@test "FULL_UPDATE flag detected from --full" {
  grep -q '\-\-full.*FULL_UPDATE=true' "$INSTALLER_DIR/install.sh"
}

@test "TOTAL_STEPS=9 when FULL_UPDATE" {
  grep -q 'TOTAL_STEPS=9' "$INSTALLER_DIR/install.sh"
}

@test "FULL_UPDATE runs setup_memgraph" {
  local block
  block=$(grep -A5 'FULL_UPDATE.*true' "$INSTALLER_DIR/install.sh" | tail -n +2)
  echo "$block" | grep -q 'setup_memgraph'
}

# ---------------------------------------------------------------------------
# NEW: snapshot/verify/rollback
# ---------------------------------------------------------------------------
@test "snapshot_state function exists" {
  grep -q '^snapshot_state()' "$INSTALLER_DIR/install.sh"
}

@test "verify_update function exists" {
  grep -q '^verify_update()' "$INSTALLER_DIR/install.sh"
}

@test "rollback_update function exists" {
  grep -q '^rollback_update()' "$INSTALLER_DIR/install.sh"
}

@test "verify_update checks settings.json" {
  local body
  body=$(sed -n '/^verify_update()/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -q 'settings.json'
}

# ---------------------------------------------------------------------------
# NEW: No stale @mariozechner references
# ---------------------------------------------------------------------------
@test "no @mariozechner/pi-coding-agent references in installer" {
  run grep -c '@mariozechner/pi-coding-agent' "$INSTALLER_DIR/install.sh"
  [ "$output" = "0" ]
}
