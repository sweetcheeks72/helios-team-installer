#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Team Installer
# =============================================================================
# Installs: Pi CLI, Helios Agent, 20 git packages, extensions, Familiar skills,
# API key setup
# =============================================================================

set -euo pipefail
cleanup() {
  # Kill any leftover spinner
  if [[ -n "${spin_pid:-}" ]] && kill -0 "$spin_pid" 2>/dev/null; then
    kill "$spin_pid" 2>/dev/null || true
    wait "$spin_pid" 2>/dev/null || true
  fi
  # Restore cursor visibility
  printf '\033[?25h'
  echo -e "\n${RED}✗ Installer interrupted. Run again to resume (idempotent).${RESET}"
}
trap cleanup EXIT INT TERM

# ─── Colors & Styles ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}  ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*"; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }
ask()     { echo -en "${MAGENTA}  ? ${RESET}$* "; }

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELIOS_AGENT_REPO="github.com/sweetcheeks72/helios-agent"
FAMILIAR_REPO="github.com/sweetcheeks72/familiar"  # NOTE: verify this URL
PI_AGENT_DIR="$HOME/.pi/agent"
FAMILIAR_DIR="$HOME/.familiar"
LOG_FILE="$INSTALLER_DIR/install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ─── Banner ───────────────────────────────────────────────────────────────────
print_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════════════╗
  ║                                                               ║
  ║    ██╗  ██╗███████╗██╗     ██╗ ██████╗ ███████╗              ║
  ║    ██║  ██║██╔════╝██║     ██║██╔═══██╗██╔════╝              ║
  ║    ███████║█████╗  ██║     ██║██║   ██║███████╗              ║
  ║    ██╔══██║██╔══╝  ██║     ██║██║   ██║╚════██║              ║
  ║    ██║  ██║███████╗███████╗██║╚██████╔╝███████║              ║
  ║    ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚══════╝              ║
  ║                                                               ║
  ║          Team Installer  •  Pi + Helios Orchestrator          ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${RESET}"
  echo -e "  ${DIM}Log: $LOG_FILE${RESET}\n"
}

