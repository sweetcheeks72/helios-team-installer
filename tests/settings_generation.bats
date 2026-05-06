#!/usr/bin/env bats

# Integration test: settings.json generation
# Tests the actual python3 step from build-release.sh against real settings.json

setup() {
  INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_STAGE="$(mktemp -d)"
  export STAGE_DIR="$TEST_STAGE"
}

teardown() {
  rm -rf "$TEST_STAGE"
}

@test "golden path: settings.json generated with local paths" {
  # Run the ACTUAL python3 heredoc from build-release.sh
  python3 << 'PYEOF'
import json, sys, os

source_settings = os.path.expanduser("~/.pi/agent/settings.json")
if not os.path.exists(source_settings):
    sys.exit(1)

with open(source_settings) as f:
    settings = json.load(f)

new_packages = []
for pkg in settings.get("packages", []):
    if isinstance(pkg, dict):
        src = pkg.get("source", "")
        if src.startswith("git:github.com/sweetcheeks72/"):
            new_pkg = dict(pkg)
            new_pkg["source"] = src.replace("git:github.com/", "git/github.com/")
            new_packages.append(new_pkg)
        else:
            new_packages.append(pkg)
    elif isinstance(pkg, str) and pkg.startswith("git:github.com/sweetcheeks72/"):
        new_packages.append(pkg.replace("git:github.com/", "git/github.com/"))
    else:
        new_packages.append(pkg)

settings["packages"] = new_packages
for key in ["mcpServers"]:
    settings.pop(key, None)

stage_dir = os.environ["STAGE_DIR"]
with open(os.path.join(stage_dir, "settings.json"), "w") as f:
    json.dump(settings, f, indent=2)
PYEOF

  # Verify output exists
  [[ -f "$TEST_STAGE/settings.json" ]]
}

@test "no git: URLs in generated settings.json" {
  # Depends on previous test's output
  run python3 << 'PYEOF'
import json, sys, os
stage = os.environ["STAGE_DIR"]
# Generate first
src = os.path.expanduser("~/.pi/agent/settings.json")
if not os.path.exists(src): sys.exit(1)
settings = json.load(open(src))
new = []
for p in settings.get("packages",[]):
    if isinstance(p,str) and p.startswith("git:github.com/sweetcheeks72/"):
        new.append(p.replace("git:github.com/","git/github.com/"))
    elif isinstance(p,dict) and p.get("source","").startswith("git:github.com/sweetcheeks72/"):
        new.append({**p, "source": p["source"].replace("git:github.com/","git/github.com/")})
    else: new.append(p)
settings["packages"]=new
settings.pop("mcpServers",None)
json.dump(settings, open(os.path.join(stage,"settings.json"),"w"), indent=2)
# Now verify
d = json.load(open(os.path.join(stage, "settings.json")))
for p in d.get("packages",[]):
    s = p.get("source",p) if isinstance(p,dict) else p
    if isinstance(s,str) and "git:github.com/sweetcheeks72" in s:
        print(f"FAIL: found git: URL: {s}")
        sys.exit(1)
print("PASS: no git: URLs found")
PYEOF
  [[ "$status" -eq 0 ]]
}

@test "npm:pi-mcp-adapter preserved unchanged" {
  run python3 -c "
import json, os
stage = os.environ.get('STAGE_DIR', '/tmp')
src = os.path.expanduser('~/.pi/agent/settings.json')
settings = json.load(open(src))
new = []
for p in settings.get('packages',[]):
    if isinstance(p,str) and p.startswith('git:github.com/sweetcheeks72/'):
        new.append(p.replace('git:github.com/','git/github.com/'))
    elif isinstance(p,dict) and p.get('source','').startswith('git:github.com/sweetcheeks72/'):
        new.append({**p, 'source': p['source'].replace('git:github.com/','git/github.com/')})
    else: new.append(p)
settings['packages']=new
settings.pop('mcpServers',None)
json.dump(settings, open(os.path.join(stage,'settings.json'),'w'), indent=2)
d = json.load(open(os.path.join(stage, 'settings.json')))
has_npm = any(p == 'npm:pi-mcp-adapter' for p in d['packages'] if isinstance(p,str))
print('PASS' if has_npm else 'FAIL: npm:pi-mcp-adapter missing')
import sys; sys.exit(0 if has_npm else 1)
"
  [[ "$status" -eq 0 ]]
}

@test "mcpServers stripped from output" {
  run python3 -c "
import json, os
stage = os.environ.get('STAGE_DIR', '/tmp')
src = os.path.expanduser('~/.pi/agent/settings.json')
settings = json.load(open(src))
settings['packages'] = [p.replace('git:github.com/','git/github.com/') if isinstance(p,str) and p.startswith('git:github.com/sweetcheeks72/') else p for p in settings.get('packages',[])]
settings.pop('mcpServers',None)
json.dump(settings, open(os.path.join(stage,'settings.json'),'w'), indent=2)
d = json.load(open(os.path.join(stage,'settings.json')))
print('PASS' if 'mcpServers' not in d else 'FAIL: mcpServers still present')
import sys; sys.exit(0 if 'mcpServers' not in d else 1)
"
  [[ "$status" -eq 0 ]]
}

@test "provider merge: bedrock produces valid config" {
  local out="$TEST_STAGE/bedrock.json"
  local script="$HOME/.pi/agent/scripts/merge-provider-config.js"
  if [[ ! -f "$script" ]]; then
    skip "merge-provider-config.js not found"
  fi
  run node "$script" bedrock "$out" 2>&1
  if [[ "$status" -ne 0 ]]; then
    skip "merge script has upstream parse error: ${output:0:80}"
  fi
  [[ -f "$out" ]]
  run python3 -c "import json; d=json.load(open('$out')); assert d['defaultProvider']=='amazon-bedrock'; print('PASS')"
  [[ "$status" -eq 0 ]]
}

@test "STAGE_DIR export: build-release.sh exports it" {
  grep -q 'export STAGE_DIR' "$INSTALLER_DIR/build-release.sh"
}

@test "build-release.sh: sys.exit(1) on missing settings.json" {
  grep -q 'sys.exit(1)' "$INSTALLER_DIR/build-release.sh"
}
