#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Post-Install Verification
# =============================================================================
# Run after install.sh to verify everything is correctly set up.
# Prints a health report card.
# =============================================================================

set -uo pipefail

# ─── Flags ────────────────────────────────────────────────────────────────────
FIX_MODE=false
for arg in "$@"; do
  case "$arg" in
    --fix)  FIX_MODE=true ;;
    --help|-h)
      echo "Usage: bash verify.sh [--fix] [--help]"
      echo ""
      echo "  (no flags)  Run health checks and print a report card."
      echo "  --fix       Auto-repair fixable issues (install missing tools,"
      echo "              start services, create missing files)."
      echo "  --help      Show this help message."
      echo ""
      echo "Examples:"
      echo "  bash ~/helios-team-installer/verify.sh"
      echo "  bash ~/helios-team-installer/verify.sh --fix"
      exit 0
      ;;
  esac
done

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

# ─── Source shared libraries ──────────────────────────────────────────────────
VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$VERIFY_DIR/lib/containers.sh" ]]; then
  source "$VERIFY_DIR/lib/containers.sh"
fi

PASS=0
WARN=0
FAIL=0

# ─── Helpers ──────────────────────────────────────────────────────────────────
check_pass() { echo -e "  ${GREEN}✓${RESET} $*"; ((PASS++)) || true; }
check_warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; ((WARN++)) || true; }
check_fail() { echo -e "  ${RED}✗${RESET} $*"; ((FAIL++)) || true; }
section()    { echo -e "\n  ${BOLD}${CYAN}$*${RESET}"; }

auto_fix() {
  local description="$1"
  local command="$2"
  if [[ "$FIX_MODE" == true ]]; then
    echo -e "    ${CYAN}→ Auto-fixing: $description${RESET}"
    if eval "$command" 2>&1 | tail -3; then
      echo -e "    ${GREEN}→ Fixed!${RESET}"
      return 0
    else
      echo -e "    ${RED}→ Fix failed${RESET}"
      return 1
    fi
  else
    echo -e "    ${DIM}→ Fix: $command${RESET}"
  fi
}

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}  ║    Helios + Pi — Health Report Card      ║${RESET}"
echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── 1. Core Binaries ─────────────────────────────────────────────────────────
section "1. Core Binaries"

if command -v helios &>/dev/null; then
  pi_ver=$(helios --version 2>/dev/null | tail -1 || echo "unknown")
  check_pass "helios binary: $pi_ver ($(which helios))"
else
  check_fail "helios binary not found — run: npm install -g @helios-agent/cli"
  auto_fix 'Install Pi CLI' 'npm install -g @helios-agent/cli'
fi

if command -v helios &>/dev/null; then
  check_pass "helios CLI: $(which helios)"
else
  check_warn "helios CLI not found — run install.sh to add it"
  auto_fix 'Install helios CLI' 'bash ~/helios-team-installer/install.sh'
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
  auto_fix 'Re-run installer' 'bash ~/helios-team-installer/install.sh --update'
fi

# Expected subdirs
for dir in agents skills extensions; do
  if [[ -d "$PI_AGENT_DIR/$dir" ]]; then
    count=$(find "$PI_AGENT_DIR/$dir" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')
    check_pass "~/.pi/agent/$dir/ — $count files"
  else
    check_warn "~/.pi/agent/$dir/ not found"
    auto_fix 'Run helios update' 'helios update'
  fi
done

# ─── 3. Agents ────────────────────────────────────────────────────────────────
section "3. Agents"

if [[ -d "$PI_AGENT_DIR/agents" ]]; then
  agent_count=$(find "$PI_AGENT_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$agent_count" -ge 40 ]]; then
    check_pass "Agents: $agent_count (✓ expect 40+)"
  elif [[ "$agent_count" -ge 20 ]]; then
    check_warn "Agents: $agent_count (expected 40+) — run: helios update"
    auto_fix 'Run helios update' 'helios update'
  else
    check_fail "Agents: $agent_count (expected 40+) — packages may not be installed"
    auto_fix 'Run helios update' 'helios update'
  fi

  # Check critical agents
  for agent in helios-system worker scout planner reviewer verifier; do
    if find "$PI_AGENT_DIR/agents" -name "${agent}.md" 2>/dev/null | grep -q .; then
      check_pass "Agent exists: $agent"
    else
      check_warn "Agent missing: $agent"
      auto_fix 'Run helios update' 'helios update'
    fi
  done