# ─── Progress Spinner ─────────────────────────────────────────────────────────
spin_pid=""
start_spinner() {
  local msg="${1:-Working...}"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  printf '\033[?25l'
  while true; do
    echo -ne "  ${CYAN}${frames[$i]}${RESET}  ${msg}\r"
    i=$(( (i+1) % ${#frames[@]} ))
    sleep 0.1
  done &
  spin_pid=$!
  disown "$spin_pid" 2>/dev/null || true
}

stop_spinner() {
  if [[ -n "$spin_pid" ]] && kill -0 "$spin_pid" 2>/dev/null; then
    kill "$spin_pid" 2>/dev/null || true
    wait "$spin_pid" 2>/dev/null || true
    spin_pid=""
  fi
  echo -ne "\r\033[K"
  printf '\033[?25h'
}

run_with_spinner() {
  local msg="$1"; shift
  start_spinner "$msg"
  if "$@" >> "$LOG_FILE" 2>&1; then
    stop_spinner
    success "$msg"
    return 0
  else
    stop_spinner
    error "$msg — see $LOG_FILE for details"
    return 1
  fi
}

# ─── Prerequisite Checks ──────────────────────────────────────────────────────
check_prerequisites() {
  step "Checking prerequisites"

  local missing=()

  # Node.js 18+
  if command -v node &>/dev/null; then
    local node_ver
    node_ver=$(node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null && node -e "console.log(process.version)" 2>/dev/null || echo "old")
    if node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null; then
      success "Node.js $(node -v) ✓"
    else
      error "Node.js 18+ required (found: $(node -v))"
      missing+=("node18+")
    fi
  else
    error "Node.js not found"
    missing+=("node")
  fi

  # npm
  if command -v npm &>/dev/null; then
    success "npm $(npm -v) ✓"
  else
    error "npm not found"
    missing+=("npm")
  fi

  # git
  if command -v git &>/dev/null; then
    success "git $(git --version | awk '{print $3}') ✓"
  else
    error "git not found"
    missing+=("git")
  fi

  # curl
  if command -v curl &>/dev/null; then
    success "curl ✓"
  else
    warn "curl not found — some features may be limited"
  fi

  # python3 (required for JSON merging)
  if command -v python3 &>/dev/null; then
    success "python3 $(python3 --version 2>/dev/null | awk '{print $2}') ✓"
  else
    error "python3 not found — required for configuration"
    echo -e "    ${DIM}macOS: xcode-select --install${RESET}"
    echo -e "    ${DIM}Linux: apt install python3 / brew install python3${RESET}"
    missing+=("python3")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    error "Missing required prerequisites: ${missing[*]}"
    echo ""
    echo -e "  ${BOLD}Install guide:${RESET}"
    echo -e "  • Node.js 18+: https://nodejs.org or ${DIM}brew install node${RESET}"
    echo -e "  • git: ${DIM}brew install git${RESET} or ${DIM}apt install git${RESET}"
    exit 1
  fi
}

# ─── Pi Installation ──────────────────────────────────────────────────────────
install_pi() {
  step "Pi CLI"

  if command -v pi &>/dev/null; then
    local pi_ver
    pi_ver=$(pi --version 2>/dev/null | head -1 || echo "unknown")
    success "Pi already installed: $pi_ver"
    PI_INSTALLED=true
    return 0
  fi

  info "Pi not found — installing via npm..."
  
  # Pre-flight: fix npm cache permissions (common macOS issue when npm was run with sudo)
  if [[ -d "$HOME/.npm" ]]; then
    if ! npm cache verify >> "$LOG_FILE" 2>&1; then
      warn "npm cache issue detected — repairing..."
      sudo chown -R "$(whoami)" "$HOME/.npm" 2>/dev/null || true
      npm cache clean --force >> "$LOG_FILE" 2>&1 || true
    fi
  fi
  
  if run_with_spinner "Installing Pi CLI (@mariozechner/pi-coding-agent)" \
      npm install -g @mariozechner/pi-coding-agent; then
    PI_INSTALLED=true
    success "Pi installed: $(pi --version 2>/dev/null | tail -1 || echo 'ok')"
  else
    # Retry with full cache nuke
    warn "First attempt failed — clearing npm cache and retrying..."
    sudo chown -R "$(whoami)" "$HOME/.npm" 2>/dev/null || true
    npm cache clean --force >> "$LOG_FILE" 2>&1 || true
    
    if run_with_spinner "Retrying Pi CLI install" \
        npm install -g @mariozechner/pi-coding-agent; then
      PI_INSTALLED=true
      success "Pi installed on retry: $(pi --version 2>/dev/null | tail -1 || echo 'ok')"
    else
      error "Failed to install Pi CLI."
      echo ""
      echo -e "  ${BOLD}Manual fix:${RESET}"
      echo -e "    ${DIM}sudo chown -R \$(whoami) ~/.npm${RESET}"
      echo -e "    ${DIM}npm cache clean --force${RESET}"
      echo -e "    ${DIM}npm install -g @mariozechner/pi-coding-agent${RESET}"
      echo -e "    Then re-run: ${DIM}bash $INSTALLER_DIR/install.sh${RESET}"
      exit 1
    fi
  fi
}

# ─── Helios Agent Repo ────────────────────────────────────────────────────────
setup_helios_agent() {
  step "Helios Agent (~/.pi/agent/)"

  if [[ -d "$PI_AGENT_DIR" ]]; then
    if [[ -d "$PI_AGENT_DIR/.git" ]]; then
      info "~/.pi/agent/ already exists (git repo) — pulling latest"
      run_with_spinner "Updating helios-agent" \
        git -C "$PI_AGENT_DIR" pull --rebase --autostash || warn "Could not pull — continuing with existing version"
      return 0
    elif [[ -L "$PI_AGENT_DIR" ]]; then
      info "~/.pi/agent/ is a symlink to: $(readlink "$PI_AGENT_DIR")"
      return 0
    else
      warn "~/.pi/agent/ exists but is not a git repo — backing up and re-cloning"
      mv "$PI_AGENT_DIR" "${PI_AGENT_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
  fi

  mkdir -p "$HOME/.pi"
  run_with_spinner "Cloning helios-agent → ~/.pi/agent/" \
    git clone "https://$HELIOS_AGENT_REPO.git" "$PI_AGENT_DIR"
  success "Helios agent cloned to $PI_AGENT_DIR"
}

# ─── Helios CLI Command ──────────────────────────────────────────────────────
install_helios_cli() {
  step "Helios CLI"

  local helios_bin="$PI_AGENT_DIR/bin/helios"
  if [[ ! -f "$helios_bin" ]]; then
    info "bin/helios not found in agent repo — skipping CLI install"
    return 0
  fi

  chmod +x "$helios_bin"
  local installed=false

  # Try /usr/local/bin first
  if [[ -w /usr/local/bin ]]; then
    ln -sfn "$helios_bin" /usr/local/bin/helios
    success "helios → /usr/local/bin/helios"
    installed=true
  elif sudo -n true 2>/dev/null; then
    sudo ln -sfn "$helios_bin" /usr/local/bin/helios
    success "helios → /usr/local/bin/helios"
    installed=true
  fi

  # Also install to ~/.local/bin
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$helios_bin" "$HOME/.local/bin/helios"
  if [[ "$installed" == false ]]; then
    success "helios → ~/.local/bin/helios"
    if ! echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin"; then
      warn "Add to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
  fi

  success "Type 'helios' to launch (branded pi wrapper)"
}

# ─── Pi Update (Install Packages) ─────────────────────────────────────────────
install_packages() {
  step "Installing Pi packages (pi update)"
  info "This installs all 20 git packages — may take 2-3 minutes"

  if [[ ! -f "$PI_AGENT_DIR/settings.json" ]]; then
    warn "settings.json not found — provider selection may have failed. Using Anthropic default."
    cp "$INSTALLER_DIR/provider-configs/anthropic.json" "$PI_AGENT_DIR/settings.json"
  fi

  run_with_spinner "Running pi update (installing packages)" \
    pi update || {
    warn "pi update had issues — packages may need manual installation"
    return 0
  }
  success "Pi packages installed"
}

# ─── Provider Selection ───────────────────────────────────────────────────────
select_provider() {
  step "AI Provider Selection"

  echo ""
  echo -e "  ${BOLD}Choose your primary AI provider:${RESET}"
  echo ""
  echo -e "  ${CYAN}1)${RESET} ${BOLD}Anthropic Direct${RESET}        (claude-sonnet-4-5, claude-opus-4)"
  echo -e "     ${DIM}Best for: Getting started quickly. Pay-per-use API.${RESET}"
  echo ""
  echo -e "  ${CYAN}2)${RESET} ${BOLD}Amazon Bedrock${RESET}           (claude-opus-4, claude-sonnet-4-5 via AWS)"
  echo -e "     ${DIM}Best for: Enterprise, existing AWS accounts, regional compliance.${RESET}"
  echo ""
  echo -e "  ${CYAN}3)${RESET} ${BOLD}OpenAI${RESET}                   (gpt-5.2, gpt-4o)"
  echo -e "     ${DIM}Best for: OpenAI preference, GPT models.${RESET}"
  echo ""
  ask "Selection [1-3] (default: 1):"
  read -r provider_choice
  provider_choice="${provider_choice:-1}"

  case "$provider_choice" in
    1)
      SELECTED_PROVIDER="anthropic"
      SELECTED_MODEL="claude-sonnet-4-5-20250514"
      PROVIDER_CONFIG="$INSTALLER_DIR/provider-configs/anthropic.json"
      success "Selected: Anthropic Direct (claude-sonnet-4-5)"
      ;;
    2)
      SELECTED_PROVIDER="amazon-bedrock"
      SELECTED_MODEL="us.anthropic.claude-opus-4-6-v1"
      PROVIDER_CONFIG="$INSTALLER_DIR/provider-configs/bedrock.json"
      success "Selected: Amazon Bedrock (claude-opus-4)"
      warn "Make sure AWS CLI is configured: aws configure"
      ;;
    3)
      SELECTED_PROVIDER="openai"
      SELECTED_MODEL="gpt-5.2"
      PROVIDER_CONFIG="$INSTALLER_DIR/provider-configs/openai.json"
      success "Selected: OpenAI (gpt-5.2)"
      ;;
    *)
      warn "Invalid selection — defaulting to Anthropic"
      SELECTED_PROVIDER="anthropic"
      SELECTED_MODEL="claude-sonnet-4-5-20250514"
      PROVIDER_CONFIG="$INSTALLER_DIR/provider-configs/anthropic.json"
      ;;
  esac

  # MERGE provider config into existing settings.json (don't overwrite!)
  if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    python3 -c "
