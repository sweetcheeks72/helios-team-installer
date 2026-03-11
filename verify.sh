#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Post-Install Verification
# =============================================================================
# Run after install.sh to verify everything is correctly set up.
# Prints a health report card.
# =============================================================================

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PI_AGENT_DIR="$HOME/.pi/agent"
FAMILIAR_DIR="$HOME/.familiar"

PASS=0
WARN=0
FAIL=0

# ─── Helpers ──────────────────────────────────────────────────────────────────
check_pass() { echo -e "  ${GREEN}✓${RESET} $*"; ((PASS++)) || true; }
check_warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; ((WARN++)) || true; }
check_fail() { echo -e "  ${RED}✗${RESET} $*"; ((FAIL++)) || true; }
section()    { echo -e "\n  ${BOLD}${CYAN}$*${RESET}"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}  ║    Helios + Pi — Health Report Card      ║${RESET}"
echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── 1. Core Binaries ─────────────────────────────────────────────────────────
section "1. Core Binaries"

if command -v pi &>/dev/null; then
  pi_ver=$(pi --version 2>/dev/null | tail -1 || echo "unknown")
  check_pass "pi binary: $pi_ver ($(which pi))"
else
  check_fail "pi binary not found — run: npm install -g @mariozechner/pi-coding-agent"
fi

if command -v helios &>/dev/null; then
  check_pass "helios CLI: $(which helios)"
else
  check_warn "helios CLI not found — run install.sh to add it"
fi

if command -v node &>/dev/null; then
  check_pass "node: $(node -v)"
else
  check_fail "node not found"
fi

if command -v git &>/dev/null; then
  check_pass "git: $(git --version | awk '{print $3}')"
else
  check_fail "git not found"
fi

# ─── 2. Agent Directory ───────────────────────────────────────────────────────
section "2. Agent Directory (~/.pi/agent/)"

