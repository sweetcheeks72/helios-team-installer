#!/usr/bin/env bats
# =============================================================================
# j_architecture.bats — J-Architecture Integration Tests
#
# Verifies the FULL helios-team-installer pipeline works correctly with the
# J-architecture (local git paths, clean secrets, correct build/install wiring).
#
# Sections:
#   1. Tarball Integration        — dist/helios-agent-latest.tar.gz structure
#   2. Build Script Integrity     — build-release.sh correctness
#   3. Installer Script Safety    — install.sh + lib/ scripts
#   4. Provider Configs           — provider-configs/*.json quality gates
#
# Usage:
#   cd ~/helios-team-installer && bats tests/j_architecture.bats
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
INSTALLER_DIR="${SCRIPT_DIR}/.."
TARBALL="${INSTALLER_DIR}/dist/helios-agent-latest.tar.gz"

# Resolve the top-level directory name inside the tarball (e.g. helios-agent-v1.1.0)
_tarball_top() {
  tar -tzf "${TARBALL}" 2>/dev/null | head -1 | cut -d/ -f1
}

# ============================================================================
# SECTION 1: TARBALL INTEGRATION
# ============================================================================

setup_tarball() {
  if [[ ! -f "${TARBALL}" ]]; then
    skip "Tarball not found at ${TARBALL} — run build-release.sh first"
  fi
}

# ---------------------------------------------------------------------------
# 1a. Required files exist
# ---------------------------------------------------------------------------

@test "tarball: settings.json is present inside the archive" {
  setup_tarball
  local top; top=$(_tarball_top)
  run bash -c "tar -tzf '${TARBALL}' | grep -qF '${top}/settings.json'"
  [ "$status" -eq 0 ]
}

@test "tarball: VERSION file is present inside the archive" {
  setup_tarball
  local top; top=$(_tarball_top)
  run bash -c "tar -tzf '${TARBALL}' | grep -qF '${top}/VERSION'"
  [ "$status" -eq 0 ]
}