import json, sys

with open('$PI_AGENT_DIR/settings.json') as f:
    existing = json.load(f)
with open('$PROVIDER_CONFIG') as f:
    template = json.load(f)

# Only merge provider-specific fields
existing['defaultProvider'] = template['defaultProvider']
existing['defaultModel'] = template['defaultModel']
existing['assistantName'] = template.get('assistantName', existing.get('assistantName', 'Helios'))

# Merge enabledModels: ADD template models to existing, don't replace
template_models = set(template.get('enabledModels', []))
existing_models = set(existing.get('enabledModels', []))
existing['enabledModels'] = sorted(list(existing_models | template_models))

# Helper to normalize package/skill identifiers for comparison
def pkg_key(p):
    if isinstance(p, str):
        return p
    if isinstance(p, dict):
        return p.get('name', p.get('source', str(p)))
    return str(p)

# Merge skills: add any from template not already present (additive union)
template_skills = template.get('skills', [])
existing_skills = existing.get('skills', [])
existing_skill_keys = set(pkg_key(s) for s in existing_skills)
for s in template_skills:
    if pkg_key(s) not in existing_skill_keys:
        existing_skills.append(s)
existing['skills'] = existing_skills

# Merge packages: add any from template not already present (additive union)
template_pkgs = template.get('packages', [])
existing_pkgs = existing.get('packages', [])
existing_pkg_keys = set(pkg_key(p) for p in existing_pkgs)
for p in template_pkgs:
    if pkg_key(p) not in existing_pkg_keys:
        existing_pkgs.append(p)
existing['packages'] = existing_pkgs

# Merge extensions: add any from template not already present (additive union)
template_exts = template.get('extensions', [])
existing_exts = existing.get('extensions', [])
existing_ext_keys = set(pkg_key(e) for e in existing_exts)
for e in template_exts:
    if pkg_key(e) not in existing_ext_keys:
        existing_exts.append(e)
existing['extensions'] = existing_exts

# Ensure other required keys
existing.setdefault('enableSkillCommands', True)
existing.setdefault('hideThinkingBlock', False)
existing['quietStartup'] = existing.get('quietStartup', template.get('quietStartup', True))

with open('$PI_AGENT_DIR/settings.json', 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')

print('Merged provider config into existing settings.json')
" || {
      error "python3 JSON merge failed — settings.json NOT overwritten"
      warn "Run 'python3 --version' to check your Python installation"
      warn "You may need to manually edit ~/.pi/agent/settings.json"
    }
  else
    # No existing settings.json — use template as-is
    cp "$PROVIDER_CONFIG" "$PI_AGENT_DIR/settings.json"
  fi
  success "settings.json configured for $SELECTED_PROVIDER"
}

# ─── Skill-Graph Dependencies ─────────────────────────────────────────────────
install_skill_deps() {
  step "Skill-Graph Dependencies"

  local sg_dir="$PI_AGENT_DIR/skills/skill-graph/scripts"
  if [[ ! -d "$sg_dir" ]] || [[ ! -f "$sg_dir/package.json" ]]; then
    info "skill-graph/scripts not found — skipping"
    return 0
  fi

  if [[ -d "$sg_dir/node_modules/neo4j-driver" ]] && [[ -d "$sg_dir/node_modules/tree-sitter" ]]; then
    success "neo4j-driver + tree-sitter already installed"
  else
    run_with_spinner "Installing neo4j-driver + tree-sitter" \
      bash -c "cd '$sg_dir' && npm install --legacy-peer-deps --no-audit --no-fund" || \
      warn "Dependency install failed — HEMA memory and code parsing will be limited"
  fi
}

