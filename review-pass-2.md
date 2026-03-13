# Adversarial Review — Pass 2: install.sh

**Reviewer:** Murray (adversarial)  
**Date:** 2026-03-13  
**File:** `/Users/chikochingaya/helios-team-installer/install.sh`  
**Focus:** Lines 608-745, 795-860, 900-945, 1005-1040, 1353-1435, 1465-1480, 1490-1545

---

## Phase 1: My Independent Approach (Blind)

Before reading the code, for a team installer shell script I would expect:
1. `set -euo pipefail` at top — every command must handle failure or the script dies
2. All `node -e` blocks should use `-- "$VAR"` + `process.argv[N]` to avoid injection
3. All `rm -rf` guarded against empty/unset paths
4. All variables double-quoted to prevent word-splitting
5. Fallback chains (python3 → node → raw) must handle ALL branches failing gracefully
6. Container detection must distinguish "binary exists" from "service is running"

## Phase 2: What The Code Does

- **Lines 608-745:** Provider selection menu → JSON merge of provider config into settings.json. Python3 first, node fallback, cp fallback.
- **Lines 855-900:** dep-allowlist.json — ensures neo4j-driver is in allowlist. Python3 → node fallback → create from scratch.
- **Lines 965-1010:** OrbStack/Docker detection for Memgraph container setup.
- **Lines 1075-1090:** Ollama auto-detection — skips if not installed.
- **Lines 1353-1465:** `dedup_skills_extensions()` — removes duplicate skills/extensions via `rm -rf`.
- **Lines 1535-1545:** Verification — settings.json provider read via python3 → node fallback.
- **Lines 1600-1615:** `keys_missing` count in quick-start guide.

## Phase 3: Socratic Interrogation

### Finding 1: Node.js code injection via unquoted variable interpolation in `node -e`

**Lines 1541, 1637-1638, 1703**

Several `node -e` blocks embed shell variables directly into JavaScript string literals instead of using `process.argv`:

```bash
# Line 1541
node -e "console.log(JSON.parse(require('fs').readFileSync('$PI_AGENT_DIR/settings.json','utf8')).defaultProvider||'?')"

# Line 1637-1638
node -e "console.log(JSON.parse(require('fs').readFileSync('$PI_AGENT_DIR/settings.json','utf8')).defaultProvider||'')"

# Line 1703
node -e "const c=require('crypto');process.stdout.write(c.createHash('sha256').update('$target_path').digest('hex').slice(0,16))"
```

If `PI_AGENT_DIR` or `target_path` contains a single quote (e.g., a path like `/Users/O'Brien/.pi/agent`), this breaks out of the JS string literal and enables arbitrary code execution.

**Contrast:** Lines 725-750 and 876-890 correctly use `-- "$VAR"` + `process.argv[1]`, showing the pattern is known.

**Severity:** MEDIUM (paths are mostly controlled, but `target_path` at line 1703 comes from function arguments making it more exploitable)

**Repro:** `PI_AGENT_DIR="/tmp/foo'+(console.log('pwned'),process.exit())+'bar"` → JS injection

---

### Finding 2: `((conflicts++))` returns non-zero when conflicts==0, needs `|| true` — ALREADY HANDLED ✅

Lines 1437 and 1458 have `((conflicts++)) || true` — this is correct. The `|| true` prevents `set -e` from killing the script when `conflicts` increments from 0 (which bash arithmetic treats as falsy). **No issue.**

---

### Finding 3: `rm -rf "$FAMILIAR_DIR/skills/$skill_name"` — safe IF variables are set

**Lines 1436, 1457**

- `$FAMILIAR_DIR` is set at line 87 as `$HOME/.familiar` — hardcoded, never empty with `set -u`.
- `$skill_name` comes from `basename` of a glob match, so it's always a directory name.
- `$ext_dir` comes from a glob expansion, always a real path.

