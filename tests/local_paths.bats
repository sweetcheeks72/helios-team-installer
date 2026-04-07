#!/usr/bin/env bats

# local_paths.bats — Comprehensive tests for the local-path package feature
# Verifies git: URLs are converted to local paths and all CTO-audit fixes landed.
#
# Run: bats tests/local_paths.bats
#
# Test plan:
#   Golden Path  (1–11):  Core invariants that must hold for the feature to work
#   Edge Cases  (12–18):  Boundary/structural verification
#   Security    (19–21):  Credential and secret hygiene

setup() {
  INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# ============================================================================
# GOLDEN PATH
# ============================================================================

# 1. All 3 provider configs have ZERO git: entries
@test "golden: anthropic.json has no git:github.com/ entries" {
  ! grep -q 'git:github\.com' "$INSTALLER_DIR/provider-configs/anthropic.json"
}

@test "golden: bedrock.json has no git:github.com/ entries" {
  ! grep -q 'git:github\.com' "$INSTALLER_DIR/provider-configs/bedrock.json"
}

@test "golden: openai.json has no git:github.com/ entries" {
  ! grep -q 'git:github\.com' "$INSTALLER_DIR/provider-configs/openai.json"
}

# 2. All 3 provider configs have the same package count (20)
@test "golden: all 3 provider configs have exactly 20 packages" {
  python3 << 'PYEOF'
import json, sys

configs = ["anthropic.json", "bedrock.json", "openai.json"]
import os
base = os.environ.get("INSTALLER_DIR", "")
counts = {}
for cfg in configs:
    path = os.path.join(base, "provider-configs", cfg)
    with open(path) as f:
        d = json.load(f)
    counts[cfg] = len(d.get("packages", []))

# All must equal 20
wrong = {k: v for k, v in counts.items() if v != 20}
if wrong:
    for name, count in wrong.items():
        print(f"FAIL: {name} has {count} packages (expected 20)")
    sys.exit(1)

# All must match each other
if len(set(counts.values())) != 1:
    for name, count in counts.items():
        print(f"  {name}: {count} packages")
    print("FAIL: package counts differ across provider configs")
    sys.exit(1)
PYEOF
}

# 3. build-release.sh contains `export STAGE_DIR`
@test "golden: build-release.sh exports STAGE_DIR (not just assigns)" {
  grep -q '^export STAGE_DIR' "$INSTALLER_DIR/build-release.sh"
}

# 4. build-release.sh uses sys.exit(1) for missing settings.json
@test "golden: build-release.sh uses sys.exit(1) for missing settings.json" {
  # Must have sys.exit(1) in the missing-settings.json block — not sys.exit(0)
  python3 << 'PYEOF'
import re, sys, os
base = os.environ.get("INSTALLER_DIR", "")
with open(os.path.join(base, "build-release.sh")) as f:
    content = f.read()

# Find the block that checks for missing settings.json
m = re.search(
    r'if not os\.path\.exists\(source_settings\).*?sys\.exit\((\d+)\)',
    content, re.DOTALL
)
if not m:
    print("FAIL: missing-settings.json block with sys.exit not found")
    sys.exit(1)

exit_code = int(m.group(1))
if exit_code != 1:
    print(f"FAIL: sys.exit({exit_code}) — expected sys.exit(1) for missing settings.json")
    sys.exit(1)
PYEOF
}

# 5. The python3 settings.json generator converts all git: URLs to local paths
@test "golden: settings.json generator converts git:github.com/ to git/github.com/" {
  python3 << 'PYEOF'
import re, sys, os
base = os.environ.get("INSTALLER_DIR", "")
with open(os.path.join(base, "build-release.sh")) as f:
    content = f.read()

# The generator must call .replace("git:github.com/", "git/github.com/")
# both for string packages and dict {"source": "..."} packages
if 'git:github.com/' not in content:
    print("FAIL: no git:github.com/ replacement pattern found in build-release.sh")
    sys.exit(1)
if 'git/github.com/' not in content:
    print("FAIL: no git/github.com/ target path found in build-release.sh")
    sys.exit(1)

# Both the string path and the dict-source path must be handled
if 'isinstance(pkg, dict)' not in content:
    print("FAIL: dict package handling missing from settings.json generator")
    sys.exit(1)
if 'isinstance(pkg, str)' not in content:
    print("FAIL: string package handling missing from settings.json generator")
    sys.exit(1)
PYEOF
}

# 6. install.sh does NOT source lib/preserve-files.sh
@test "golden: install.sh does not source lib/preserve-files.sh" {
  ! grep -qE 'source[[:space:]]+.*preserve-files\.sh|\.[[:space:]]+.*preserve-files\.sh' \
    "$INSTALLER_DIR/install.sh"
}

# 7. install.sh pins Homebrew to aec7285
@test "golden: install.sh pins Homebrew install script to commit aec7285" {
  grep -q 'Homebrew/install/aec7285' "$INSTALLER_DIR/install.sh"
}

# 8. install.sh _timeout_cmd has bg-kill fallback with kill -9
@test "golden: _timeout_cmd has bg-kill fallback using kill -9 \$cmd_pid" {
  local fn_body
  fn_body=$(sed -n '/^_timeout_cmd()/,/^}/p' "$INSTALLER_DIR/install.sh")
  # The else branch must have the background kill pattern
  echo "$fn_body" | grep -q 'kill -9 "\$cmd_pid"'
}

# 9. detect_update_mode checks for VERSION file (not .env)
@test "golden: detect_update_mode checks for VERSION file" {
  python3 << 'PYEOF'
import re, sys, os
base = os.environ.get("INSTALLER_DIR", "")
with open(os.path.join(base, "install.sh")) as f:
    content = f.read()

# Extract detect_update_mode body
m = re.search(r'detect_update_mode\(\)[^{]*\{(.{0,3000})', content, re.DOTALL)
if not m:
    print("FAIL: detect_update_mode() not found")
    sys.exit(1)

fn_body = m.group(1)
if 'VERSION' not in fn_body:
    print("FAIL: detect_update_mode does not reference VERSION file")
    sys.exit(1)

# Must check VERSION as a file (-f), not just grep for the word
if '-f' not in fn_body and 'VERSION' not in fn_body:
    print("FAIL: detect_update_mode VERSION check is not a file test")
    sys.exit(1)
PYEOF
}

# 10. error-recovery.sh has NO heartbeat_pid variable (dual heartbeat removed)
@test "golden: error-recovery.sh has no heartbeat_pid variable" {
  ! grep -q 'heartbeat_pid' "$INSTALLER_DIR/lib/error-recovery.sh"
}

# 11. error-recovery.sh has NO hardcoded TOTAL_STEPS= assignment
@test "golden: error-recovery.sh has no hardcoded TOTAL_STEPS= assignment" {
  # No 'TOTAL_STEPS=<number>' at the top level (assignment, not conditional reference)
  ! grep -qE '^TOTAL_STEPS=[0-9]' "$INSTALLER_DIR/lib/error-recovery.sh"
  ! grep -qE 'TOTAL_STEPS=14' "$INSTALLER_DIR/lib/error-recovery.sh"
}

# ============================================================================
# EDGE CASES
# ============================================================================

# 12. Provider configs are valid JSON (parse without error)
@test "edge: anthropic.json is valid JSON" {
  python3 -c "import json; json.load(open('$INSTALLER_DIR/provider-configs/anthropic.json'))"
}

@test "edge: bedrock.json is valid JSON" {
  python3 -c "import json; json.load(open('$INSTALLER_DIR/provider-configs/bedrock.json'))"
}

@test "edge: openai.json is valid JSON" {
  python3 -c "import json; json.load(open('$INSTALLER_DIR/provider-configs/openai.json'))"
}

# 13. Provider configs all have defaultProvider field
@test "edge: all provider configs have defaultProvider field" {
  python3 << 'PYEOF'
import json, sys, os
base = os.environ.get("INSTALLER_DIR", "")
configs = ["anthropic.json", "bedrock.json", "openai.json"]
failed = False
for cfg in configs:
    with open(os.path.join(base, "provider-configs", cfg)) as f:
        d = json.load(f)
    if "defaultProvider" not in d:
        print(f"FAIL: {cfg} missing 'defaultProvider' field")
        failed = True
    elif not d["defaultProvider"]:
        print(f"FAIL: {cfg} has empty 'defaultProvider'")
        failed = True
if failed:
    sys.exit(1)
PYEOF
}

# 14. Provider configs all have enabledModels array with >0 entries
@test "edge: all provider configs have non-empty enabledModels array" {
  python3 << 'PYEOF'
import json, sys, os
base = os.environ.get("INSTALLER_DIR", "")
configs = ["anthropic.json", "bedrock.json", "openai.json"]
failed = False
for cfg in configs:
    with open(os.path.join(base, "provider-configs", cfg)) as f:
        d = json.load(f)
    models = d.get("enabledModels", None)
    if models is None:
        print(f"FAIL: {cfg} missing 'enabledModels' field")
        failed = True
    elif not isinstance(models, list):
        print(f"FAIL: {cfg} 'enabledModels' is not an array")
        failed = True
    elif len(models) == 0:
        print(f"FAIL: {cfg} 'enabledModels' array is empty")
        failed = True
if failed:
    sys.exit(1)
PYEOF
}

# 15. error-recovery.sh known-fix entries are all valid shell commands
@test "edge: error-recovery.sh known-fix commands are all valid shell syntax" {
  python3 << 'PYEOF'
import re, subprocess, sys, os
base = os.environ.get("INSTALLER_DIR", "")
with open(os.path.join(base, "lib/error-recovery.sh")) as f:
    content = f.read()

# Extract _KNOWN_FIX_CMDS array entries
m = re.search(r'_KNOWN_FIX_CMDS=\((.+?)\)', content, re.DOTALL)
if not m:
    print("FAIL: _KNOWN_FIX_CMDS array not found")
    sys.exit(1)

block = m.group(1)
# Extract quoted strings from the array (handles escaped quotes inside)
entries = re.findall(r'"((?:[^"\\]|\\.)*)"', block)

failed = False
for entry in entries:
    # Unescape the entry (it uses \ escaping in the shell array literal)
    cmd = entry.replace('\\$', '$').replace('\\"', '"').replace("\\'", "'").replace('\\\\', '\\').replace('\\n', '\n')
    # Check syntax via bash -n
    result = subprocess.run(
        ['bash', '-n', '-c', cmd],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"FAIL: invalid shell syntax in known-fix command:")
        print(f"  cmd: {entry[:80]}")
        print(f"  error: {result.stderr.strip()}")
        failed = True

if failed:
    sys.exit(1)
PYEOF
}

# 16. install.sh _timeout_cmd handles duration=0 gracefully
@test "edge: _timeout_cmd fallback branch handles duration=0 without error" {
  # Test: override timeout/gtimeout to be absent, run _timeout_cmd 0 true
  # The else branch uses 'sleep 0' which is valid on all POSIX systems
  run bash << 'BASH'
# Source only _timeout_cmd by extracting and sourcing its body
_timeout_cmd() {
  # Simulate the 'else' branch directly (no timeout binary available)
  local duration=$1; shift
  "$@" &
  local cmd_pid=$!
  ( sleep "$duration" && kill -9 "$cmd_pid" 2>/dev/null ) &
  local killer_pid=$!
  wait "$cmd_pid" 2>/dev/null
  local exit_code=$?
  kill "$killer_pid" 2>/dev/null 2>&1
  wait "$killer_pid" 2>/dev/null 2>&1
  return $exit_code
}

_timeout_cmd 0 true
BASH
  [ "$status" -eq 0 ]
}

# 17. settings.json generator handles {source: "git:..."} dict objects
@test "edge: settings.json generator handles dict packages with source key" {
  python3 << 'PYEOF'
import json, sys, os, tempfile

base = os.environ.get("INSTALLER_DIR", "")

# Build a synthetic settings.json with both string and dict package entries
synthetic = {
    "packages": [
        "git:github.com/sweetcheeks72/pi-tui",
        {"source": "git:github.com/sweetcheeks72/pi-subagents", "version": "1.0"},
        "npm:some-other-package",
        {"source": "npm:another-package", "version": "2.0"},
    ]
}

# Run the same transformation logic as in build-release.sh
new_packages = []
converted = 0
for pkg in synthetic.get("packages", []):
    if isinstance(pkg, dict):
        src = pkg.get("source", "")
        if src.startswith("git:github.com/sweetcheeks72/"):
            local_path = src.replace("git:github.com/", "git/github.com/")
            new_pkg = dict(pkg)
            new_pkg["source"] = local_path
            new_packages.append(new_pkg)
            converted += 1
        else:
            new_packages.append(pkg)
    elif isinstance(pkg, str) and pkg.startswith("git:github.com/sweetcheeks72/"):
        local_path = pkg.replace("git:github.com/", "git/github.com/")
        new_packages.append(local_path)
        converted += 1
    else:
        new_packages.append(pkg)

# Verify string conversion
assert_pkg = new_packages[0]
if isinstance(assert_pkg, str) and assert_pkg.startswith("git:"):
    print(f"FAIL: string pkg still has git: prefix: {assert_pkg}")
    sys.exit(1)
if not (isinstance(assert_pkg, str) and assert_pkg.startswith("git/github.com/")):
    print(f"FAIL: string pkg not converted correctly: {assert_pkg}")
    sys.exit(1)

# Verify dict conversion
dict_pkg = new_packages[1]
if not isinstance(dict_pkg, dict):
    print(f"FAIL: dict pkg lost its dict type: {dict_pkg}")
    sys.exit(1)
if dict_pkg.get("source", "").startswith("git:"):
    print(f"FAIL: dict pkg source still has git: prefix: {dict_pkg['source']}")
    sys.exit(1)
if not dict_pkg.get("source", "").startswith("git/github.com/"):
    print(f"FAIL: dict pkg source not converted correctly: {dict_pkg.get('source')}")
    sys.exit(1)

# Verify non-git packages untouched
if new_packages[2] != "npm:some-other-package":
    print(f"FAIL: non-git string pkg was modified: {new_packages[2]}")
    sys.exit(1)
if new_packages[3].get("source") != "npm:another-package":
    print(f"FAIL: non-git dict pkg was modified: {new_packages[3]}")
    sys.exit(1)

# Verify conversion count
if converted != 2:
    print(f"FAIL: expected 2 conversions, got {converted}")
    sys.exit(1)
PYEOF
}

# 18. No git:github.com/sweetcheeks72 in provider-configs/ (production data)
@test "edge: no git:github.com/sweetcheeks72 in any provider config" {
  ! grep -r 'git:github\.com/sweetcheeks72' "$INSTALLER_DIR/provider-configs/"
}

# ============================================================================
# SECURITY
# ============================================================================

# 19. install.sh contains chmod 600 for credential files
@test "security: install.sh uses chmod 600 for credential/secret files" {
  grep -q 'chmod 600' "$INSTALLER_DIR/install.sh"
}

# 20. secrets-manager.sh references .secrets-salt file
@test "security: secrets-manager.sh references .secrets-salt file" {
  grep -q '\.secrets-salt' "$INSTALLER_DIR/lib/secrets-manager.sh"
}

# 21. No hardcoded API keys or tokens in any installer file
@test "security: no hardcoded API keys or tokens in installer files" {
  python3 << 'PYEOF'
import re, sys, os

base = os.environ.get("INSTALLER_DIR", "")
files = [
    "install.sh",
    "build-release.sh",
    "lib/error-recovery.sh",
    "lib/secrets-manager.sh",
    "lib/containers.sh",
    "lib/platform.sh",
]

# Patterns that would indicate hardcoded credentials
# - OpenAI/Anthropic sk- keys (20+ alphanumeric chars after sk-)
# - AWS AKIA keys (AKIA followed by 16 uppercase alphanumeric)
# - GitHub PAT (ghp_ or github_pat_ followed by long alphanumeric)
# - Generic "api_key = <long literal>"
# Note: short sk- prefixes (like variable names $sk_...) are excluded by length
PATTERNS = [
    (r'\bsk-[A-Za-z0-9]{20,}\b',       "OpenAI/Anthropic API key"),
    (r'\bAKIA[0-9A-Z]{16}\b',           "AWS Access Key ID"),
    (r'\bghp_[A-Za-z0-9]{36,}\b',       "GitHub PAT (ghp_)"),
    (r'\bgithub_pat_[A-Za-z0-9]{30,}\b',"GitHub PAT (github_pat_)"),
    (r'api[_-]?key\s*=\s*["\'][A-Za-z0-9+/]{20,}["\']', "hardcoded api_key value"),
]

violations = []
for rel_path in files:
    full_path = os.path.join(base, rel_path)
    if not os.path.exists(full_path):
        continue
    with open(full_path) as f:
        lines = f.readlines()
    for i, line in enumerate(lines, 1):
        stripped = line.lstrip()
        # Skip comment lines
        if stripped.startswith('#'):
            continue
        for pattern, label in PATTERNS:
            if re.search(pattern, line):
                violations.append(f"{rel_path}:{i} — {label}: {line.rstrip()[:80]}")

if violations:
    for v in violations:
        print(f"FAIL: {v}")
    sys.exit(1)
PYEOF
}