# ─── Governance Extension Dependencies ────────────────────────────────────────
install_governance_deps() {
  step "Governance Extension Dependencies"

  local gov_dir="$PI_AGENT_DIR/extensions/helios-governance"
  if [[ ! -d "$gov_dir" ]] || [[ ! -f "$gov_dir/tsconfig.json" ]]; then
    info "Governance extension not found — skipping"
    return 0
  fi

  if [[ -d "$gov_dir/node_modules" ]]; then
    success "Governance deps already installed"
  else
    run_with_spinner "Installing governance extension deps" \
      bash -c "cd '$gov_dir' && npm install --no-audit --no-fund" || \
      warn "Governance deps failed — extension may not load"
  fi
}

# ─── Git Hooks ────────────────────────────────────────────────────────────────
install_git_hooks() {
  step "Git Hooks"

  local hooks_dir="$PI_AGENT_DIR/.git/hooks"
  if [[ ! -d "$hooks_dir" ]]; then
    info "No .git/hooks directory — skipping"
    return 0
  fi

  # Pre-push hook (blocks accidental pushes to main from agents)
  local hook_src="$PI_AGENT_DIR/hooks/pre-push"
  if [[ -f "$hook_src" ]]; then
    cp "$hook_src" "$hooks_dir/pre-push"
    chmod +x "$hooks_dir/pre-push"
    success "pre-push hook installed"
  elif [[ -f "$hooks_dir/pre-push" ]]; then
    success "pre-push hook already present"
  else
    # Create a minimal pre-push hook
    cat > "$hooks_dir/pre-push" << 'HOOK'
#!/bin/bash
# Helios pre-push hook: block agent pushes to protected branches
remote="$1"
while read local_ref local_sha remote_ref remote_sha; do
  if echo "$remote_ref" | grep -qE "refs/heads/(main|master)$"; then
    if [ -n "$PI_AGENT" ] || [ -n "$HELIOS_WORKER" ]; then
      echo "🚫 BLOCKED: Push to protected branch is not allowed."
      echo "   Use a feature branch and open a PR instead."
      echo "   To override: git push --no-verify"
      exit 1
    fi
  fi
done
HOOK
    chmod +x "$hooks_dir/pre-push"
    success "pre-push hook created"
  fi
}