else
  check_fail "~/.pi/agent/agents/ not found"
  auto_fix 'Run helios update' 'helios update'
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
  auto_fix 'Run helios update' 'helios update'
else
  check_fail "No skills found"
  auto_fix 'Run helios update' 'helios update'
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
    auto_fix 'Pull agent repo and update' 'cd ~/.pi/agent && git pull && pi update'
  else
    check_pass "All ${found_exts} required extensions present"
  fi
else
  check_fail "~/.pi/agent/extensions/ not found — run: cd ~/.pi/agent && git pull"
  auto_fix 'Pull agent repo' 'cd ~/.pi/agent && git pull'
fi

# ─── 5b. Git Packages ─────────────────────────────────────────────────────────
section "5b. Git Packages (~/.pi/agent/git/)"

if [[ -d "$PI_AGENT_DIR/git" ]]; then
  pkg_count=$(find "$PI_AGENT_DIR/git" -maxdepth 4 -name "package.json" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$pkg_count" -ge 18 ]]; then
    check_pass "Git packages: $pkg_count installed (✓ expect 18+)"
  elif [[ "$pkg_count" -gt 0 ]]; then
    check_warn "Git packages: $pkg_count installed (expected 18+) — run: helios update"
    auto_fix 'Run helios update' 'helios update'
  else
    check_fail "Git packages: none found — run: helios update"
    auto_fix 'Run helios update' 'helios update'
  fi
else
  check_fail "~/.pi/agent/git/ not found — pi update has not been run"
  auto_fix 'Run helios update' 'helios update'
fi

# Check critical packages individually
critical_pkgs=("pi-interview-tool" "visual-explainer" "pi-design-deck" "pi-subagents" "pi-web-access")
missing_critical=()
for pkg in "${critical_pkgs[@]}"; do
  if [[ ! -d "$PI_AGENT_DIR/git/github.com/sweetcheeks72/$pkg" ]]; then
    missing_critical+=("$pkg")
  fi
done
if [[ ${#missing_critical[@]} -gt 0 ]]; then
  check_warn "Missing critical packages: ${missing_critical[*]} — run: cd ~/.pi/agent && git pull && pi update"
  auto_fix 'Run pi update' 'cd ~/.pi/agent && git pull && pi update'
else
  check_pass "All critical packages present (interview, visual-explainer, design-deck, subagents, web-access)"
fi

# ─── 6. Configuration ─────────────────────────────────────────────────────────
section "6. Configuration"

env_file="$PI_AGENT_DIR/.env"
if [[ -f "$env_file" ]]; then
  check_pass ".env file exists"
  
  # Check for required keys based on provider
  provider=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('defaultProvider','?'))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
    node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.defaultProvider||'?')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
  
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
  auto_fix 'Create .env from template' 'cp ~/helios-team-installer/.env.template ~/.pi/agent/.env && chmod 600 ~/.pi/agent/.env'
fi

if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
  provider=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('defaultProvider','?'))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
    node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.defaultProvider||'?')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
  model=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('defaultModel','?'))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
    node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.defaultModel||'?')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
  pkg_count=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('packages',[])))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
    node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log((d.packages||[]).length)" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
  check_pass "settings.json: provider=$provider, model=$model, packages=$pkg_count"
else
  check_fail "settings.json not found in $PI_AGENT_DIR"
  auto_fix 'Re-run installer' 'bash ~/helios-team-installer/install.sh --update'
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
# Use shared lib (containers.sh) for consistent container resolution.
if command -v docker &>/dev/null; then
  if declare -f is_memgraph_running &>/dev/null && is_memgraph_running 2>/dev/null; then
    mg_running=$(resolve_memgraph_container)
  else
    # Fallback: lib not loaded or not running
    for name in memgraph familiar-graph-1; do
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        mg_running="$name"
        break
      fi
    done
  fi
