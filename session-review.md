# Adversarial Review: install.sh Bug Fixes (B1-B11)

## Phase 1: My Independent Approach (Blind)

Given the task of adding python3/node fallback patterns, OrbStack detection, and a dedup function:

1. JSON merge fallback: python3 then node chain. Node must merge ALL fields.
2. npm: set -euo pipefail means || { } pattern needed.
3. OrbStack: Check orb/orbctl, verify docker CLI.
4. Ollama: Detect-or-skip is safest.
5. Dedup: rm -rf is dangerous. Verify exact match, glob safety.
6. Arithmetic: grep -c returns exit 1 on zero matches.

Predicted edge cases: lossy node fallback, find false positives in dedup, ((conflicts++)) under set -e.

## Phase 2: Evidence Summary

11 bug fixes, +113 / -26 lines. Consistent python3-then-node pattern with || true guards.

## Phase 3: Findings

### BUG 1: Node fallback merge is LOSSY (MEDIUM)

Location: install.sh lines 689-700

Python3 merges: defaultProvider, defaultModel, assistantName, enabledModels, skills, packages, extensions, enableSkillCommands, hideThinkingBlock, quietStartup.

Node merges ONLY: defaultProvider, defaultModel, assistantName, enabledModels.

Missing: skills, packages, extensions, enableSkillCommands, hideThinkingBlock, quietStartup.

Impact: Users with broken python3 but working node lose skill/package/extension additions on upgrade.

### BUG 2: Dedup extension find-match too broad (MEDIUM)

Location: install.sh lines 1386-1396

The glob */$ext_name/index.ts matches ANY nested subdirectory, not just git package roots.
False positive: git/some-monorepo/src/my-ext/index.ts would cause rm -rf on extensions/my-ext/.

Repro: mkdir -p ~/.pi/agent/git/repo/src/my-ext && touch that dir/index.ts -> local extension deleted.

Fix: Require package.json sibling or limit find depth.

### LOW 3: Variable expansion in inline scripts (pre-existing, not a regression)

### LOW 4: PATH warning assumes zsh (cosmetic)

### CONFIRMED CORRECT: B3 (npm || {}), B4 (OrbStack), B5 (Ollama), B6 (dep-allowlist), B7 (keys_missing), B9 (verification fallback), B10 (((conflicts++)) || true)

## Phase 4: Verdict

| # | Finding | Severity |
|---|---------|----------|
| 1 | Node fallback merge lossy | MEDIUM |
| 2 | Dedup find-match too broad | MEDIUM |
| 3 | Variable expansion (pre-existing) | LOW |
| 4 | Zsh-only PATH warning | LOW |
| 5-11 | Other fixes | CORRECT |

## OWASP: LLM06 improved (Ollama auto-removed). ASI01 LOW (pre-existing). ASI05 PASS.

## Recommendation: FIX FIRST (issues 1 and 2)

## Confidence: HIGH

REVIEW_TOKEN: { verdict: NEEDS_WORK, issues: 2, critical: 0 }