# ─── Dep Allowlist ────────────────────────────────────────────────────────────
setup_dep_allowlist() {
  step "Dependency Allowlist"

  local allowlist="$PI_AGENT_DIR/dep-allowlist.json"
  if [[ -f "$allowlist" ]]; then
    # Verify it contains neo4j-driver
    if python3 -c "
import json
with open('$allowlist') as f:
    data = json.load(f)
pkgs = data.get('packages', [])
if 'neo4j-driver' not in pkgs:
    pkgs.append('neo4j-driver')
    data['packages'] = pkgs
    with open('$allowlist', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('added')
else:
    print('ok')
" 2>/dev/null; then
      success "dep-allowlist.json verified"
    else
      warn "Could not verify dep-allowlist.json"
    fi
  else
    echo '{"packages": ["neo4j-driver", "neo4j"]}' > "$allowlist"
    success "dep-allowlist.json created"
  fi
}

# ─── Memgraph (Knowledge Graph) ──────────────────────────────────────────────
setup_memgraph() {
  step "Memgraph (Knowledge Graph)"

  # Check Docker
  if ! command -v docker &>/dev/null; then
    warn "Docker not installed — Memgraph will be skipped"
    info "Install Docker Desktop: https://docs.docker.com/get-docker"
    info "Then re-run the installer to set up Memgraph"
    return 0
  fi

  if ! docker info &>/dev/null 2>&1; then
    warn "Docker is installed but not running — start Docker Desktop"
    info "Then re-run the installer to set up Memgraph"
    return 0
  fi

  # Check if a Memgraph container already exists
  local mg_container=""
  for name in helios-memgraph familiar-graph-1; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$" 2>/dev/null; then
      mg_container="$name"
      break
    fi
  done

  if [[ -n "$mg_container" ]]; then
    # Already exists — make sure it's running
    if docker ps --format '{{.Names}}' | grep -q "^${mg_container}$" 2>/dev/null; then
      success "Memgraph running ($mg_container)"
    else
      info "Starting existing Memgraph container..."
      docker start "$mg_container" >> "$LOG_FILE" 2>&1 && \
        success "Memgraph started ($mg_container)" || \
        warn "Could not start $mg_container"
    fi

    # Cap memory at 12GB if unlimited (prevents OOM)
    local mem
    mem=$(docker inspect --format '{{.HostConfig.Memory}}' "$mg_container" 2>/dev/null || echo "0")
    if [[ "$mem" == "0" ]]; then
      docker update --memory 12g "$mg_container" >> "$LOG_FILE" 2>&1 && \
        info "Memory capped at 12GB (prevents OOM)" || true
    fi
  else
    # Fresh install via docker compose
    local compose_file="$PI_AGENT_DIR/proxies/memgraph/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
      # Detect docker compose v1 vs v2
      local compose_cmd="docker compose"
      if ! docker compose version &>/dev/null 2>&1; then
        if command -v docker-compose &>/dev/null; then
          compose_cmd="docker-compose"
        else
          warn "Neither 'docker compose' nor 'docker-compose' found"
          return 0
        fi
      fi
      run_with_spinner "Starting Memgraph (first time — downloading image)" \
        bash -c "cd '$PI_AGENT_DIR/proxies/memgraph' && $compose_cmd up -d" || {
        warn "Memgraph failed to start — you can set it up later"
        return 0
      }
      success "Memgraph started"
    else
      warn "No docker-compose.yml found — skipping Memgraph"
      return 0
    fi
  fi

  # Apply graph schema
  local mg_running
  mg_running=$(docker ps --format '{{.Names}}' | grep -E "^(helios-memgraph|familiar-graph-1)$" | head -1)
  local schema="$PI_AGENT_DIR/skills/skill-graph/scripts/schema.cypher"
  if [[ -n "$mg_running" ]] && [[ -f "$schema" ]]; then
    docker exec -i "$mg_running" mgconsole --username memgraph --password memgraph \
      < "$schema" >> "$LOG_FILE" 2>&1 && info "Graph schema applied" || true
  fi
}

# ─── Ollama (Local Embeddings) ────────────────────────────────────────────────
setup_ollama() {
  step "Ollama (Local Embeddings)"

  if ! command -v ollama &>/dev/null; then
    echo ""
    ask "Install Ollama for local embeddings? (required for semantic search) [Y/n]:"
    read -r install_ollama
    install_ollama="${install_ollama:-Y}"

    if [[ "$install_ollama" =~ ^[Yy]$ ]]; then
      info "Installing Ollama..."
      if curl -fsSL https://ollama.com/install.sh 2>/dev/null | sh >> "$LOG_FILE" 2>&1; then
        success "Ollama installed"
      else
        warn "Ollama auto-install failed"
        info "Install manually: https://ollama.com"
        return 0
      fi
    else
      info "Skipping Ollama — semantic search will be unavailable"
      return 0
    fi
  else
    success "Ollama installed"
  fi

  # Ensure Ollama is running
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    info "Starting Ollama..."
    nohup ollama serve >> "$LOG_FILE" 2>&1 &
    disown 2>/dev/null || true
    # Wait with retry loop (up to 15s)
    local ollama_ready=false
    for i in {1..15}; do
      if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        ollama_ready=true
        break
      fi
      sleep 1
    done
    if [[ "$ollama_ready" = true ]]; then
      success "Ollama running"
    else
      warn "Ollama not responding — you may need to start it manually"
      return 0
    fi
  else
    success "Ollama running"
  fi

  # Pull required embedding models
  for model in granite-embedding qwen3-embedding; do
    if ollama list 2>/dev/null | grep -q "$model"; then
      success "$model model ready"
    else
      run_with_spinner "Pulling $model (this may take a few minutes)" \
        ollama pull "$model" || warn "Failed to pull $model"
    fi
  done
}

# ─── MCP Servers ──────────────────────────────────────────────────────────────
setup_mcp_servers() {
  step "MCP Servers"

  # uv/uvx — needed for mcp-memgraph
  if ! command -v uvx &>/dev/null; then
    info "Installing uv (Python package manager for MCP servers)..."
    if curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh >> "$LOG_FILE" 2>&1; then
      [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env" 2>/dev/null || true
      export PATH="$HOME/.local/bin:$PATH"
      success "uv installed"
    else
      warn "uv install failed — MCP memgraph server will be unavailable"
    fi
  else
    success "uv/uvx ready"
  fi

  # Warm up mcp-memgraph binary
  if command -v uvx &>/dev/null; then
    info "Caching mcp-memgraph server..."
    uvx --from mcp-memgraph mcp-memgraph --help >> "$LOG_FILE" 2>&1 &
    success "mcp-memgraph (Bolt → MCP bridge)"
  fi

  # npx for GitHub MCP
  if command -v npx &>/dev/null; then
    success "GitHub MCP (via npx)"
  else
    warn "npx not found — GitHub MCP server unavailable"
  fi

  # Write mcp.json with all 3 servers
  local mcp_file="$PI_AGENT_DIR/mcp.json"
  if [[ -f "$mcp_file" ]]; then
    local server_count
    server_count=$(python3 -c "import json; print(len(json.load(open('$mcp_file')).get('mcpServers',{})))" 2>/dev/null || echo "0")
    if [[ "$server_count" -ge 3 ]]; then
      success "mcp.json configured ($server_count servers)"
    else
      info "mcp.json has $server_count servers — updating"
      _write_mcp_json "$mcp_file"
    fi
  else
    _write_mcp_json "$mcp_file"
  fi
}

_write_mcp_json() {
  local mcp_file="$1"
  python3 -c "
import json, os
target = '$mcp_file'
servers = {
    'figma-remote': {
        'transport': 'http',
        'url': 'https://mcp.figma.com/mcp',
        'auth': 'bearer',
        'bearerTokenEnv': 'FIGMA_MCP_TOKEN',
        'lifecycle': 'lazy'
    },
    'memgraph': {
        'command': 'uvx',
        'args': ['--from', 'mcp-memgraph', 'mcp-memgraph'],
        'env': {
            'MEMGRAPH_URL': 'bolt://127.0.0.1:7687',
            'MEMGRAPH_USER': 'memgraph',
            'MEMGRAPH_PASSWORD': 'memgraph',
            'MEMGRAPH_DATABASE': 'memgraph',
            'MCP_READ_ONLY': 'no'
        },
        'lifecycle': 'eager',
        'idleTimeout': 300
    },
    'github': {
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-github'],
        'env': {
            'GITHUB_PERSONAL_ACCESS_TOKEN': '\${GITHUB_TOKEN}'
        }
    }
}
mcp = {'mcpServers': servers}
if os.path.exists(target):
    try:
        with open(target) as f:
            existing = json.load(f)
        existing.setdefault('mcpServers', {}).update(servers)
        mcp = existing
    except: pass
with open(target, 'w') as f:
    json.dump(mcp, f, indent=2)
    f.write('\n')
" 2>/dev/null && success "mcp.json written (figma-remote, memgraph, github)" || warn "Could not write mcp.json"
}

# ─── API Key Setup ────────────────────────────────────────────────────────────
setup_api_keys() {
  step "API Key Setup"

  local env_file="$PI_AGENT_DIR/.env"
  local env_template="$INSTALLER_DIR/.env.template"

  # Load existing .env if present
  if [[ -f "$env_file" ]]; then
    info ".env already exists — updating only empty values"
  else
    cp "$env_template" "$env_file"
    chmod 600 "$env_file"
    info "Created .env from template"
  fi

  echo ""
  echo -e "  ${BOLD}API Keys${RESET} ${DIM}(press Enter to skip and fill in later)${RESET}"
  echo ""

  # Helper: prompt for key if not already set
  prompt_key() {
    local key_name="$1"
    local description="$2"
    local required="${3:-optional}"
    local current_val
    current_val=$(grep "^${key_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- || echo "")

    if [[ -n "$current_val" ]]; then
      info "$key_name already set — skipping"
      return
    fi

    local label="${GREEN}[required]${RESET}"
    [[ "$required" == "optional" ]] && label="${DIM}[optional]${RESET}"
    [[ "$required" == "recommended" ]] && label="${YELLOW}[recommended]${RESET}"

    ask "$key_name $label — $description:"
    read -rs key_val
    echo ""  # newline after silent read

    if [[ -n "$key_val" ]]; then
      # Update the env file (replace the empty key= line)
      if grep -q "^${key_name}=" "$env_file"; then
        sed -i.bak "s|^${key_name}=.*|${key_name}=\"${key_val}\"|" "$env_file"
        rm -f "${env_file}.bak"
      else
        echo "${key_name}=${key_val}" >> "$env_file"
      fi
      success "$key_name saved"
    else
      warn "$key_name skipped — add to $env_file later"
    fi
  }

  # Provider-specific required key
  case "$SELECTED_PROVIDER" in
    anthropic)
      prompt_key "ANTHROPIC_API_KEY" "from console.anthropic.com/api-keys" "required"
      ;;
    amazon-bedrock)
      prompt_key "AWS_ACCESS_KEY_ID" "from AWS IAM Console" "required"
      prompt_key "AWS_SECRET_ACCESS_KEY" "from AWS IAM Console" "required"
      echo ""
      ask "AWS_DEFAULT_REGION (default: us-east-1):"
      read -r aws_region
      aws_region="${aws_region:-us-east-1}"
      sed -i.bak "s|^AWS_DEFAULT_REGION=.*|AWS_DEFAULT_REGION=${aws_region}|" "$env_file"
      rm -f "${env_file}.bak"
      ;;
    openai)
      prompt_key "OPENAI_API_KEY" "from platform.openai.com/api-keys" "required"
      ;;
  esac

  echo ""
  echo -e "  ${DIM}Additional keys (optional but recommended):${RESET}"
  prompt_key "GITHUB_TOKEN" "github.com/settings/tokens (for PR review MCP)" "recommended"
  prompt_key "GROQ_API_KEY" "for transcription/Whisper (console.groq.com)" "optional"
  prompt_key "FIGMA_MCP_TOKEN" "for Figma MCP server (figma.com → Account → API tokens)" "optional"
  prompt_key "ANTHROPIC_API_KEY" "for fallback if primary is Bedrock/OpenAI" "optional"

  success ".env configured at $env_file"
  # Secure .env permissions (API keys should not be world-readable)
  chmod 600 "$env_file"
}

