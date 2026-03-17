#!/usr/bin/env bash
# =============================================================================
# e2e_feature_parity.sh — Verify installed Helios matches golden standard
# =============================================================================
# Checks that a fresh install has all agents, skills, extensions, packages,
# prompts, templates, schemas, and config that the developer has locally.
# Exit code = number of failures (0 = all passed).
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

PASS=0; FAIL=0; WARN=0
PI_AGENT="${HOME}/.pi/agent"

pass() { echo -e "  ${GREEN}✓${RESET} $*"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}✗${RESET} $*"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; ((WARN++)) || true; }
section() { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║   Helios Feature Parity Verification              ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── 1. Core Files ─────────────────────────────────────────────────────────
section "Core Files"

REQUIRED_FILES=(
  "SYSTEM.md"
  "APPEND_SYSTEM.md"
  "AGENTS.md"
  "VERSION"
  "bin/helios"
  "mcp.json"
  "extension-registry.json"
  "proxies/memgraph/docker-compose.yml"
  "models.json"
  "package.json"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -e "$PI_AGENT/$f" ]]; then
    pass "$f"
  else
    fail "$f MISSING"
  fi
done

# ─── 2. Agent Definitions ────────────────────────────────────────────────
section "Agent Definitions (expect 48+)"

REQUIRED_AGENTS=(
  "helios-system.md"
  "scout.md"
  "worker.md"
  "reviewer.md"
  "planner.md"
  "verifier.md"
  "auditor.md"
  "researcher.md"
)

agent_count=$(find "$PI_AGENT/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$agent_count" -ge 48 ]]; then
  pass "Agent count: $agent_count (≥48)"
else
  fail "Agent count: $agent_count (expected ≥48)"
fi

for agent in "${REQUIRED_AGENTS[@]}"; do
  if [[ -f "$PI_AGENT/agents/$agent" ]]; then
    pass "Agent: $agent"
  else
    fail "Agent MISSING: $agent"
  fi
done

# ─── 3. Skills ────────────────────────────────────────────────────────────
section "Skills (expect 16+)"

REQUIRED_SKILLS=(
  "helios-prime"
  "helios-governance"
  "engineering"
  "gsd"
  "tdd-enforcement"
  "feynman-shared"
  "worker-methodology"
  "helios-design-system"
  "visual-explainer"
  "design-deck"
  "skill-graph"
  "data-model-first"
  "helios-bugfix-pipeline"
  "helios-health"
  "helios-pr-review"
  "focus"
)

skill_count=$(find "$PI_AGENT/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$skill_count" -ge 16 ]]; then
  pass "Skill count: $skill_count (≥16)"
else
  fail "Skill count: $skill_count (expected ≥16)"
fi

for skill in "${REQUIRED_SKILLS[@]}"; do
  if [[ -f "$PI_AGENT/skills/$skill/SKILL.md" ]]; then
    pass "Skill: $skill"
  else
    # Check if it's provided by a git package
    if find "$PI_AGENT/git" -path "*/$skill/SKILL.md" 2>/dev/null | grep -q .; then
      pass "Skill: $skill (via git package)"
    else
      fail "Skill MISSING: $skill"
    fi
  fi
done

# ─── 4. Extensions ───────────────────────────────────────────────────────
section "Extensions"

REQUIRED_EXTENSIONS=(
  "helios-governance"
  "helios-tui.ts"
  "codebase-index.ts"
  "subagent-inline-enforce.ts"
  "subagent-mesh.ts"
  "auto-update.ts"
  "registry-loader.ts"
  "git-push-guard.ts"
)

for ext in "${REQUIRED_EXTENSIONS[@]}"; do
  if [[ -e "$PI_AGENT/extensions/$ext" ]]; then
    pass "Extension: $ext"
  else
    fail "Extension MISSING: $ext"
  fi
done

# ─── 5. Git Packages (installed via pi update) ──────────────────────────
section "Git Packages (expect 18+)"

REQUIRED_PACKAGES=(
  "pi-subagents"
  "pi-messenger"
  "pi-coordination"
  "pi-interactive-shell"
  "pi-design-deck"
  "visual-explainer"
  "pi-web-access"
  "surf-cli"
  "pi-interview-tool"
  "pi-review-loop"
  "pi-model-switch"
  "pi-foreground-chains"
  "pi-annotate"
  "pi-boomerang"
  "pi-skill-palette"
  "pi-rewind-hook"
  "pi-prompt-template-model"
  "pi-powerline-footer"
)