if [[ -d "$PI_AGENT_DIR" ]]; then
  check_pass "~/.pi/agent/ exists"
  if [[ -L "$PI_AGENT_DIR" ]]; then
    check_pass "~/.pi/agent/ is a symlink → $(readlink "$PI_AGENT_DIR")"
  elif [[ -d "$PI_AGENT_DIR/.git" ]]; then
    git_branch=$(git -C "$PI_AGENT_DIR" branch --show-current 2>/dev/null || echo "?")
    git_commit=$(git -C "$PI_AGENT_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
    check_pass "git repo: branch=$git_branch commit=$git_commit"
  fi
else
  check_fail "~/.pi/agent/ not found — run install.sh"
fi

# Expected subdirs
for dir in agents skills extensions; do
  if [[ -d "$PI_AGENT_DIR/$dir" ]]; then
    count=$(find "$PI_AGENT_DIR/$dir" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')
    check_pass "~/.pi/agent/$dir/ — $count files"
  else
    check_warn "~/.pi/agent/$dir/ not found"
  fi
done

# ─── 3. Agents ────────────────────────────────────────────────────────────────
section "3. Agents"

if [[ -d "$PI_AGENT_DIR/agents" ]]; then
  agent_count=$(find "$PI_AGENT_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$agent_count" -ge 40 ]]; then
    check_pass "Agents: $agent_count (✓ expect 40+)"
  elif [[ "$agent_count" -ge 20 ]]; then
    check_warn "Agents: $agent_count (expected 40+) — run: pi update"
  else
    check_fail "Agents: $agent_count (expected 40+) — packages may not be installed"
  fi

  # Check critical agents
  for agent in helios-system worker scout planner reviewer verifier; do
    if find "$PI_AGENT_DIR/agents" -name "${agent}.md" 2>/dev/null | grep -q .; then
      check_pass "Agent exists: $agent"
    else
      check_warn "Agent missing: $agent"
    fi
  done
else
  check_fail "~/.pi/agent/agents/ not found"
fi

# ─── 4. Skills ────────────────────────────────────────────────────────────────
section "4. Skills"

skill_count=0
if [[ -d "$PI_AGENT_DIR/skills" ]]; then
  pi_skills=$(find "$PI_AGENT_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  skill_count=$((skill_count + pi_skills))
  check_pass "Pi skills: $pi_skills"
fi

if [[ -d "$FAMILIAR_DIR/skills" ]]; then
  fam_skills=$(find "$FAMILIAR_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  skill_count=$((skill_count + fam_skills))
  check_pass "Familiar skills: $fam_skills"
else
  check_warn "Familiar skills not found (~/.familiar/skills/) — optional"
fi

if [[ "$skill_count" -ge 13 ]]; then
  check_pass "Total skills: $skill_count (✓ expect 13+)"
elif [[ "$skill_count" -gt 0 ]]; then
  check_warn "Total skills: $skill_count (expected 13+)"
else
  check_fail "No skills found"
fi

# ─── 5. Extensions ────────────────────────────────────────────────────────────
section "5. Extensions"

if [[ -d "$PI_AGENT_DIR/extensions" ]]; then
  # Check each required extension by name
  required_exts=(
    "helios-governance:dir"
    "auto-update.ts:file"
    "codebase-index.ts:file"
    "mcp-startup-visibility.ts:file"
    "subagent-inline-enforce.ts:file"
    "subagent-mesh.ts:file"
  )
  missing_exts=()
  found_exts=0
  for entry in "${required_exts[@]}"; do
    ext_name="${entry%%:*}"
    ext_type="${entry##*:}"
    ext_path="$PI_AGENT_DIR/extensions/$ext_name"
    if [[ "$ext_type" == "dir" && -d "$ext_path" ]] || [[ "$ext_type" == "file" && -f "$ext_path" ]]; then
      check_pass "  Extension: $ext_name"
      ((found_exts++))
    else
      missing_exts+=("$ext_name")
    fi
  done
  if [[ ${#missing_exts[@]} -gt 0 ]]; then
    check_warn "Missing extensions: ${missing_exts[*]} — run: cd ~/.pi/agent && git pull"
  else
    check_pass "All ${found_exts} required extensions present"
  fi
else
  check_fail "~/.pi/agent/extensions/ not found — run: cd ~/.pi/agent && git pull"
fi

# ─── 5b. Git Packages ─────────────────────────────────────────────────────────
section "5b. Git Packages (~/.pi/agent/git/)"

if [[ -d "$PI_AGENT_DIR/git" ]]; then
  pkg_count=$(find "$PI_AGENT_DIR/git" -maxdepth 4 -name "package.json" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$pkg_count" -ge 18 ]]; then
    check_pass "Git packages: $pkg_count installed (✓ expect 18+)"
  elif [[ "$pkg_count" -gt 0 ]]; then
    check_warn "Git packages: $pkg_count installed (expected 18+) — run: pi update"
  else
    check_fail "Git packages: none found — run: pi update"
  fi
else
  check_fail "~/.pi/agent/git/ not found — pi update has not been run"
fi

# Check critical packages individually
critical_pkgs=("pi-interview-tool" "visual-explainer" "pi-design-deck" "pi-subagents" "pi-web-access")
missing_critical=()
for pkg in "${critical_pkgs[@]}"; do
  if [[ ! -d "$PI_AGENT_DIR/git/github.com/nicobailon/$pkg" ]]; then
    missing_critical+=("$pkg")
  fi
done
if [[ ${#missing_critical[@]} -gt 0 ]]; then
  check_warn "Missing critical packages: ${missing_critical[*]} — run: cd ~/.pi/agent && git pull && pi update"
else
  check_pass "All critical packages present (interview, visual-explainer, design-deck, subagents, web-access)"
fi

# ─── 6. Configuration ─────────────────────────────────────────────────────────
section "6. Configuration"

env_file="$PI_AGENT_DIR/.env"
if [[ -f "$env_file" ]]; then
  check_pass ".env file exists"
  
  # Check for required keys based on provider
  provider=$(python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/settings.json')); print(d.get('defaultProvider','?'))" 2>/dev/null || echo "?")
  
  check_key() {
    local key="$1"
    local label="${2:-$1}"
    local val
    val=$(grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- || echo "")
    if [[ -n "$val" ]]; then
      check_pass "$label: set (${#val} chars)"
    else
      check_warn "$label: NOT SET — add to ~/.pi/agent/.env"
    fi
  }

  case "$provider" in
    anthropic)         check_key "ANTHROPIC_API_KEY" "Anthropic API key" ;;
    amazon-bedrock)    check_key "AWS_ACCESS_KEY_ID" "AWS Access Key ID"
                       check_key "AWS_SECRET_ACCESS_KEY" "AWS Secret Access Key" ;;
    openai)            check_key "OPENAI_API_KEY" "OpenAI API key" ;;
    *)                 check_warn "Could not determine provider from settings.json" ;;
  esac

  check_key "GITHUB_TOKEN" "GitHub token (recommended)"
else
  check_fail ".env not found at $env_file — run install.sh or create manually"
fi

if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
  provider=$(python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/settings.json')); print(d.get('defaultProvider','?'))" 2>/dev/null || echo "?")
  model=$(python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/settings.json')); print(d.get('defaultModel','?'))" 2>/dev/null || echo "?")
  pkg_count=$(python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/settings.json')); print(len(d.get('packages',[])))" 2>/dev/null || echo "?")
  check_pass "settings.json: provider=$provider, model=$model, packages=$pkg_count"
else
  check_fail "settings.json not found in $PI_AGENT_DIR"
fi

# ─── 7. MCP Servers ───────────────────────────────────────────────────────────
section "7. MCP Servers"

# GitHub MCP
if command -v npx &>/dev/null; then
  if npm list -g @modelcontextprotocol/server-github &>/dev/null 2>&1; then
    check_pass "GitHub MCP server installed"
  else
    check_warn "GitHub MCP server not installed (optional)"
  fi
fi

# Figma MCP
figma_token=$(grep "^FIGMA_MCP_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2- || echo "")
if [[ -n "$figma_token" ]]; then
  check_pass "Figma MCP token configured"
else
  check_warn "Figma MCP token not set (optional)"
fi

# ─── 8. Memgraph ──────────────────────────────────────────────────────────────
section "8. Memgraph"

mg_running=""
for name in helios-memgraph familiar-graph-1; do
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    mg_running="$name"
    break
  fi
done

if [[ -n "$mg_running" ]]; then
  check_pass "Memgraph container running ($mg_running)"

  # Check Bolt connectivity via neo4j-driver
  neo_driver="$PI_AGENT_DIR/skills/skill-graph/scripts/node_modules/neo4j-driver"
  if [[ -d "$neo_driver" ]]; then
    if node -e "const d=require('$neo_driver');const x=d.driver('bolt://localhost:7687',d.auth.basic('memgraph','memgraph'));x.verifyConnectivity().then(()=>{console.log('ok');x.close()}).catch(()=>{process.exit(1)})" 2>/dev/null; then
      check_pass "Bolt connection verified (neo4j-driver → localhost:7687)"
    else
      check_warn "Bolt port open but driver connection failed"
    fi
  elif nc -z 127.0.0.1 7687 2>/dev/null; then
    check_pass "Memgraph Bolt port 7687 reachable"
    check_warn "neo4j-driver not installed — run installer to add it"
  fi

  # Memory cap
  mem=$(docker inspect --format '{{.HostConfig.Memory}}' "$mg_running" 2>/dev/null || echo "0")
  if [[ "$mem" != "0" ]]; then
    mem_gb=$((mem / 1073741824))
    check_pass "Memory capped at ${mem_gb}GB"
  else
    check_warn "No memory limit — recommend: docker update --memory 12g $mg_running"
  fi
else
  if command -v docker &>/dev/null; then
    check_warn "Memgraph not running — start with: cd ~/.pi/agent/proxies/memgraph && docker compose up -d"
  else
    check_warn "Docker not installed — Memgraph unavailable"
  fi
fi

# ─── 9. Ollama ────────────────────────────────────────────────────────────────
section "9. Ollama (Embeddings)"

if command -v ollama &>/dev/null; then
  check_pass "Ollama installed"
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    check_pass "Ollama running"
    for model in granite-embedding qwen3-embedding; do
      if ollama list 2>/dev/null | grep -q "$model"; then
        check_pass "$model model"
      else
        check_warn "$model not pulled — run: ollama pull $model"
      fi
    done
  else
    check_warn "Ollama not running — start with: ollama serve"
  fi
else
  check_warn "Ollama not installed — embeddings unavailable (https://ollama.com)"
fi

# ─── 10. HEMA (Episodic Memory) ──────────────────────────────────────────────
section "10. HEMA (Episodic Memory)"

sg_dir="$PI_AGENT_DIR/skills/skill-graph/scripts"
if [[ -d "$sg_dir/node_modules/neo4j-driver" ]]; then
  check_pass "neo4j-driver installed"
else
  check_warn "neo4j-driver missing — run installer to add it"
fi

if [[ -f "$sg_dir/ingest-episodes.js" ]]; then
  check_pass "ingest-episodes.js present"
else
  check_warn "ingest-episodes.js missing — pull latest helios-agent"
fi

if [[ -f "$sg_dir/memory-recall.js" ]]; then
  check_pass "memory-recall.js present"
else
  check_warn "memory-recall.js missing — pull latest helios-agent"
fi

# ─── 11. MCP Toolchain ───────────────────────────────────────────────────────
section "11. MCP Toolchain"

if command -v uvx &>/dev/null; then
  check_pass "uvx $(uvx --version 2>/dev/null | head -1)"
else
  check_warn "uvx not found — mcp-memgraph server unavailable"
fi

if [[ -f "$PI_AGENT_DIR/mcp.json" ]]; then
  mcp_count=$(python3 -c "import json;d=json.load(open('$PI_AGENT_DIR/mcp.json'));print(len(d.get('mcpServers',{})))" 2>/dev/null || echo "0")
  check_pass "mcp.json: $mcp_count server(s) configured"
  # Verify specific servers
  for server in memgraph github figma-remote; do
    if python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/mcp.json')); assert '$server' in d.get('mcpServers',{})" 2>/dev/null; then
      check_pass "  → $server server configured"
    else
      check_warn "  → $server server missing from mcp.json"
    fi
  done
else
  check_warn "mcp.json not found"
fi

# ─── 12. Git Hooks ───────────────────────────────────────────────────────────
section "12. Git Hooks & Allowlists"

if [[ -f "$PI_AGENT_DIR/.git/hooks/pre-push" ]]; then
  check_pass "pre-push hook installed"
else
  check_warn "pre-push hook missing — agents can push to main unchecked"
fi

if [[ -f "$PI_AGENT_DIR/dep-allowlist.json" ]]; then
  if python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/dep-allowlist.json')); assert 'neo4j-driver' in d.get('packages',[])" 2>/dev/null; then
    check_pass "dep-allowlist.json (neo4j-driver allowed)"
  else
    check_warn "dep-allowlist.json missing neo4j-driver entry"
  fi
else
  check_warn "dep-allowlist.json not found"
fi

# ─── 13. Governance Extension ────────────────────────────────────────────────
section "13. Governance Extension"

gov_dir="$PI_AGENT_DIR/extensions/helios-governance"
if [[ -d "$gov_dir" ]]; then
  check_pass "Governance extension present"
  if [[ -d "$gov_dir/node_modules" ]]; then
    check_pass "Governance node_modules installed"
  else
    check_warn "Governance node_modules missing — run: cd $gov_dir && npm install"
  fi
else
  check_warn "Governance extension not found"
fi

# ─── Report Card ──────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${BOLD}  Report Card${RESET}"
echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "    ${GREEN}✓ Passed: $PASS${RESET}"
echo -e "    ${YELLOW}⚠ Warnings: $WARN${RESET}"
echo -e "    ${RED}✗ Failed: $FAIL${RESET}"
echo ""

total=$((PASS + WARN + FAIL))
if [[ "$FAIL" -eq 0 && "$WARN" -le 3 ]]; then
  echo -e "  ${GREEN}${BOLD}  ✓ System healthy — ready to use Pi + Helios!${RESET}"
  echo -e "  ${DIM}  Run: helios${RESET}"
elif [[ "$FAIL" -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}  ⚠ System functional with warnings${RESET}"
  echo -e "  ${DIM}  Optional items are missing — see warnings above${RESET}"
else
  echo -e "  ${RED}${BOLD}  ✗ Setup incomplete — $FAIL check(s) failed${RESET}"
  echo -e "  ${DIM}  Run: bash ~/helios-team-installer/install.sh${RESET}"
fi
echo ""

exit "$FAIL"