# ─── Wire API Keys to Shell ───────────────────────────────────────────────────
wire_env_to_shell() {
  step "Wiring API keys to shell environment"

  local env_file="$PI_AGENT_DIR/.env"
  local shell_profile=""

  # Detect shell profile
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    shell_profile="$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
    shell_profile="$HOME/.bashrc"
  else
    shell_profile="$HOME/.profile"
  fi

  local source_line="# Helios/Pi API keys"
  local source_cmd="[ -f ~/.pi/agent/.env ] && set -a && source ~/.pi/agent/.env && set +a"

  if grep -qF "source ~/.pi/agent/.env" "$shell_profile" 2>/dev/null || grep -qF ".pi/agent/.env" "$shell_profile" 2>/dev/null; then
    success "Shell profile already sources .env"
  else
    echo "" >> "$shell_profile"
    echo "$source_line" >> "$shell_profile"
    echo "$source_cmd" >> "$shell_profile"
    success "Added .env sourcing to $shell_profile"
  fi

  # Source now for immediate use
  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    set +a
    success "API keys loaded into current session"
  fi

  warn "Restart your terminal or run: source $shell_profile"
}

# ─── Familiar Skills ──────────────────────────────────────────────────────────
setup_familiar() {
  step "Familiar Skills (optional)"

  echo ""
  ask "Install Familiar skills? (Gmail, Calendar, Drive, transcription) [y/N]:"
  read -r install_familiar
  install_familiar="${install_familiar:-n}"

  if [[ ! "$install_familiar" =~ ^[Yy]$ ]]; then
    info "Skipping Familiar setup"
    return 0
  fi

  if [[ -d "$FAMILIAR_DIR" ]]; then
    if [[ -d "$FAMILIAR_DIR/.git" ]]; then
      info "~/.familiar/ already exists — pulling latest"
      run_with_spinner "Updating familiar" \
        git -C "$FAMILIAR_DIR" pull --rebase --autostash || warn "Could not pull familiar"
      return 0
    fi
  fi

  info "Cloning Familiar → ~/.familiar/"
  echo ""
  ask "Proceed with clone? [y/N]:"
  read -r confirm_familiar
  if [[ ! "$confirm_familiar" =~ ^[Yy]$ ]]; then
    warn "Familiar setup skipped"
    return 0
  fi

  if ! run_with_spinner "Cloning familiar → ~/.familiar/" \
    git clone "https://$FAMILIAR_REPO.git" "$FAMILIAR_DIR"; then
    warn "Could not clone Familiar"
    echo -e "    ${DIM}If this is a private repo, configure git credentials:${RESET}"
    echo -e "    ${DIM}  gh auth login${RESET}"
    echo -e "    ${DIM}  # or: git config --global credential.helper osxkeychain${RESET}"
    return 0
  fi
  success "Familiar cloned to $FAMILIAR_DIR"

  # Check if Familiar needs dependency installation
  if [[ -f "$FAMILIAR_DIR/pnpm-lock.yaml" ]]; then
    if command -v pnpm &>/dev/null; then
      ask "Run pnpm install for Familiar dependencies? [y/N]:"
      read -r run_pnpm
      if [[ "$run_pnpm" =~ ^[Yy]$ ]]; then
        run_with_spinner "Installing Familiar dependencies" \
          pnpm --dir "$FAMILIAR_DIR" install || warn "pnpm install had issues"
      fi
    else
      warn "pnpm not found — Familiar skills may need manual setup: cd ~/.familiar && pnpm install"
    fi
  fi

  echo ""
  info "NOTE: Google Workspace skills (Gmail, Calendar, Drive) require OAuth setup."
  info "See: ~/.familiar/skills/gmcli/SKILL.md for OAuth configuration instructions."
}

