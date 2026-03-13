# Session Review — Final Adversarial Code Review

**Reviewer**: Murray (adversarial reviewer)  
**Date**: 2026-03-13  
**Scope**: install.sh (JSON merge, allowlist, Docker detection, dedup, .env fix) + sdk-runner.ts (model registry)

---

## Verdicts by Fix

### 1. Python3/Node JSON Merge (lines 628–730) — ⚠️ CONDITIONAL PASS

**Python3 path**: ✅ PASS — uses `sys.argv[]` for file paths, clean merge logic, proper error handling.

**Node fallback path**: ❌ FAIL — **Path injection bug**.

- `$PI_AGENT_DIR` and `$PROVIDER_CONFIG` are bash-interpolated directly into JavaScript string literals inside `node -e "..."`.
- If either path contains a single quote, the JS breaks with a SyntaxError.
- The `|| true` guard means the failure is silent → falls through to overwriting `settings.json` with the template, losing existing user settings.
- **Repro**: `PI_AGENT_DIR="/tmp/test'dir" bash install.sh` → node -e fails → settings.json overwritten.
- **Fix**: Pass paths as arguments: `node -e "..." -- "$PI_AGENT_DIR/settings.json" "$PROVIDER_CONFIG"` and use `process.argv[2]`, `process.argv[3]` inside the script.

**Additional bug (line 719)**: Node fallback uses raw `Set` for extensions dedup (`const eExtKeys = new Set(existing.extensions || [])`). If extensions are objects (not strings), reference equality fails and duplicates are added. Python3 version correctly uses `pkg_key()` for all three collections (skills, packages, extensions). **Inconsistent behavior between the two code paths.**

### 2. Dependency Allowlist (lines 825–855) — ⚠️ CONDITIONAL PASS

**Python3 path**: ✅ PASS — uses `sys.argv[1]`.

**Node fallback path**: ❌ FAIL — Same path injection as above. `fs.readFileSync('$allowlist', 'utf8')` embeds the path directly in JS source.

### 3. OrbStack/Docker Detection (lines 940–1005) — ✅ PASS

- Correctly detects OrbStack via `orb`/`orbctl`, falls back to Docker CLI.
- `docker info` check catches daemon-not-running.
- Container name discovery uses exact `grep -q "^name$"` matching — no substring risk.
- `|| true` guards on all `docker` calls protect `set -euo pipefail`.
- Memory cap at 12GB with graceful failure is a nice touch.
- No issues found.

### 4. Ollama / Memgraph Startup (lines 1005–1030) — ✅ PASS

- Docker compose v1 vs v2 detection is correct.
- Container name resolution uses same exact-match pattern.
- `run_with_spinner` failures are caught with `|| { warn ...; return 0; }`.
- No issues found.

### 5. Dedup Function (lines 1395–1432) — ✅ PASS

- Skill dedup: `basename` + `dirname` extracts just the directory name. Comparison is against exact directory existence in `$PI_AGENT_DIR/skills/`. `rm -rf` is scoped to `$FAMILIAR_DIR/skills/$skill_name` — cannot escape. Double-quoted throughout.
- Extension dedup: `find -name "$ext_name"` is exact match. Requires `package.json` + `index.ts`/`index.js` to confirm real extension before removal. Well-guarded.
- `((conflicts++)) || true` handles the `set -e` issue with arithmetic returning 0 when incrementing from 0. ✅ Correct.
- Minor: `break` inside `while read` subshell doesn't stop `find`, but functionally correct.

### 6. PATH Fix + keys_missing Fix (lines 1490–1510) — ✅ PASS

- `|| keys_set=0` correctly handles `pipefail` when all lines are filtered out by `grep -v`.
- Pipeline: `grep -v '^#' | grep -v '^$' | grep -v '=$'` correctly filters comments, empty lines, and unset keys (ending with `=`).
- `wc -l | tr -d ' '` handles macOS `wc` whitespace padding.
- No issues found.

### 7. SDK Model Registry Fix (sdk-runner.ts:558–655) — ✅ PASS

- Runtime feature detection is correct: checks legacy API → new API → throws descriptive error.
- `(sdk as any)` is the right approach — TypeScript types may not include the new API surface.
- Optional chaining (`AuthStorage?.create`) prevents crashes on missing exports.
- Promise deduplication prevents concurrent initialization races.
- Error handling clears `modelRegistryInitPromise` allowing retry on transient failures.
- `resolveModel()` has a proper fallback chain: explicit provider → inferred → search all → undefined (SDK default).
- **Advisory**: All types are `any`. Works for now but provides no compile-time safety. Consider adding a minimal interface when the SDK API stabilizes.

---

## Summary of Issues

| # | File:Line | Severity | Description |
|---|-----------|----------|-------------|
| 1 | install.sh:693-724 | **MEDIUM** | Path injection in node `-e` fallback — `$PI_AGENT_DIR`/`$PROVIDER_CONFIG` interpolated into JS string literals. Single quotes in paths break the script silently. |
| 2 | install.sh:851 | **MEDIUM** | Same path injection in node `-e` for allowlist update. |
| 3 | install.sh:719 | **LOW-MEDIUM** | Node fallback uses raw `Set` for extensions dedup (reference equality on objects fails). Python3 uses `pkg_key()`. Inconsistent behavior. |
| 4 | sdk-runner.ts | **ADVISORY** | All-`any` typing. No immediate risk but fragile long-term. |

## Overall Recommendation

**FIX FIRST** — Issues #1 and #2 are real injection bugs. While usernames with quotes are rare, an installer must be robust against all valid filesystem paths. The fix is straightforward: use `process.argv[]` instead of bash interpolation (matching the python3 pattern which already does this correctly with `sys.argv[]`).

Issue #3 should be fixed for consistency — use `pkgKey()` for extensions in the node path, matching the python3 behavior.

Issue #4 is advisory — no action needed now.

---

## REVIEW_TOKEN

```
REVIEW_TOKEN: { verdict: NEEDS_WORK, issues: 3, critical: 0 }
```