@test "tarball: .release-manifest.txt is present inside the archive" {
  setup_tarball
  local top; top=$(_tarball_top)
  run bash -c "tar -tzf '${TARBALL}' | grep -qF '${top}/.release-manifest.txt'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 1b. settings.json uses local paths (git/github.com/, NOT git:github.com/)
# ---------------------------------------------------------------------------

@test "tarball: settings.json has zero git:github.com/ entries (local paths only)" {
  setup_tarball
  local top; top=$(_tarball_top)
  run python3 << PYEOF
import json, sys, subprocess, os

tarball = os.path.expanduser("${TARBALL}")
top = "${BATS_TEST_DESCRIPTION}"  # unused — we get top from env

result = subprocess.run(
    ['tar', '-xzf', tarball, '-O', '${top}/settings.json'],
    capture_output=True, text=True
)
if result.returncode != 0:
    # Re-compute top
    list_result = subprocess.run(['tar', '-tzf', tarball], capture_output=True, text=True)
    top2 = list_result.stdout.split('\n')[0].split('/')[0]
    result = subprocess.run(
        ['tar', '-xzf', tarball, '-O', f'{top2}/settings.json'],
        capture_output=True, text=True
    )

if not result.stdout.strip():
    print("FAIL: settings.json not found or empty in tarball")
    sys.exit(1)

data = json.loads(result.stdout)
pkgs = data.get("packages", [])

bad = []
for pkg in pkgs:
    if isinstance(pkg, str) and "git:github.com" in pkg:
        bad.append(pkg)
    elif isinstance(pkg, dict) and "git:github.com" in pkg.get("source", ""):
        bad.append(pkg.get("source"))

if bad:
    for b in bad:
        print(f"FAIL: git: URL found in tarball settings.json: {b}")
    sys.exit(1)
PYEOF
  [ "$status" -eq 0 ]
}

@test "tarball: settings.json uses git/github.com/ local paths for sweetcheeks72 packages" {
  setup_tarball
  local top; top=$(_tarball_top)
  run python3 << PYEOF
import json, sys, subprocess, os

tarball = os.path.expanduser("${TARBALL}")
top_dir = subprocess.run(['tar', '-tzf', tarball], capture_output=True, text=True).stdout.split('\n')[0].split('/')[0]

result = subprocess.run(
    ['tar', '-xzf', tarball, '-O', f'{top_dir}/settings.json'],
    capture_output=True, text=True
)
if not result.stdout.strip():
    print("FAIL: settings.json not found in tarball")
    sys.exit(1)

data = json.loads(result.stdout)
pkgs = data.get("packages", [])

# At least some packages should use local git/ paths
local_pkgs = [
    p for p in pkgs
    if (isinstance(p, str) and p.startswith("git/github.com/"))
    or (isinstance(p, dict) and p.get("source", "").startswith("git/github.com/"))
]

if len(local_pkgs) == 0:
    print("FAIL: no git/github.com/ local paths found in tarball settings.json")
    sys.exit(1)

print(f"OK: {len(local_pkgs)} local git/ path packages found")
PYEOF
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 1c. VERSION file is valid semver
# ---------------------------------------------------------------------------

@test "tarball: VERSION file contains valid semver (e.g. 1.1.0 or v1.1.0)" {
  setup_tarball
  local top; top=$(_tarball_top)
  run python3 << PYEOF
import subprocess, sys, re, os

tarball = os.path.expanduser("${TARBALL}")
top_dir = subprocess.run(['tar', '-tzf', tarball], capture_output=True, text=True).stdout.split('\n')[0].split('/')[0]

result = subprocess.run(
    ['tar', '-xzf', tarball, '-O', f'{top_dir}/VERSION'],
    capture_output=True, text=True
)
version = result.stdout.strip()
if not version:
    print("FAIL: VERSION file is empty or missing")
    sys.exit(1)

# Accept optional 'v' prefix, then major.minor.patch with optional pre-release/build
pattern = r'^v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$'
if not re.match(pattern, version):
    print(f"FAIL: VERSION '{version}' is not valid semver")
    sys.exit(1)

print(f"OK: VERSION = {version}")
PYEOF
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 1d. git/github.com/sweetcheeks72/ has >10 package dirs
# ---------------------------------------------------------------------------

@test "tarball: git/github.com/sweetcheeks72/ contains more than 10 package directories" {
  setup_tarball
  local top; top=$(_tarball_top)
  local count
  count=$(tar -tzf "${TARBALL}" | grep -cE "^${top}/git/github\.com/sweetcheeks72/[^/]+/$" || true)
  if [[ "$count" -le 10 ]]; then
    echo "FAIL: only ${count} package dirs in git/github.com/sweetcheeks72/ (expected >10)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1e. Excluded user data: .env, auth.json, .git/
# ---------------------------------------------------------------------------

@test "tarball: excludes .env files" {
  setup_tarball
  run bash -c "tar -tzf '${TARBALL}' | grep -qE '(^|/)\.env(\$|/)'"
  [ "$status" -ne 0 ]
}

@test "tarball: excludes auth.json" {
  setup_tarball
  run bash -c "tar -tzf '${TARBALL}' | grep -q 'auth\.json'"
  [ "$status" -ne 0 ]
}

@test "tarball: excludes .git/ directories" {
  setup_tarball
  run bash -c "tar -tzf '${TARBALL}' | grep -q '/\.git/'"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 1f. No secret patterns in tarball content
# ---------------------------------------------------------------------------

@test "tarball: no sk-ant- API key patterns in any extracted file" {
  setup_tarball
  run python3 << PYEOF
import subprocess, sys, re, os, tarfile

tarball = os.path.expanduser("${TARBALL}")
pattern = re.compile(r'\bsk-ant-[A-Za-z0-9_\-]{20,}')

with tarfile.open(tarball, 'r:gz') as tf:
    for member in tf.getmembers():
        if not member.isfile():
            continue
        # Only check text-like files (skip large binaries)
        if member.size > 500_000:
            continue
        try:
            f = tf.extractfile(member)
            if f is None:
                continue
            content = f.read().decode('utf-8', errors='ignore')
            m = pattern.search(content)
            if m:
                print(f"FAIL: sk-ant- key found in {member.name}")
                sys.exit(1)
        except Exception:
            pass
PYEOF
  [ "$status" -eq 0 ]
}

@test "tarball: no ghp_ GitHub token patterns in any extracted file" {
  setup_tarball
  run python3 << PYEOF
import subprocess, sys, re, os, tarfile

tarball = os.path.expanduser("${TARBALL}")
pattern = re.compile(r'\bghp_[A-Za-z0-9]{36,}')

with tarfile.open(tarball, 'r:gz') as tf:
    for member in tf.getmembers():
        if not member.isfile():
            continue
        if member.size > 500_000:
            continue
        try:
            f = tf.extractfile(member)
            if f is None:
                continue
            content = f.read().decode('utf-8', errors='ignore')
            # Skip the test file itself
            if 'j_architecture.bats' in member.name:
                continue
            m = pattern.search(content)
            if m:
                print(f"FAIL: ghp_ token found in {member.name}")
                sys.exit(1)
        except Exception:
            pass
PYEOF
  [ "$status" -eq 0 ]
}

@test "tarball: no AWS_SECRET_ACCESS_KEY patterns in any extracted file" {
  setup_tarball
  run python3 << PYEOF
import subprocess, sys, re, os, tarfile

tarball = os.path.expanduser("${TARBALL}")
# Match literal AWS_SECRET_ACCESS_KEY= followed by a non-empty value
pattern = re.compile(r'AWS_SECRET_ACCESS_KEY\s*=\s*[A-Za-z0-9+/]{20,}')

with tarfile.open(tarball, 'r:gz') as tf:
    for member in tf.getmembers():
        if not member.isfile():
            continue
        if member.size > 500_000:
            continue
        try:
            f = tf.extractfile(member)
            if f is None:
                continue
            content = f.read().decode('utf-8', errors='ignore')
            m = pattern.search(content)
            if m:
                print(f"FAIL: AWS_SECRET_ACCESS_KEY literal value found in {member.name}")
                sys.exit(1)
        except Exception:
            pass
PYEOF
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 1g. Governance templates are clean (not user-specific data)
# ---------------------------------------------------------------------------

@test "tarball: governance/credibility.json is a clean template (empty or minimal object)" {
  setup_tarball
  run python3 << PYEOF
import subprocess, sys, json, os

tarball = os.path.expanduser("${TARBALL}")
top_dir = subprocess.run(['tar', '-tzf', tarball], capture_output=True, text=True).stdout.split('\n')[0].split('/')[0]

result = subprocess.run(
    ['tar', '-xzf', tarball, '-O', f'{top_dir}/governance/credibility.json'],
    capture_output=True, text=True
)
if result.returncode != 0 or not result.stdout.strip():
    # May not exist — that is also acceptable as a "clean" state
    print("OK: governance/credibility.json not present (acceptable)")
    sys.exit(0)

try:
    data = json.loads(result.stdout)
except json.JSONDecodeError as e:
    print(f"FAIL: governance/credibility.json is invalid JSON: {e}")
    sys.exit(1)

# A clean template should be an empty object or very small
# It must NOT contain agent-specific entries from a live session
if isinstance(data, dict):
    # If it has entries, each value should be a number (credibility score template)
    for k, v in data.items():
        if not isinstance(v, (int, float, type(None))):
            print(f"FAIL: credibility.json has non-numeric entry: {k} = {v!r}")
            sys.exit(1)
    print(f"OK: credibility.json is a clean template with {len(data)} entries")
else:
    print(f"FAIL: credibility.json is not a JSON object (got {type(data).__name__})")
    sys.exit(1)
PYEOF
  [ "$status" -eq 0 ]
}

@test "tarball: governance/specialization-registry.json is a clean template" {
  setup_tarball
  run python3 << PYEOF
import subprocess, sys, json, os

tarball = os.path.expanduser("${TARBALL}")
top_dir = subprocess.run(['tar', '-tzf', tarball], capture_output=True, text=True).stdout.split('\n')[0].split('/')[0]

result = subprocess.run(
    ['tar', '-xzf', tarball, '-O', f'{top_dir}/governance/specialization-registry.json'],
    capture_output=True, text=True
)
if result.returncode != 0 or not result.stdout.strip():
    print("OK: governance/specialization-registry.json not present")
    sys.exit(0)

try:
    data = json.loads(result.stdout)
except json.JSONDecodeError as e:
    print(f"FAIL: specialization-registry.json invalid JSON: {e}")
    sys.exit(1)

# A clean template should have taskTypes (possibly empty) and lastUpdated
if not isinstance(data, dict):
    print(f"FAIL: specialization-registry.json is not a JSON object")
    sys.exit(1)

task_types = data.get("taskTypes", {})
if not isinstance(task_types, dict):
    print(f"FAIL: 'taskTypes' is not an object: {type(task_types).__name__}")
    sys.exit(1)

print(f"OK: specialization-registry.json is a clean template with {len(task_types)} task types")
PYEOF
  [ "$status" -eq 0 ]
}

# ============================================================================
# SECTION 2: BUILD SCRIPT INTEGRITY
# ============================================================================

@test "build: build-release.sh has 'export STAGE_DIR' (not just assignment)" {
  grep -q '^export STAGE_DIR' "${INSTALLER_DIR}/build-release.sh"
}

@test "build: build-release.sh uses sys.exit(1) for missing settings.json" {
  run python3 << PYEOF
import re, sys, os

build_sh = os.path.join("${INSTALLER_DIR}", "build-release.sh")
with open(build_sh) as f:
    content = f.read()

# Find the block checking for missing settings.json and using sys.exit
m = re.search(
    r'if not os\.path\.exists\(source_settings\).*?sys\.exit\((\d+)\)',
    content, re.DOTALL
)
if not m:
    print("FAIL: missing-settings.json guard with sys.exit not found in build-release.sh")
    sys.exit(1)

exit_code = int(m.group(1))
if exit_code != 1:
    print(f"FAIL: expected sys.exit(1) but found sys.exit({exit_code}) for missing settings.json")
    sys.exit(1)

print(f"OK: sys.exit(1) used for missing settings.json guard")
PYEOF
  [ "$status" -eq 0 ]
}

@test "build: build-release.sh generates settings.json using python3 heredoc" {
  # The settings.json generator must use a python3 heredoc (not node/sed/awk)
  run python3 << PYEOF
import re, sys, os

build_sh = os.path.join("${INSTALLER_DIR}", "build-release.sh")
with open(build_sh) as f:
    content = f.read()

# Must have a python3 heredoc that writes settings.json
# Pattern: python3 << 'HEREDOC_MARKER' ... settings.json
has_python3_heredoc = bool(re.search(r"python3\s*<<\s*['\"]?[A-Z_]+", content))
if not has_python3_heredoc:
    print("FAIL: no python3 heredoc found in build-release.sh")
    sys.exit(1)

# The heredoc must write settings.json
has_settings_write = 'settings.json' in content
if not has_settings_write:
    print("FAIL: settings.json not referenced in build-release.sh")
    sys.exit(1)

print("OK: python3 heredoc generates settings.json")
PYEOF
  [ "$status" -eq 0 ]
}

@test "build: settings.json generator converts git:github.com/ to git/github.com/" {
  run python3 << PYEOF
import re, sys, os

build_sh = os.path.join("${INSTALLER_DIR}", "build-release.sh")
with open(build_sh) as f:
    content = f.read()

# Must have the replace() call converting git: → git/
if "git:github.com/" not in content:
    print("FAIL: no git:github.com/ pattern found in build-release.sh")
    sys.exit(1)
if "git/github.com/" not in content:
    print("FAIL: no git/github.com/ replacement target found in build-release.sh")
    sys.exit(1)

# Must handle BOTH string packages and dict-with-source packages
if "isinstance(pkg, dict)" not in content:
    print("FAIL: dict package handling (isinstance(pkg, dict)) missing from build-release.sh")
    sys.exit(1)
if "isinstance(pkg, str)" not in content:
    print("FAIL: string package handling (isinstance(pkg, str)) missing from build-release.sh")
    sys.exit(1)

print("OK: build-release.sh handles both string and dict packages")
PYEOF
  [ "$status" -eq 0 ]
}

# ============================================================================
# SECTION 3: INSTALLER SCRIPT SAFETY
# ============================================================================

@test "install: install.sh does NOT source lib/preserve-files.sh" {
  # preserve-files.sh is dead code — sourcing it is a bug
  run grep -qE 'source[[:space:]]+.*preserve-files\.sh|\.[[:space:]]+.*preserve-files\.sh' \
    "${INSTALLER_DIR}/install.sh"
  [ "$status" -ne 0 ]
}

@test "install: install.sh pins Homebrew install script to commit aec7285" {
  grep -q 'Homebrew/install/aec7285' "${INSTALLER_DIR}/install.sh"
}

@test "install: _timeout_cmd has bg-kill fallback using kill -9 \$cmd_pid" {
  # The else branch (no system timeout binary) must implement background kill
  run python3 << PYEOF
import re, sys, os

install_sh = os.path.join("${INSTALLER_DIR}", "install.sh")
with open(install_sh) as f:
    content = f.read()

# Extract _timeout_cmd function body
m = re.search(r'_timeout_cmd\(\)[^{]*\{(.{0,4000})', content, re.DOTALL)
if not m:
    print("FAIL: _timeout_cmd() function not found in install.sh")
    sys.exit(1)

fn_body = m.group(1)

# Must have kill -9 "$cmd_pid" for the fallback bg-kill pattern
if 'kill -9' not in fn_body:
    print("FAIL: _timeout_cmd has no kill -9 fallback")
    sys.exit(1)

if 'cmd_pid' not in fn_body:
    print("FAIL: _timeout_cmd has no cmd_pid variable (background process tracking)")
    sys.exit(1)

print("OK: _timeout_cmd has bg-kill fallback with kill -9 \$cmd_pid")
PYEOF
  [ "$status" -eq 0 ]
}

@test "install: detect_update_mode checks VERSION file (not .env)" {
  run python3 << PYEOF
import re, sys, os

install_sh = os.path.join("${INSTALLER_DIR}", "install.sh")
with open(install_sh) as f:
    content = f.read()

# Extract detect_update_mode body
m = re.search(r'detect_update_mode\(\)[^{]*\{(.{0,5000})', content, re.DOTALL)
if not m:
    print("FAIL: detect_update_mode() not found in install.sh")
    sys.exit(1)

fn_body = m.group(1)

# Must check VERSION as a file (-f VERSION)
if 'VERSION' not in fn_body:
    print("FAIL: detect_update_mode() does not reference VERSION file")
    sys.exit(1)

if '-f' not in fn_body:
    print("FAIL: detect_update_mode() does not use -f file test for VERSION")
    sys.exit(1)

# Should NOT trigger on .env file for update detection
# (legacy bug: earlier versions checked .env instead of VERSION)
lines = fn_body.split('\n')
bad_lines = [l for l in lines if '\.env' in l and 'UPDATE_MODE' in l]
if bad_lines:
    print(f"FAIL: detect_update_mode() triggers UPDATE_MODE based on .env: {bad_lines[0].strip()}")
    sys.exit(1)

print("OK: detect_update_mode() checks VERSION file for update detection")
PYEOF
  [ "$status" -eq 0 ]
}

@test "install: install.sh has chmod 600 for credential files" {
  # chmod 600 ensures credential/secret files are owner-read-only
  grep -q 'chmod 600' "${INSTALLER_DIR}/install.sh"
}

@test "install: error-recovery.sh has no dual heartbeat (no heartbeat_pid variable)" {
  # Dual heartbeat was a bug — heartbeat_pid should not exist
  run grep -q 'heartbeat_pid' "${INSTALLER_DIR}/lib/error-recovery.sh"
  [ "$status" -ne 0 ]
}

@test "install: error-recovery.sh has no hardcoded TOTAL_STEPS=14 assignment" {
  # TOTAL_STEPS must NOT be hardcoded — it must be passed in from the caller
  run grep -qE 'TOTAL_STEPS=14' "${INSTALLER_DIR}/lib/error-recovery.sh"
  [ "$status" -ne 0 ]
}

@test "install: error-recovery.sh has no top-level hardcoded TOTAL_STEPS=<number>" {
  # Only bare assignment at top level is wrong; conditional usage like ${TOTAL_STEPS:-} is fine
  run grep -qE '^TOTAL_STEPS=[0-9]' "${INSTALLER_DIR}/lib/error-recovery.sh"
  [ "$status" -ne 0 ]
}

@test "install: secrets-manager.sh uses /dev/urandom for salt generation" {
  grep -q 'urandom' "${INSTALLER_DIR}/lib/secrets-manager.sh"
}

# ============================================================================
# SECTION 4: PROVIDER CONFIGS
# ============================================================================

@test "provider: anthropic.json is valid JSON" {
  python3 -c "import json; json.load(open('${INSTALLER_DIR}/provider-configs/anthropic.json'))"
}

@test "provider: bedrock.json is valid JSON" {
  python3 -c "import json; json.load(open('${INSTALLER_DIR}/provider-configs/bedrock.json'))"
}

@test "provider: openai.json is valid JSON" {
  python3 -c "import json; json.load(open('${INSTALLER_DIR}/provider-configs/openai.json'))"
}

@test "provider: anthropic.json has zero git:github.com/ entries" {
  run grep -q 'git:github\.com' "${INSTALLER_DIR}/provider-configs/anthropic.json"
  [ "$status" -ne 0 ]
}

@test "provider: bedrock.json has zero git:github.com/ entries" {
  run grep -q 'git:github\.com' "${INSTALLER_DIR}/provider-configs/bedrock.json"
  [ "$status" -ne 0 ]
}

@test "provider: openai.json has zero git:github.com/ entries" {
  run grep -q 'git:github\.com' "${INSTALLER_DIR}/provider-configs/openai.json"
  [ "$status" -ne 0 ]
}

@test "provider: all 3 provider configs have more than 15 packages" {
  run python3 << PYEOF
import json, sys, os

base = "${INSTALLER_DIR}"
configs = ["anthropic.json", "bedrock.json", "openai.json"]
failed = False

for cfg in configs:
    path = os.path.join(base, "provider-configs", cfg)
    with open(path) as f:
        data = json.load(f)
    count = len(data.get("packages", []))
    if count <= 15:
        print(f"FAIL: {cfg} has only {count} packages (expected >15)")
        failed = True
    else:
        print(f"OK: {cfg} has {count} packages")

if failed:
    sys.exit(1)
PYEOF
  [ "$status" -eq 0 ]
}

@test "provider: all 3 provider configs have non-empty enabledModels" {
  run python3 << PYEOF
import json, sys, os

base = "${INSTALLER_DIR}"
configs = ["anthropic.json", "bedrock.json", "openai.json"]
failed = False

for cfg in configs:
    path = os.path.join(base, "provider-configs", cfg)
    with open(path) as f:
        data = json.load(f)
    models = data.get("enabledModels", None)
    if models is None:
        print(f"FAIL: {cfg} missing 'enabledModels' field")
        failed = True
    elif not isinstance(models, list):
        print(f"FAIL: {cfg} 'enabledModels' is not an array (got {type(models).__name__})")
        failed = True
    elif len(models) == 0:
        print(f"FAIL: {cfg} 'enabledModels' is empty")
        failed = True
    else:
        print(f"OK: {cfg} has {len(models)} enabled model(s)")

if failed:
    sys.exit(1)
PYEOF
  [ "$status" -eq 0 ]
}

@test "provider: all 3 provider configs have a non-empty defaultProvider field" {
  run python3 << PYEOF
import json, sys, os

base = "${INSTALLER_DIR}"
configs = ["anthropic.json", "bedrock.json", "openai.json"]
failed = False

for cfg in configs:
    path = os.path.join(base, "provider-configs", cfg)
    with open(path) as f:
        data = json.load(f)
    dp = data.get("defaultProvider", None)
    if not dp:
        print(f"FAIL: {cfg} missing or empty 'defaultProvider'")
        failed = True
    else:
        print(f"OK: {cfg} defaultProvider = {dp!r}")

if failed:
    sys.exit(1)
PYEOF
  [ "$status" -eq 0 ]
}