pkg_count=$(find "$PI_AGENT/git" -maxdepth 4 -name "package.json" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$pkg_count" -ge 18 ]]; then
  pass "Git package count: $pkg_count (≥18)"
else
  fail "Git package count: $pkg_count (expected ≥18)"
fi

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if find "$PI_AGENT/git" -maxdepth 4 -type d -name "$pkg" 2>/dev/null | grep -q .; then
    pass "Package: $pkg"
  else
    fail "Package MISSING: $pkg"
  fi
done

# ─── 6. Prompts ──────────────────────────────────────────────────────────
section "Prompts"

REQUIRED_PROMPTS=(
  "helios.md"
  "worker.md"
  "planner.md"
  "adversarial-review.md"
  "debug-protocol.md"
)

for prompt in "${REQUIRED_PROMPTS[@]}"; do
  if [[ -f "$PI_AGENT/prompts/$prompt" ]]; then
    pass "Prompt: $prompt"
  else
    fail "Prompt MISSING: $prompt"
  fi
done

# ─── 7. Templates ────────────────────────────────────────────────────────
section "Templates"

REQUIRED_TEMPLATES=(
  "post-review-actions.json"
  "recap-visual.html"
  "recap-markdown.md"
  "robust-plan.md"
)

for tmpl in "${REQUIRED_TEMPLATES[@]}"; do
  if [[ -f "$PI_AGENT/templates/$tmpl" ]]; then
    pass "Template: $tmpl"
  else
    fail "Template MISSING: $tmpl"
  fi
done

# ─── 8. Schemas ──────────────────────────────────────────────────────────
section "Schemas"

REQUIRED_SCHEMAS=(
  "session-recap-v1.json"
  "connector-matrix-v1.json"
  "helios-handoff-v1.json"
)

for schema in "${REQUIRED_SCHEMAS[@]}"; do
  if [[ -f "$PI_AGENT/schemas/$schema" ]]; then
    pass "Schema: $schema"
  else
    fail "Schema MISSING: $schema"
  fi
done

# ─── 9. Settings.json Validation ─────────────────────────────────────────
section "Settings.json"

if [[ -f "$PI_AGENT/settings.json" ]]; then
  pass "settings.json exists"

  # Check required keys
  python3 -c "
import json, sys
d = json.load(open('$PI_AGENT/settings.json'))
required = ['defaultProvider', 'defaultModel', 'packages', 'extensions', 'skills', 'enableSkillCommands']
missing = [k for k in required if k not in d]
if missing:
    print('MISSING keys: ' + ', '.join(missing))
    sys.exit(1)
pkg_count = len(d.get('packages', []))
ext_count = len(d.get('extensions', []))
print(f'Packages: {pkg_count}, Extensions: {ext_count}')
if pkg_count < 15:
    print(f'LOW package count: {pkg_count} (expected >=15)')
    sys.exit(1)
if ext_count < 8:
    print(f'LOW extension count: {ext_count} (expected >=8)')
    sys.exit(1)
" 2>/dev/null && pass "settings.json has required keys and counts" || fail "settings.json validation failed"
else
  fail "settings.json MISSING"
fi

# ─── 10. MCP Configuration ──────────────────────────────────────────────
section "MCP Configuration"

if [[ -f "$PI_AGENT/mcp.json" ]]; then
  pass "mcp.json exists"

  python3 -c "
import json, sys
d = json.load(open('$PI_AGENT/mcp.json'))
servers = d.get('mcpServers', {})
required = ['memgraph', 'github']
missing = [s for s in required if s not in servers]
if missing:
    print('MISSING MCP servers: ' + ', '.join(missing))
    sys.exit(1)
print(f'MCP servers: {len(servers)} ({chr(44).join(servers.keys())})')
" 2>/dev/null && pass "MCP servers configured" || fail "MCP configuration incomplete"
else
  fail "mcp.json MISSING"
fi

# ─── 11. Memgraph Infrastructure ────────────────────────────────────────
section "Memgraph Infrastructure"

if [[ -f "$PI_AGENT/proxies/memgraph/docker-compose.yml" ]]; then
  pass "docker-compose.yml for Memgraph"
else
  fail "docker-compose.yml for Memgraph MISSING"
fi

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' | grep -q memgraph 2>/dev/null; then
    pass "Memgraph container running"
  else
    warn "Memgraph container not running (Docker available but container not started)"
  fi
else
  warn "Docker not available — Memgraph check skipped (OK in CI)"
fi

# ─── 12. Governance Extension ────────────────────────────────────────────
section "Governance Extension"

if [[ -d "$PI_AGENT/extensions/helios-governance" ]]; then
  pass "Governance extension directory"
  if [[ -d "$PI_AGENT/extensions/helios-governance/node_modules" ]]; then
    pass "Governance node_modules installed"
  else
    warn "Governance node_modules not installed (run npm install)"
  fi
else
  fail "Governance extension MISSING"
fi

# ─── 13. Skill-Graph Infrastructure ─────────────────────────────────────
section "Skill-Graph"

SKILL_GRAPH_SCRIPTS=(
  "skills/skill-graph/scripts/bootstrap-codebases.js"
  "skills/skill-graph/scripts/ingest-episodes.js"
  "skills/skill-graph/scripts/index-codebase-fast.js"
  "skills/skill-graph/scripts/schema.cypher"
  "skills/skill-graph/scripts/package.json"
)

for script in "${SKILL_GRAPH_SCRIPTS[@]}"; do
  if [[ -f "$PI_AGENT/$script" ]]; then
    pass "$(basename "$script")"
  else
    fail "$(basename "$script") MISSING"
  fi
done

# ─── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}✓ Passed: $PASS${RESET}"
echo -e "  ${RED}✗ Failed: $FAIL${RESET}"
echo -e "  ${YELLOW}⚠ Warnings: $WARN${RESET}"
echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ Feature parity verified — all required components present${RESET}"
else
  echo -e "  ${RED}${BOLD}✗ $FAIL feature(s) missing — install is incomplete${RESET}"
fi
echo ""

exit "$FAIL"