**Verdict:** ✅ CONFIRMED SAFE. The `set -u` flag (line 10) would abort if any variable were unset. The glob patterns ensure the paths are real.

---

### Finding 4: OrbStack detection — `orb` exists but OrbStack not running

**Lines 972-997**

The code detects OrbStack via `command -v orb` or `command -v orbctl`, then checks if `docker` CLI is available. Later at line 996, there's a `docker info` check:

```bash
if ! docker info &>/dev/null 2>&1; then
    warn "Container runtime ... is installed but not running"
    return 0
fi
```

**Verdict:** ✅ CONFIRMED CORRECT. The `docker info` call at line 996 catches the case where OrbStack (or Docker) binary exists but the daemon isn't running. The flow is: detect binary → check docker CLI → check daemon running. All three cases handled.

---

### Finding 5: Ollama skip — does it break downstream?

**Lines 1075-1090**

When Ollama is not found, the function returns 0 with an info message. I checked downstream: `setup_ollama` is called independently, and `persist_runtime_contract` writes `OLLAMA_AVAILABLE=false` when Ollama is absent. The HEMA/embedding code checks this flag.

**Verdict:** ✅ CONFIRMED CORRECT. Skipping Ollama is a graceful degradation path, not a hard requirement.

---

### Finding 6: `keys_missing` pattern safety

**Lines 1604-1609**

```bash
keys_missing=$(grep -c '^[A-Z_]*=$' "$PI_AGENT_DIR/.env" 2>/dev/null || echo "0")
keys_missing="${keys_missing//[^0-9]/}"
keys_missing="${keys_missing:-0}"
if [ "$keys_missing" -gt 0 ] 2>/dev/null; then
```

**Analysis:**
- `grep -c` with `|| echo "0"` handles grep returning exit 1 (no matches) ✅
- `${keys_missing//[^0-9]/}` strips any non-numeric characters (e.g., whitespace from `wc`) ✅
- `${keys_missing:-0}` provides default if empty after stripping ✅  
- `[ "$keys_missing" -gt 0 ] 2>/dev/null` — the `2>/dev/null` suppresses the `integer expression expected` error if `keys_missing` is somehow still non-numeric. In that case `[` returns non-zero and the `if` branch is skipped ✅

**Verdict:** ✅ CONFIRMED SAFE. Triple-sanitization with graceful fallthrough. Robust defensive pattern.

---

### Finding 7: Python3 `sys.argv[1]` vs Node `process.argv[1]` — inconsistent `--` separator

**Lines 660-720 (python3) vs Lines 725-754 (node)**

Python3 blocks pass arguments positionally: `python3 -c "..." "$FILE1" "$FILE2"` → `sys.argv[1]`, `sys.argv[2]`.

Node blocks at lines 725-754 correctly use: `node -e "..." -- "$FILE1" "$FILE2"` → `process.argv[1]`, `process.argv[2]`.

The `--` separator is needed for node to prevent node from interpreting arguments as flags. Python3 doesn't need it because `-c` consumes the next argument and the rest go to `sys.argv`.

BUT at **line 876** (dep-allowlist node fallback):
```bash
node -e "
const fs = require('fs');
const p = process.argv[1];
..." -- "$allowlist" 2>/dev/null; then
```
This correctly uses `-- "$allowlist"` ✅.

**Verdict:** ✅ The blocks that use `process.argv` all correctly use `--`. The inconsistency is in the blocks that DON'T use `process.argv` (Finding 1 above).

---

### Finding 8: JSON merge fallback chain — complete failure path

**Lines 656-765**

```
If settings.json exists:
  1. Try python3 merge → merge_ok=true
  2. If not, try node merge → merge_ok=true
  3. If both fail → warn + cp template (OVERWRITES existing settings.json)
If no settings.json:
  cp template
```

**The fallback `cp` at line 761 is DATA LOSS.** If a user has custom settings (extra keys, custom packages, etc.) and both python3 and node are unavailable (rare but possible in minimal containers), the template overwrites their config.