fi

if [[ -n "$mg_running" ]]; then
  check_pass "Memgraph container running ($mg_running)"

  # Check Bolt connectivity via neo4j-driver
  neo_driver="$PI_AGENT_DIR/skills/skill-graph/scripts/node_modules/neo4j-driver"
  if [[ -d "$neo_driver" ]]; then
    if node -e "const d=require('$neo_driver');const x=d.driver('bolt://localhost:7687',d.auth.basic('memgraph','memgraph'));x.verifyConnectivity().then(()=>{console.log('ok');x.close()}).catch(()=>{process.exit(1)})" 2>/dev/null; then
      check_pass "Bolt connection verified (neo4j-driver → localhost:7687)"
    else
      check_warn "Bolt port open but driver connection failed"
      auto_fix 'Install neo4j-driver' 'cd ~/.pi/agent/skills/skill-graph/scripts && npm install --legacy-peer-deps'
    fi
  elif nc -z 127.0.0.1 7687 2>/dev/null; then
    check_pass "Memgraph Bolt port 7687 reachable"
    check_warn "neo4j-driver not installed — run installer to add it"
    auto_fix 'Install neo4j-driver' 'cd ~/.pi/agent/skills/skill-graph/scripts && npm install --legacy-peer-deps'
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
    auto_fix 'Start Memgraph' 'docker start memgraph 2>/dev/null || (cd ~/.pi/agent/proxies/memgraph && docker compose up -d)'
  else
    check_warn "No container runtime (OrbStack/Docker) — Memgraph unavailable"
  fi
fi

# ─── 8b. Runtime Contract ─────────────────────────────────────────────────────
section "8b. Graph Runtime Contract"