# ─── Verification ─────────────────────────────────────────────────────────────
run_verification() {
  step "Verification"

  local all_ok=true

  # Pi responds
  if command -v pi &>/dev/null; then
    success "pi binary found: $(which pi)"
  else
    error "pi binary not in PATH"
    all_ok=false
  fi

  # Agent dir
  if [[ -d "$PI_AGENT_DIR" ]]; then
    success "~/.pi/agent/ exists"
  else
    error "~/.pi/agent/ not found"
    all_ok=false
  fi

  # Count agents
  local agent_count=0
  if [[ -d "$PI_AGENT_DIR/agents" ]]; then
    agent_count=$(find "$PI_AGENT_DIR/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$agent_count" -ge 40 ]]; then
      success "Agents: $agent_count (expect 40+)"
    else
      warn "Agents: $agent_count (expected 40+) — packages may not be fully installed"
    fi
  fi

  # Count skills
  local skill_count=0
  skill_count=$(find "$PI_AGENT_DIR/skills" "$FAMILIAR_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$skill_count" -ge 13 ]]; then
    success "Skills: $skill_count (expect 13+)"
  else
    warn "Skills: $skill_count (expected 13+)"
  fi

  # Count extensions
  local ext_count=0
  if [[ -d "$PI_AGENT_DIR/extensions" ]]; then
    ext_count=$(find "$PI_AGENT_DIR/extensions" -name "*.js" -o -name "index.ts" 2>/dev/null | wc -l | tr -d ' ')
    success "Extensions: found in ~/.pi/agent/extensions/"
  fi

  # .env has at least one key set
  local env_file="$PI_AGENT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    local keys_set
    keys_set=$(grep -v '^#' "$env_file" 2>/dev/null | grep -v '^$' | grep -v '=$' | wc -l | tr -d ' ')
    if [[ "$keys_set" -gt 0 ]]; then
      success ".env: $keys_set key(s) configured"
    else
      warn ".env exists but no keys are set — add at least one API key"
    fi
  else
    warn ".env not found at $env_file"
  fi

  # settings.json
  if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local configured_provider
    configured_provider=$(python3 -c "import json; d=json.load(open('$PI_AGENT_DIR/settings.json')); print(d.get('defaultProvider','?'))" 2>/dev/null || echo "?")
    success "settings.json: provider=$configured_provider"
  fi

  echo ""
  if [[ "$all_ok" == "true" ]]; then
    echo -e "  ${GREEN}${BOLD}✓ Verification passed${RESET}"
  else
    echo -e "  ${YELLOW}${BOLD}⚠ Verification completed with warnings — see above${RESET}"
  fi
}