**Severity:** LOW (requires neither python3 nor node available — very unlikely since Pi requires node). The `warn` message alerts the user.

**Verdict:** ⚠️ UNCERTAIN — acceptable tradeoff for an installer. Could be improved by backing up before overwriting.

---

## Phase 4: Verdict Summary

| # | Finding | Severity | Verdict |
|---|---------|----------|---------|
| 1 | Node.js injection via unquoted `$PI_AGENT_DIR` / `$target_path` in `node -e` string literals (lines 1541, 1637-1638, 1703) | MEDIUM | 🐛 BUG |
| 2 | `((conflicts++)) || true` | — | ✅ Already handled |
| 3 | `rm -rf` with unset vars | — | ✅ Safe (`set -u` guards) |
| 4 | OrbStack exists but not running | — | ✅ Handled by `docker info` check |
| 5 | Ollama skip downstream effects | — | ✅ Graceful degradation |
| 6 | `keys_missing` integer comparison | — | ✅ Triple-sanitized, safe |
| 7 | `process.argv` with `--` separator | — | ✅ Correct where used |
| 8 | JSON merge fallback overwrites existing settings | LOW | ⚠️ Acceptable tradeoff |

---

## Detailed Issue: Node.js String Injection (Finding 1)

### Affected Lines

| Line | Variable | Risk |
|------|----------|------|
| 1541 | `$PI_AGENT_DIR` | Single-quote in path breaks JS string literal |
| 1637 | `$PI_AGENT_DIR` | Same |
| 1638 | `$PI_AGENT_DIR` | Same |
| 1703 | `$target_path` | User-supplied path → higher risk |

### Fix Pattern

Change from:
```bash
node -e "console.log(JSON.parse(require('fs').readFileSync('$PI_AGENT_DIR/settings.json','utf8')).defaultProvider||'?')"
```
To:
```bash
node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultProvider||'?')" -- "$PI_AGENT_DIR/settings.json"
```

And for line 1703:
```bash
node -e "const c=require('crypto');process.stdout.write(c.createHash('sha256').update(process.argv[1]).digest('hex').slice(0,16))" -- "$target_path"
```

---

## OWASP Agentic Security Checks

| # | Check | Result |
|---|-------|--------|
| LLM01 | Prompt Injection | N/A — no LLM calls in installer |
| LLM02 | Insecure Output Handling | ⚠️ Finding 1 — shell variable interpolated into `node -e` code string |
| LLM06 | Excessive Agency | N/A |
| LLM08 | Vector/Embedding | N/A |
| ASI01 | Tool Output Injection | N/A |
| ASI02 | Excessive Permissions | N/A — installer has expected scope |
| ASI03 | Uncontrolled Recursion | N/A |
| ASI04 | Resource Exhaustion | ✅ — docker memory capped at 12GB |
| ASI05 | Supply Chain | ✅ — `npm install` runs in known dirs with lockfiles |

---

## Confidence: HIGH

All sections read thoroughly. Type-flow tracing complete on the python3/node fallback chains. The code injection finding is concrete and reproducible.

## Issues Found: 1 (+ 1 advisory)

- 🐛 **1 MEDIUM:** Node.js code injection via unquoted variable interpolation (4 occurrences)
- ⚠️ **1 LOW advisory:** JSON merge fallback overwrites existing settings (acceptable)

## Recommendation: FIX FIRST (the 4 `node -e` interpolation sites)

The fix is mechanical — change each site to use `process.argv[N]` with `--` separator, matching the pattern already used correctly elsewhere in the same file.

## Next Steps

- **Hans (verifier):** Verify the `set -euo pipefail` interaction with `|| true` guards on all subshell/pipeline commands
- **Dirac (auditor):** Verify the claim that all `rm -rf` paths are guarded by `set -u`

---

```
REVIEW_TOKEN: { verdict: NEEDS_WORK, issues: 1, critical: 0 }
```