runtime_contract="$PI_AGENT_DIR/runtime/memgraph.env"
if [[ -f "$runtime_contract" ]]; then
  contract_container=$(grep '^MEMGRAPH_CONTAINER=' "$runtime_contract" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
  check_pass "Runtime contract: $runtime_contract (container: ${contract_container:-?})"
  # Validate the container recorded in the contract is actually running
  if [[ -n "$contract_container" ]]; then
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${contract_container}$"; then
      check_pass "Contract container running: $contract_container"
    else
      check_warn "Contract container NOT running: $contract_container"
      echo -e "    ${DIM}→ Self-heal: docker start ${contract_container}${RESET}"
      echo -e "    ${DIM}→ Or re-run: bash ~/helios-team-installer/install.sh${RESET}"
      auto_fix 'Start Memgraph' 'docker start memgraph 2>/dev/null || (cd ~/.pi/agent/proxies/memgraph && docker compose up -d)'
    fi
  fi
else
  check_warn "Runtime contract missing: $runtime_contract"
  echo -e "    ${DIM}→ Self-heal: bash ~/helios-team-installer/install.sh${RESET}"
  auto_fix 'Re-run installer' 'bash ~/helios-team-installer/install.sh --update'
fi

# ─── 8c. Codebase Bootstrap State ─────────────────────────────────────────────
section "8c. Codebase Bootstrap State"

bootstrap_dir="$PI_AGENT_DIR/state/codebase-bootstrap"

# Helper: check bootstrap state for a given target path
check_bootstrap_target() {
  local target_path="$1"
  local label="$2"
  local status_key
  status_key=$(python3 -c "import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])" "$target_path" 2>/dev/null || \
    node -e "const c=require('crypto');console.log(c.createHash('sha256').update(process.argv[1]).digest('hex').slice(0,16))" -- "$target_path" 2>/dev/null || echo "")
  if [[ -z "$status_key" ]]; then
    check_warn "$label — cannot compute status key (python3/node required)"
    return
  fi
  local status_file="$bootstrap_dir/${status_key}.json"
  if [[ -f "$status_file" ]]; then
    local bs_state bs_error bs_indexed bs_chunks
    bs_state=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('state','?'))" "$status_file" 2>/dev/null || \
      node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.state||'?')" -- "$status_file" 2>/dev/null || echo "?")
    bs_error=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('error') or '')" "$status_file" 2>/dev/null || \
      node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.error||'')" -- "$status_file" 2>/dev/null || echo "")
    bs_indexed=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('indexedFiles',0))" "$status_file" 2>/dev/null || \
      node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.indexedFiles||0)" -- "$status_file" 2>/dev/null || echo "0")
    bs_chunks=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('totalChunks',0))" "$status_file" 2>/dev/null || \
      node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(d.totalChunks||0)" -- "$status_file" 2>/dev/null || echo "0")
    case "$bs_state" in
      complete)
        check_pass "$label — bootstrap complete (${bs_indexed} files, ${bs_chunks} chunks)"
        ;;
      running)
        check_warn "$label — bootstrap in progress"
        echo -e "    ${DIM}→ Bootstrap is currently running. Check: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
        ;;
      queued)
        check_warn "$label — bootstrap queued (not yet started)"
        echo -e "    ${DIM}→ Self-heal: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
        auto_fix 'Run bootstrap' "node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js"
        ;;
      waiting_for_memgraph)
        check_warn "$label — bootstrap waiting for Memgraph${bs_error:+ ($bs_error)}"
        echo -e "    ${DIM}→ Start Memgraph then: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
        auto_fix 'Start Memgraph' 'docker start memgraph 2>/dev/null || (cd ~/.pi/agent/proxies/memgraph && docker compose up -d)'
        ;;
      waiting_for_ollama_model)
        check_warn "$label — bootstrap waiting for Ollama model${bs_error:+ ($bs_error)}"
        echo -e "    ${DIM}→ Run: ollama pull nomic-embed-text  then: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
        auto_fix 'Pull embedding model' 'ollama pull nomic-embed-text'
        ;;
      failed)
        check_fail "$label — bootstrap FAILED${bs_error:+: $bs_error}"
        echo -e "    ${DIM}→ Retry: node $PI_AGENT_DIR/skills/skill-graph/scripts/index-codebase.js ${target_path} --incremental${RESET}"
        auto_fix 'Retry bootstrap' "node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js"
        ;;
      *)
        check_warn "$label — unknown bootstrap state: $bs_state"
        echo -e "    ${DIM}→ Self-heal: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
        auto_fix 'Run bootstrap' "node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js"
        ;;
    esac
  else
    check_warn "$label — no bootstrap record found"
    echo -e "    ${DIM}→ Self-heal: node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js${RESET}"
    auto_fix 'Run bootstrap' "node $PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js"
  fi
}

if [[ -d "$bootstrap_dir" ]]; then
  check_pass "Bootstrap state dir: $bootstrap_dir"
else
  check_warn "Bootstrap state dir missing: $bootstrap_dir"
  echo -e "    ${DIM}→ Self-heal: bash ~/helios-team-installer/install.sh${RESET}"
  auto_fix 'Re-run installer' 'bash ~/helios-team-installer/install.sh --update'
fi

# Always check ~/.pi/agent bootstrap state
check_bootstrap_target "$PI_AGENT_DIR" "~/.pi/agent"

# Check current repo when it's a git repo and != PI_AGENT_DIR
current_dir="$(pwd)"
resolved_agent_dir="$(cd "$PI_AGENT_DIR" 2>/dev/null && pwd || echo "$PI_AGENT_DIR")"
if [[ "$current_dir" != "$resolved_agent_dir" ]] && [[ -d "$current_dir/.git" ]]; then
  check_bootstrap_target "$current_dir" "$(basename "$current_dir") (CWD)"
fi

# ─── 9. Ollama ────────────────────────────────────────────────────────────────
section "9. Ollama (Embeddings)"