# ─── Quick-Start Guide ────────────────────────────────────────────────────────
print_quickstart() {
  echo ""
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${GREEN}  ✓ Helios + Pi Installation Complete!${RESET}"
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo -e "  ${BOLD}Quick Start:${RESET}"
  echo ""
  echo -e "    ${CYAN}1.${RESET} Open your project directory:"
  echo -e "       ${DIM}cd /path/to/your/project${RESET}"
  echo ""
  echo -e "    ${CYAN}2.${RESET} Start Helios:"
  echo -e "       ${DIM}helios${RESET}"
  echo ""
  echo -e "    ${CYAN}3.${RESET} Try a task:"
  echo -e "       ${DIM}\"Review my code and create a PR\"${RESET}"
  echo -e "       ${DIM}\"Plan and implement user authentication\"${RESET}"
  echo ""
  echo -e "  ${BOLD}Key Files:${RESET}"
  echo -e "    ${DIM}~/.pi/agent/.env${RESET}          — API keys (edit to add/change)"
  echo -e "    ${DIM}~/.pi/agent/settings.json${RESET} — Provider/model config"
  echo -e "    ${DIM}~/.pi/agent/agents/${RESET}        — Agent definitions"
  echo -e "    ${DIM}~/.pi/agent/skills/${RESET}        — Skill definitions"
  echo ""
  echo -e "  ${BOLD}Useful Commands:${RESET}"
  echo -e "    ${DIM}helios${RESET}                  — Launch Helios (branded splash)"
  echo -e "    ${DIM}pi${RESET}                      — Start Pi"
  echo -e "    ${DIM}bash ~/helios-team-installer/install.sh${RESET}  — Update everything"
  echo -e "    ${DIM}bash $INSTALLER_DIR/verify.sh${RESET}   — Run health check"
  echo -e "    ${DIM}bash $INSTALLER_DIR/uninstall.sh${RESET} — Uninstall"
  echo -e "    ${DIM}bash install.sh --fresh${RESET}  — Re-run full setup (provider, keys)"
  echo ""
  echo -e "  ${BOLD}Troubleshooting:${RESET}  ${DIM}See $INSTALLER_DIR/README.md${RESET}"
  echo ""
  if [[ -f "$PI_AGENT_DIR/.env" ]]; then
    local keys_missing
    keys_missing=$(grep -c '^[A-Z_]*=$' "$PI_AGENT_DIR/.env" 2>/dev/null || echo 0)
    if [[ "$keys_missing" -gt 0 ]]; then
      echo -e "  ${YELLOW}⚠ ${keys_missing} API key(s) not yet set. Edit: ${DIM}~/.pi/agent/.env${RESET}"
    fi
  fi
  echo ""
}

# ─── Update Detection ─────────────────────────────────────────────────────────
# If helios is already installed and configured, skip interactive steps.
# User can force fresh setup with: bash install.sh --fresh
detect_update_mode() {
  UPDATE_MODE=false

  # --fresh flag forces full interactive setup
  for arg in "$@"; do
    [[ "$arg" == "--fresh" ]] && return 0
  done

  # If agent dir exists with a configured provider and .env, this is an update
  if [[ -d "$PI_AGENT_DIR/.git" ]] && [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local current_provider
    current_provider=$(python3 -c "import json; print(json.load(open('$PI_AGENT_DIR/settings.json')).get('defaultProvider',''))" 2>/dev/null || echo "")
    if [[ -n "$current_provider" ]] && [[ "$current_provider" != "null" ]]; then
      if [[ -f "$PI_AGENT_DIR/.env" ]]; then
        UPDATE_MODE=true
        SELECTED_PROVIDER="$current_provider"
        SELECTED_MODEL=$(python3 -c "import json; print(json.load(open('$PI_AGENT_DIR/settings.json')).get('defaultModel',''))" 2>/dev/null || echo "")
        info "Existing install detected (provider: $SELECTED_PROVIDER)"
        info "Running in update mode — skipping provider/key prompts"
        info "To re-run full setup: bash install.sh --fresh"
        echo ""
      fi
    fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  print_banner
  detect_update_mode "$@"
  check_prerequisites
  install_pi
  setup_helios_agent
  install_helios_cli

  if [[ "$UPDATE_MODE" == false ]]; then
    select_provider     # Interactive: choose AI provider
  fi

  install_packages
  install_skill_deps    # neo4j-driver, tree-sitter for HEMA
  install_governance_deps  # Governance extension node_modules
  install_git_hooks     # Pre-push hook for branch protection
  setup_dep_allowlist   # npm dependency allowlist
  setup_memgraph        # Docker + Memgraph + schema + 12GB cap
  setup_ollama          # Ollama + embedding models (skips already-pulled)
  setup_mcp_servers     # uv/uvx, mcp-memgraph, GitHub MCP, write mcp.json

  if [[ "$UPDATE_MODE" == false ]]; then
    setup_api_keys      # Interactive: prompt for keys
    wire_env_to_shell   # Add .env sourcing to shell profile
    setup_familiar      # Interactive: optional Familiar install
  fi

  run_verification
  print_quickstart

  # Ensure installer exit trap doesn't print error message on clean exit
  trap - EXIT
}

main "$@"