if command -v ollama &>/dev/null; then
  check_pass "Ollama installed"
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    check_pass "Ollama running"
    for model in nomic-embed-text granite-embedding; do
      if ollama list 2>/dev/null | grep -q "$model"; then
        check_pass "$model model"
      else
        check_warn "$model not pulled — run: ollama pull $model"
        auto_fix "Pull $model model" "ollama pull $model"
      fi
    done
  else
    check_warn "Ollama not running — start with: ollama serve"
    auto_fix 'Start Ollama' 'nohup ollama serve >/dev/null 2>&1 & disown; sleep 3'
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
  auto_fix 'Install neo4j-driver' 'cd ~/.pi/agent/skills/skill-graph/scripts && npm install --legacy-peer-deps'
fi

if [[ -f "$sg_dir/ingest-episodes.js" ]]; then
  check_pass "ingest-episodes.js present"
else
  check_warn "ingest-episodes.js missing — pull latest helios-agent"
  auto_fix 'Run helios update' 'helios update'
fi

if [[ -f "$sg_dir/memory-recall.js" ]]; then
  check_pass "memory-recall.js present"
else
  check_warn "memory-recall.js missing — pull latest helios-agent"
  auto_fix 'Run helios update' 'helios update'
fi

# ─── 11. MCP Toolchain ───────────────────────────────────────────────────────
section "11. MCP Toolchain"

if command -v uvx &>/dev/null; then
  check_pass "uvx $(uvx --version 2>/dev/null | head -1)"
else
  check_warn "uvx not found — mcp-memgraph server unavailable"
fi

if [[ -f "$PI_AGENT_DIR/mcp.json" ]]; then
  mcp_count=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d.get('mcpServers',{})))" "$PI_AGENT_DIR/mcp.json" 2>/dev/null || \
    node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); console.log(Object.keys(d.mcpServers||{}).length)" -- "$PI_AGENT_DIR/mcp.json" 2>/dev/null || echo "0")
  check_pass "mcp.json: $mcp_count server(s) configured"
  # Verify specific servers
  for server in memgraph github figma-remote; do
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert sys.argv[2] in d.get('mcpServers',{})" "$PI_AGENT_DIR/mcp.json" "$server" 2>/dev/null || \
       node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.exit((process.argv[2] in (d.mcpServers||{}))?0:1)" -- "$PI_AGENT_DIR/mcp.json" "$server" 2>/dev/null; then
      check_pass "  → $server server configured"
    else
      check_warn "  → $server server missing from mcp.json"
    fi
  done
else
  check_warn "mcp.json not found"
  auto_fix 'Re-run installer' 'bash ~/helios-team-installer/install.sh --update'
fi

# ─── 12. Git Hooks ───────────────────────────────────────────────────────────
section "12. Git Hooks & Allowlists"

if [[ -f "$PI_AGENT_DIR/.git/hooks/pre-push" ]]; then
  check_pass "pre-push hook installed"
else
  check_warn "pre-push hook missing — agents can push to main unchecked"
  auto_fix 'Install pre-push hook' 'cp ~/.pi/agent/hooks/pre-push ~/.pi/agent/.git/hooks/pre-push && chmod +x ~/.pi/agent/.git/hooks/pre-push'
fi

if [[ -f "$PI_AGENT_DIR/dep-allowlist.json" ]]; then
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert 'neo4j-driver' in d.get('packages',[])" "$PI_AGENT_DIR/dep-allowlist.json" 2>/dev/null || \
     node -e "const d=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); process.exit((d.packages||[]).includes('neo4j-driver')?0:1)" -- "$PI_AGENT_DIR/dep-allowlist.json" 2>/dev/null; then
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
    auto_fix 'Install governance deps' 'cd ~/.pi/agent/extensions/helios-governance && npm install'
  fi
else
  check_warn "Governance extension not found"
  auto_fix 'Run helios update' 'helios update'
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

if [[ "$FIX_MODE" == true ]]; then
  echo ""
  echo -e "  ${CYAN}  ℹ If fixes were applied, re-run:${RESET}"
  echo -e "  ${CYAN}    bash ~/helios-team-installer/verify.sh${RESET}"
fi
echo ""

exit "$FAIL"
