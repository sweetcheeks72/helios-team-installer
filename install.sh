#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Team Installer
# =============================================================================
# Installs: Pi CLI, Helios Agent, 20 git packages, extensions, Familiar skills,
# API key setup
# =============================================================================
INSTALLER_VERSION="2.1.0"

set -euo pipefail
INSTALL_WARNINGS=()

# ─── Source error recovery library ────────────────────────────────────────────
INSTALLER_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$INSTALLER_DIR_EARLY/lib/error-recovery.sh" ]]; then
  # shellcheck source=lib/error-recovery.sh
  source "$INSTALLER_DIR_EARLY/lib/error-recovery.sh"
fi

# ─── Early arg check (before tty redirect) ───────────────────────────────────
for _arg in "$@"; do
  case "$_arg" in
    --help|-h)
      echo "Helios Team Installer v${INSTALLER_VERSION}"
      echo ""
      echo "Usage: bash install.sh [options]"
      echo ""
      echo "Options:"
      echo "  --fresh    Force full interactive setup (re-prompt provider, keys)"
      echo "  --update   Run in update mode (skip interactive prompts)"
      echo "  --help     Show this help message"
      echo ""
      echo "First install (team members):"
      echo "  curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"
      echo ""
      echo "Re-run / update:"
      echo "  helios update"
      exit 0
      ;;
  esac
done

# ─── Restore stdin from terminal (critical for curl|bash piping) ─────────────
# When run via `curl ... | bash`, stdin is the pipe (EOF after script downloads).
# Reopen stdin from /dev/tty so interactive `read` commands work.
if [[ ! -t 0 ]]; then
  if [[ -e /dev/tty ]]; then
    exec < /dev/tty || true
  else
    echo "ERROR: No terminal available (/dev/tty). Run this script directly instead of piping." >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh -o /tmp/helios-bootstrap.sh && bash /tmp/helios-bootstrap.sh" >&2
    exit 1
  fi
fi

cleanup() {
  local exit_code=$?
  # Kill any leftover spinner
  if [[ -n "${spin_pid:-}" ]] && kill -0 "$spin_pid" 2>/dev/null; then
    kill "$spin_pid" 2>/dev/null || true
    wait "$spin_pid" 2>/dev/null || true
  fi
  # Restore cursor visibility
  printf '\033[?25h'
  if [[ $exit_code -ne 0 ]]; then
    # Write to stderr directly — stdout may be a broken tee pipe
    echo -e "\n\033[0;31m✗ Installer interrupted (exit code $exit_code). Run again to resume (idempotent).\033[0m" >&2
  fi
}
trap cleanup EXIT INT TERM

# ─── Platform Detection ───────────────────────────────────────────────────────
is_wsl() {
  [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version 2>/dev/null
}

current_platform() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos"
  elif is_wsl; then
    echo "wsl"
  elif [[ "$(uname -s)" == "Linux" ]]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

# ─── Colors & Styles ─────────────────────────────────────────────────────────
# Respect NO_COLOR (https://no-color.org/) and dumb terminals
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' RESET=''
else
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}  ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*"; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }
ask()     { echo -en "${MAGENTA}  ? ${RESET}$* "; }

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELIOS_RELEASE_URL="https://github.com/sweetcheeks72/helios-team-installer/releases/latest/download"
HELIOS_AGENT_TARBALL="helios-agent-latest.tar.gz"
FAMILIAR_REPO="github.com/sweetcheeks72/familiar"
PI_AGENT_DIR="$HOME/.pi/agent"
FAMILIAR_DIR="$HOME/.familiar"
LOG_FILE="$INSTALLER_DIR/install.log"

# Log to file AND terminal. Best-effort — if tee fails, continue without logging.
# CRITICAL: Do NOT redirect stderr through tee. If tee/pipe breaks, stderr must
# still reach the terminal so error messages (including the cleanup trap) are visible.
if touch "$LOG_FILE" 2>/dev/null; then
  exec > >(tee -a "$LOG_FILE")
  trap '' PIPE  # Ignore SIGPIPE so script continues if tee dies
  # stderr stays on the terminal — cleanup trap errors will always be visible
else
  echo -e "${YELLOW}  ⚠ ${RESET}Cannot write to $LOG_FILE — continuing without log file"
fi

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
  local tmp_err
  tmp_err="$(mktemp)"
  # Run command: stdout to log file (not terminal — spinner is showing).
  # Stderr to temp file for error display on failure.
  "$@" >> "$LOG_FILE" 2>"$tmp_err" &
  local cmd_pid=$!
  # Use || cmd_exit=$? to prevent set -e from firing on failed wait, which would
  # skip stop_spinner and leave the terminal in a corrupt state.
  local cmd_exit=0
  wait $cmd_pid || cmd_exit=$?
  stop_spinner
  # Append stderr to log file regardless of outcome
  cat "$tmp_err" >> "$LOG_FILE" 2>/dev/null || true
  if [[ $cmd_exit -eq 0 ]]; then
    success "$msg"
    rm -f "$tmp_err"
    return 0
  else
    error "$msg"
    if [[ -s "$tmp_err" ]]; then
      echo -e "    ${DIM}--- Error details ---${RESET}" >&2
      tail -8 "$tmp_err" | while IFS= read -r line; do
        echo -e "    ${DIM}${line}${RESET}" >&2
      done
    fi
    echo -e "    ${DIM}Full log: $LOG_FILE${RESET}" >&2
    rm -f "$tmp_err"
    return $cmd_exit
  fi
}

check_prerequisites() {
  step "Prerequisites (auto-installing missing dependencies)"

  local platform
  platform="$(current_platform)"
  local arch
  arch="$(uname -m)"

  # ── Homebrew (macOS only) ──────────────────────────────────────────────────
  if [[ "$platform" == "macos" ]] && ! command -v brew &>/dev/null; then
    info "Installing Homebrew (required for macOS package management)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null >> "$LOG_FILE" 2>&1
    # Add brew to PATH for this session
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
    if command -v brew &>/dev/null; then
      success "Homebrew installed"
    else
      error "Homebrew install failed — install manually: https://brew.sh"
      exit 1
    fi
  fi

  # ── One-time apt-get update (linux/wsl) ────────────────────────────────────
  if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
    sudo apt-get update -y >> "$LOG_FILE" 2>&1 || true
  fi

  # ── Helper: install a dependency ───────────────────────────────────────────
  _install_dep() {
    local cmd="$1" brew_pkg="${2:-$1}" apt_pkg="${3:-$1}"
    if command -v "$cmd" &>/dev/null; then
      return 0
    fi
    info "Installing $cmd..."
    case "$platform" in
      macos)
        brew install "$brew_pkg" >> "$LOG_FILE" 2>&1 ;;
      linux|wsl)
        sudo apt-get install -y "$apt_pkg" >> "$LOG_FILE" 2>&1 ;;
      *)
        warn "$cmd: unsupported platform ($platform) — install manually"
        return 1 ;;
    esac
    command -v "$cmd" &>/dev/null
  }

  # ── Node.js 18+ ────────────────────────────────────────────────────────────
  local node_ok=false
  if command -v node &>/dev/null; then
    if node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null; then
      node_ok=true
      success "Node.js $(node -v)"
    else
      warn "Node.js $(node -v) is too old (need 18+) — upgrading..."
    fi
  fi

  if [[ "$node_ok" == false ]]; then
    info "Installing Node.js..."
    case "$platform" in
      macos)
        brew install node >> "$LOG_FILE" 2>&1 ;;
      linux|wsl)
        # NodeSource for Node 22 LTS (Ubuntu/Debian)
        if command -v curl &>/dev/null; then
          curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | sudo bash - >> "$LOG_FILE" 2>&1
          sudo apt-get install -y nodejs >> "$LOG_FILE" 2>&1
        else
          sudo apt-get update -y >> "$LOG_FILE" 2>&1
          sudo apt-get install -y nodejs npm >> "$LOG_FILE" 2>&1
        fi
        ;;
    esac
    if command -v node &>/dev/null && node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null; then
      success "Node.js $(node -v) installed"
    else
      error "Node.js 18+ installation failed"
      echo -e "    ${DIM}Install manually: https://nodejs.org${RESET}"
      exit 1
    fi
  fi

  # ── npm ─────────────────────────────────────────────────────────────────────
  if command -v npm &>/dev/null; then
    success "npm $(npm -v)"
  else
    error "npm not found (should come with Node.js) — install Node.js from https://nodejs.org"
    exit 1
  fi

  # ── git ─────────────────────────────────────────────────────────────────────
  if _install_dep git git git; then
    success "git $(git --version | awk '{print $3}')"
  else
    error "git installation failed"
    exit 1
  fi

  # ── curl ────────────────────────────────────────────────────────────────────
  if command -v curl &>/dev/null; then
    success "curl"
  else
    _install_dep curl curl curl || warn "curl not found — some features may be limited"
  fi

  # ── python3 ─────────────────────────────────────────────────────────────────
  if command -v python3 &>/dev/null; then
    success "python3 $(python3 --version 2>/dev/null | awk '{print $2}')"
  else
    info "Installing python3..."
    case "$platform" in
      macos)
        brew install python3 >> "$LOG_FILE" 2>&1
        ;;
      linux|wsl)
        sudo apt-get install -y python3 >> "$LOG_FILE" 2>&1
        ;;
    esac
    if command -v python3 &>/dev/null; then
      success "python3 $(python3 --version 2>/dev/null | awk '{print $2}') installed"
    else
      warn "python3 not found — some configuration features may be limited"
    fi
  fi

  # ── pnpm ────────────────────────────────────────────────────────────────────
  if command -v pnpm &>/dev/null; then
    success "pnpm $(pnpm -v 2>/dev/null)"
  else
    info "Installing pnpm..."
    npm install -g pnpm >> "$LOG_FILE" 2>&1 && success "pnpm installed" || warn "pnpm install failed — not critical"
  fi

  # ── Docker / OrbStack ───────────────────────────────────────────────────────
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      success "Docker (running)"
    else
      warn "Docker installed but not running — start OrbStack or Docker Desktop"
    fi
  else
    info "Installing container runtime (for Memgraph knowledge graph)..."
    case "$platform" in
      macos)
        info "Installing OrbStack (lightweight Docker for macOS)..."
        brew install --cask orbstack >> "$LOG_FILE" 2>&1 && {
          success "OrbStack installed — launch it to start Docker"
        } || warn "OrbStack install failed — install manually: https://orbstack.dev"
        ;;
      linux)
        info "Installing Docker CE..."
        if command -v curl &>/dev/null; then
          info "This will run the Docker install script with sudo permissions"
          curl -fsSL https://get.docker.com 2>/dev/null | sh >> "$LOG_FILE" 2>&1 && {
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            success "Docker CE installed"
          } || warn "Docker install failed — install manually: https://docs.docker.com/engine/install/"
        else
          warn "curl needed for Docker install — install Docker manually"
        fi
        ;;
      wsl)
        warn "Docker in WSL: Install Docker Desktop for Windows with WSL integration"
        info "https://docs.docker.com/desktop/wsl/"
        ;;
    esac
  fi

  # ── Xcode Command Line Tools (macOS) ───────────────────────────────────────
  if [[ "$platform" == "macos" ]] && ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    warn "Xcode CLT may need manual confirmation — check the popup dialog"
  fi

  # WSL-specific guidance
  if [[ "$platform" == "wsl" ]]; then
    echo -e "  ${CYAN}ℹ${RESET}  Running inside WSL — great! Full Linux environment detected."
    if command -v docker &>/dev/null; then
      success "Docker available in WSL"
    else
      warn "Docker not found in WSL"
      info "Install Docker Desktop for Windows and enable WSL integration:"
      info "https://docs.docker.com/desktop/wsl/"
    fi
    echo ""
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
      sudo chown -R "$(whoami)" "$HOME/.npm" >> "$LOG_FILE" 2>&1 || true
      npm cache clean --force >> "$LOG_FILE" 2>&1 || true
    fi
  fi
  
  if run_with_spinner "Installing Pi CLI (@helios-agent/cli)" \
      npm install -g @helios-agent/cli; then
    PI_INSTALLED=true
    success "Pi installed: $(pi --version 2>/dev/null | tail -1 || echo 'ok')"
  else
    # Retry with full cache nuke
    warn "First attempt failed — clearing npm cache and retrying..."
    sudo chown -R "$(whoami)" "$HOME/.npm" >> "$LOG_FILE" 2>&1 || true
    npm cache clean --force >> "$LOG_FILE" 2>&1 || true
    
    if run_with_spinner "Retrying Pi CLI install" \
        npm install -g @helios-agent/cli; then
      PI_INSTALLED=true
      success "Pi installed on retry: $(pi --version 2>/dev/null | tail -1 || echo 'ok')"
    else
      error "Failed to install Pi CLI."
      echo ""
      echo -e "  ${BOLD}Manual fix:${RESET}"
      echo -e "    ${DIM}sudo chown -R \$(whoami) ~/.npm${RESET}"
      echo -e "    ${DIM}npm cache clean --force${RESET}"
      echo -e "    ${DIM}npm install -g @helios-agent/cli${RESET}"
      echo -e "    Then re-run: ${DIM}bash $INSTALLER_DIR/install.sh${RESET}"
      exit 1
    fi
  fi
}

# ─── Helios Agent (Tarball) ───────────────────────────────────────────────────
setup_helios_agent() {
  step "Helios Agent (~/.pi/agent/)"

  # ── Helper: download a file, return non-zero on failure ──────────────────
  _helios_download() {
    local url="$1" dest="$2"
    curl -fSL --retry 3 --retry-delay 5 --max-time 300 -o "$dest" "$url"
  }

  # ── Update path: ~/.pi/agent/ exists and has a VERSION file ──────────────
  if [[ -e "$PI_AGENT_DIR" ]] && [[ ! -d "$PI_AGENT_DIR" ]]; then
    warn "~/.pi/agent/ exists but is not a directory — backing up"
    mv "$PI_AGENT_DIR" "${PI_AGENT_DIR}.file-backup.$(date +%s)"
  fi

  if [[ -d "$PI_AGENT_DIR" ]] && [[ -f "$PI_AGENT_DIR/VERSION" ]]; then
    local local_version
    local_version="$(cat "$PI_AGENT_DIR/VERSION")"
    info "Installed version: $local_version — checking for updates…"

    local tmp_version
    tmp_version="$(mktemp)"
    if ! _helios_download "$HELIOS_RELEASE_URL/VERSION" "$tmp_version"; then
      warn "Could not reach release server — continuing with existing version"
      rm -f "$tmp_version"
      return 0
    fi

    local remote_version
    remote_version="$(cat "$tmp_version")"
    rm -f "$tmp_version"

    if [[ "$local_version" == "$remote_version" ]]; then
      success "Helios agent is already up to date ($local_version)"
      return 0
    fi

    info "Update available: $local_version → $remote_version — downloading…"

    # Backup current install, preserving user files
    local backup_dir="${PI_AGENT_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -a "$PI_AGENT_DIR" "$backup_dir"
    info "Backed up current agent to $backup_dir"

    # Stash user files before extraction
    # PRESERVE_FILES — MUST MATCH auto-update.ts PRESERVE_FILES list
    local tmp_stash
    tmp_stash="$(mktemp -d)"
    for preserve in .env settings.json governance sessions .helios auth.json run-history.jsonl \
                    mcp.json dep-allowlist.json .secrets state models.json pi-messenger.json \
                    .update-state.json VERSION; do
      [[ -e "$PI_AGENT_DIR/$preserve" ]] && cp -a "$PI_AGENT_DIR/$preserve" "$tmp_stash/"
    done

    # Download and extract new tarball
    local tmp_tarball
    tmp_tarball="$(mktemp)"
    if ! _helios_download "$HELIOS_RELEASE_URL/$HELIOS_AGENT_TARBALL" "$tmp_tarball"; then
      warn "Tarball download failed — rolling back to existing version"
      rm -rf "$tmp_stash" "$tmp_tarball"
      return 0
    fi

    # Verify checksum
    local tmp_checksum
    tmp_checksum="$(mktemp)"
    if _helios_download "$HELIOS_RELEASE_URL/$HELIOS_AGENT_TARBALL.sha256" "$tmp_checksum"; then
      local expected_sha actual_sha
      expected_sha="$(awk '{print $1}' "$tmp_checksum")"
      if command -v sha256sum &>/dev/null; then
        actual_sha="$(sha256sum "$tmp_tarball" | awk '{print $1}')"
      elif command -v shasum &>/dev/null; then
        actual_sha="$(shasum -a 256 "$tmp_tarball" | awk '{print $1}')"
      else
        warn "No sha256 tool found — skipping checksum verification"
        actual_sha="$expected_sha"
      fi
      if [[ -n "$actual_sha" ]] && [[ "$actual_sha" != "$expected_sha" ]]; then
        warn "SHA256 mismatch — aborting update"
        rm -rf "$tmp_stash" "$tmp_tarball" "$tmp_checksum"
        cp -a "$backup_dir" "$PI_AGENT_DIR"
        return 0
      fi
    fi
    rm -f "$tmp_checksum"

    rm -rf "$PI_AGENT_DIR"
    mkdir -p "$PI_AGENT_DIR"
    if ! tar -xzf "$tmp_tarball" -C "$PI_AGENT_DIR" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
      warn "Tarball extraction failed — restoring backup"
      rm -rf "$PI_AGENT_DIR"
      cp -a "$backup_dir" "$PI_AGENT_DIR"
      rm -rf "$tmp_stash" "$tmp_tarball"
      return 0
    fi
    rm -f "$tmp_tarball"

    # Restore user files
    for preserve in .env settings.json governance sessions .helios auth.json run-history.jsonl \
                    mcp.json dep-allowlist.json .secrets state models.json pi-messenger.json \
                    .update-state.json VERSION; do
      [[ -e "$tmp_stash/$preserve" ]] && cp -a "$tmp_stash/$preserve" "$PI_AGENT_DIR/"
    done
    rm -rf "$tmp_stash"

    success "Helios agent updated to $remote_version"
    # Ensure VERSION file exists after update
    if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
      echo "$remote_version" > "$PI_AGENT_DIR/VERSION"
    fi

    # /update uses tarball mechanism (same as this installer) — no git needed
    return 0
  fi

  # ── Migration: git-based install → tarball ─────────────────────────────────
  if [[ -d "$PI_AGENT_DIR/.git" ]]; then
    info "Detected git-based install — migrating to tarball distribution…"

    # Stash user files
    local tmp_stash
    tmp_stash="$(mktemp -d)"
    for preserve in .env settings.json governance sessions .helios auth.json run-history.jsonl \
                    mcp.json dep-allowlist.json .secrets state models.json pi-messenger.json \
                    .update-state.json VERSION; do
      [[ -e "$PI_AGENT_DIR/$preserve" ]] && cp -a "$PI_AGENT_DIR/$preserve" "$tmp_stash/"
    done

    # Backup the full git install
    local backup_dir="${PI_AGENT_DIR}.git-backup.$(date +%Y%m%d_%H%M%S)"
    cp -a "$PI_AGENT_DIR" "$backup_dir"
    info "Backed up git install to $backup_dir"

    # Download latest tarball
    local tmp_tarball
    tmp_tarball="$(mktemp)"
    if ! _helios_download "$HELIOS_RELEASE_URL/helios-agent-latest.tar.gz" "$tmp_tarball"; then
      warn "Tarball download failed — keeping git-based install"
      rm -rf "$tmp_stash" "$tmp_tarball"
      return 0
    fi

    # Verify checksum
    local tmp_checksum
    tmp_checksum="$(mktemp)"
    if _helios_download "$HELIOS_RELEASE_URL/helios-agent-latest.tar.gz.sha256" "$tmp_checksum"; then
      local expected_sha actual_sha
      expected_sha="$(awk '{print $1}' "$tmp_checksum")"
      if command -v sha256sum &>/dev/null; then
        actual_sha="$(sha256sum "$tmp_tarball" | awk '{print $1}')"
      elif command -v shasum &>/dev/null; then
        actual_sha="$(shasum -a 256 "$tmp_tarball" | awk '{print $1}')"
      else
        warn "No sha256 tool found — skipping checksum verification"
        actual_sha="$expected_sha"
      fi
      if [[ -n "$actual_sha" ]] && [[ "$actual_sha" != "$expected_sha" ]]; then
        warn "SHA256 mismatch — aborting migration"
        rm -rf "$tmp_stash" "$tmp_tarball" "$tmp_checksum"
        return 0
      fi
    fi
    rm -f "$tmp_checksum"

    # Replace git install with tarball
    rm -rf "$PI_AGENT_DIR"
    mkdir -p "$PI_AGENT_DIR"
    if ! tar -xzf "$tmp_tarball" -C "$PI_AGENT_DIR" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
      warn "Tarball extraction failed — restoring git backup"
      rm -rf "$PI_AGENT_DIR"
      cp -a "$backup_dir" "$PI_AGENT_DIR"
      rm -rf "$tmp_stash" "$tmp_tarball"
      return 0
    fi
    rm -f "$tmp_tarball"

    # Restore user files
    for preserve in .env settings.json governance sessions .helios auth.json run-history.jsonl \
                    mcp.json dep-allowlist.json .secrets state models.json pi-messenger.json \
                    .update-state.json VERSION; do
      [[ -e "$tmp_stash/$preserve" ]] && cp -a "$tmp_stash/$preserve" "$PI_AGENT_DIR/"
    done
    rm -rf "$tmp_stash"

    success "Migrated from git to tarball distribution ($(cat "$PI_AGENT_DIR/VERSION" 2>/dev/null || echo 'unknown'))"
    # Ensure VERSION file exists after migration
    if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
      echo "tarball-$(date +%Y%m%d)" > "$PI_AGENT_DIR/VERSION"
    fi
    info "Git backup preserved at: $backup_dir"
    return 0
  fi

  # ── Symlink: leave untouched ──────────────────────────────────────────────
  if [[ -L "$PI_AGENT_DIR" ]]; then
    info "~/.pi/agent/ is a symlink to: $(readlink "$PI_AGENT_DIR") — skipping"
    return 0
  fi

  # ── Fresh install ─────────────────────────────────────────────────────────
  info "Fresh install — downloading helios-agent tarball…"

  # Check disk space before downloading
  local free_mb
  free_mb=$(df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
  if [[ -n "$free_mb" ]] && [[ "$free_mb" -lt 500 ]]; then
    error "Insufficient disk space (${free_mb}MB free, need at least 500MB)"
    return 1
  fi

  local tmp_tarball tmp_checksum
  tmp_tarball="$(mktemp)"
  tmp_checksum="$(mktemp)"

  if ! _helios_download "$HELIOS_RELEASE_URL/$HELIOS_AGENT_TARBALL" "$tmp_tarball"; then
    warn "Tarball download failed — skipping helios-agent install"
    rm -f "$tmp_tarball" "$tmp_checksum"
    return 1
  fi

  if ! _helios_download "$HELIOS_RELEASE_URL/$HELIOS_AGENT_TARBALL.sha256" "$tmp_checksum"; then
    warn "Checksum file download failed — skipping helios-agent install"
    rm -f "$tmp_tarball" "$tmp_checksum"
    return 1
  fi

  # Verify SHA256
  local expected_sha actual_sha
  expected_sha="$(awk '{print $1}' "$tmp_checksum")"
  if command -v sha256sum &>/dev/null; then
    actual_sha="$(sha256sum "$tmp_tarball" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    actual_sha="$(shasum -a 256 "$tmp_tarball" | awk '{print $1}')"
  else
    warn "No sha256 tool found — skipping checksum verification"
    actual_sha="$expected_sha"
  fi

  if [[ "$actual_sha" != "$expected_sha" ]]; then
    warn "SHA256 mismatch (expected $expected_sha, got $actual_sha) — aborting install"
    rm -f "$tmp_tarball" "$tmp_checksum"
    return 1
  fi

  mkdir -p "$HOME/.pi"
  mkdir -p "$PI_AGENT_DIR"
  if ! tar -xzf "$tmp_tarball" -C "$PI_AGENT_DIR" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
    warn "Tarball extraction failed — skipping helios-agent install"
    rm -rf "$PI_AGENT_DIR" "$tmp_tarball" "$tmp_checksum"
    return 1
  fi

  rm -f "$tmp_tarball" "$tmp_checksum"
  success "Helios agent installed to $PI_AGENT_DIR"

  # Ensure VERSION file exists (tarball may be missing it)
  if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
    echo "tarball-$(date +%Y%m%d)" > "$PI_AGENT_DIR/VERSION"
    warn "VERSION file missing from tarball — created placeholder"
  fi
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
  fi

  # Add to PATH in shell profile if not already there
  local shell_rc="$HOME/.zshrc"
  [[ -f "$HOME/.bashrc" ]] && [[ ! -f "$HOME/.zshrc" ]] && shell_rc="$HOME/.bashrc"
  if ! grep -q '\.local/bin' "$shell_rc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
    success "Added ~/.local/bin to PATH in $(basename "$shell_rc")"
  fi
  export PATH="$HOME/.local/bin:$PATH"
  info "Restart your terminal or run: source ~/.zshrc"


  # Also symlink fd if present and not already in PATH
  local fd_bin="$PI_AGENT_DIR/bin/fd"
  if [[ -f "$fd_bin" ]] && ! command -v fd &>/dev/null; then
    chmod +x "$fd_bin"
    if [[ -w /usr/local/bin ]]; then
      ln -sfn "$fd_bin" /usr/local/bin/fd
      success "fd → /usr/local/bin/fd"
    elif [[ -d "$HOME/.local/bin" ]]; then
      ln -sfn "$fd_bin" "$HOME/.local/bin/fd"
      success "fd → ~/.local/bin/fd"
    fi
  fi

  success "Type 'helios' to launch (branded pi wrapper)"
}

# ─── Pi Update (Install Packages) ─────────────────────────────────────────────
install_packages() {
  step "Installing Pi packages"

  # Check if packages were bundled in the tarball
  local bundled_count=0
  if [[ -d "$PI_AGENT_DIR/git/github.com/sweetcheeks72" ]]; then
    bundled_count=$(find "$PI_AGENT_DIR/git/github.com/sweetcheeks72" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    ((bundled_count--)) || true  # subtract the parent dir itself
  fi

  if [[ "$bundled_count" -ge 15 ]]; then
    success "Packages pre-bundled in tarball ($bundled_count packages)"
    info "Running pi update to verify and sync..."
  else
    info "Downloading packages — this may take 2-3 minutes"
  fi

  if [[ ! -f "$PI_AGENT_DIR/settings.json" ]]; then
    warn "settings.json not found — using Anthropic default"
    cp "$INSTALLER_DIR/provider-configs/anthropic.json" "$PI_AGENT_DIR/settings.json"
  fi

  run_with_spinner "Running pi update (installing/verifying packages)" \
    pi update || {
    if [[ "$bundled_count" -ge 15 ]]; then
      warn "pi update had issues, but bundled packages are available"
    else
      warn "pi update had issues — packages may need manual installation"
    fi
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
  read -t 120 -r provider_choice || provider_choice=""
  provider_choice="${provider_choice:-1}"

  case "$provider_choice" in
    1)
      SELECTED_PROVIDER="anthropic"
      SELECTED_MODEL="claude-sonnet-4-5"
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
      SELECTED_MODEL="claude-sonnet-4-5"
      PROVIDER_CONFIG="$INSTALLER_DIR/provider-configs/anthropic.json"
      ;;
  esac

  # MERGE provider config into existing settings.json (don't overwrite!)
  if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local merge_ok=false

    # Try python3 first
    if command -v python3 &>/dev/null && python3 -c "import json" 2>/dev/null; then
      python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    existing = json.load(f)
with open(sys.argv[2]) as f:
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

with open(sys.argv[1], 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')

print('Merged provider config into existing settings.json')
" "$PI_AGENT_DIR/settings.json" "$PROVIDER_CONFIG" && merge_ok=true || true
    fi

    # Fallback to node if python3 failed
    if [[ "$merge_ok" == false ]] && command -v node &>/dev/null; then
      node -e "
const fs = require('fs');
const existing = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const template = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
existing.defaultProvider = template.defaultProvider;
existing.defaultModel = template.defaultModel;
existing.assistantName = template.assistantName || existing.assistantName || 'Helios';
// Merge enabledModels (additive union)
const tModels = new Set(template.enabledModels || []);
const eModels = new Set(existing.enabledModels || []);
existing.enabledModels = [...new Set([...eModels, ...tModels])].sort();
// Merge skills (additive union by name)
const pkgKey = (p) => typeof p === 'string' ? p : (p.name || p.source || JSON.stringify(p));
const eSkillKeys = new Set((existing.skills || []).map(pkgKey));
for (const s of (template.skills || [])) { if (!eSkillKeys.has(pkgKey(s))) (existing.skills = existing.skills || []).push(s); }
// Merge packages (additive union by name)
const ePkgKeys = new Set((existing.packages || []).map(pkgKey));
for (const p of (template.packages || [])) { if (!ePkgKeys.has(pkgKey(p))) (existing.packages = existing.packages || []).push(p); }
// Merge extensions (additive union by key)
const eExtKeys = new Set((existing.extensions || []).map(pkgKey));
for (const e of (template.extensions || [])) { if (!eExtKeys.has(pkgKey(e))) (existing.extensions = existing.extensions || []).push(e); }
// Preserve boolean settings from template
for (const k of ['enableSkillCommands','hideThinkingBlock','quietStartup']) {
  if (template[k] !== undefined && existing[k] === undefined) existing[k] = template[k];
}
fs.writeFileSync(process.argv[1], JSON.stringify(existing, null, 2) + '\n');
console.log('Merged provider config via node fallback');
" -- "$PI_AGENT_DIR/settings.json" "$PROVIDER_CONFIG" && merge_ok=true || true
    fi

    if [[ "$merge_ok" == false ]]; then
      warn "JSON merge failed (python3 and node both unavailable or errored)"
      warn "Copying provider template as settings.json"
      cp "$PROVIDER_CONFIG" "$PI_AGENT_DIR/settings.json"
    fi
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
      bash -c "cd '$sg_dir' && npm install --legacy-peer-deps --no-audit --no-fund 2>&1" || {
      warn "Dependency install failed — HEMA memory and code parsing will be limited"
      info "Installing neo4j-driver + tree-sitter — see $LOG_FILE for details"
      info "You can retry: cd '$sg_dir' && npm install --legacy-peer-deps"
    }
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
  if [[ ! -d "$PI_AGENT_DIR/.git" ]]; then
    info "Tarball install — git hooks not applicable"
    return 0
  fi
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
    local allowlist_ok=false
    if command -v python3 &>/dev/null && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
pkgs = data.get('packages', [])
if 'neo4j-driver' not in pkgs:
    pkgs.append('neo4j-driver')
    data['packages'] = pkgs
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('added')
else:
    print('ok')
" "$allowlist" 2>/dev/null; then
      allowlist_ok=true
    elif command -v node &>/dev/null && node -e "
const fs = require('fs');
const p = process.argv[1];
const data = JSON.parse(fs.readFileSync(p, 'utf8'));
const pkgs = data.packages || [];
if (!pkgs.includes('neo4j-driver')) {
  pkgs.push('neo4j-driver');
  data.packages = pkgs;
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + '\n');
  console.log('added');
} else { console.log('ok'); }
" -- "$allowlist" 2>/dev/null; then
      allowlist_ok=true
    fi
    if [[ "$allowlist_ok" == true ]]; then
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

# ─── Runtime Contract: persist resolved Memgraph + Ollama settings ────────────
#
# Priority (container resolution):
#   1. Existing valid memgraph.env (reuse if MEMGRAPH_CONTAINER still running)
#   2. Exact running container named 'memgraph'
#   3. Compose-labeled Memgraph container (label com.docker.compose.service=memgraph)
#   4. Legacy fallback 'familiar-graph-1'
#
# Output: ~/.pi/agent/runtime/memgraph.env (KEY=VALUE, one per line, no spaces)
#
persist_runtime_contract() {
  local resolved_container="${1:-}"
  local runtime_dir="$PI_AGENT_DIR/runtime"
  local contract_file="$runtime_dir/memgraph.env"

  # Step 1 — reuse existing contract if its container is still alive
  if [[ -f "$contract_file" ]]; then
    local existing_name
    existing_name=$(grep '^MEMGRAPH_CONTAINER=' "$contract_file" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    if [[ -n "$existing_name" ]] && docker ps --format '{{.Names}}' | grep -q "^${existing_name}$" 2>/dev/null; then
      info "Runtime contract valid — container $existing_name still running (no update needed)"
      return 0
    fi
  fi

  # Step 2 — use caller-resolved container if provided
  if [[ -z "$resolved_container" ]]; then
    # Priority: exact 'memgraph' → compose-label → legacy 'familiar-graph-1'
    local _ps_names
    _ps_names=$(docker ps --format '{{.Names}}' 2>/dev/null || true)
    for _mgn in memgraph familiar-graph-1; do
      if echo "$_ps_names" | grep -q "^${_mgn}$" 2>/dev/null; then
        resolved_container="$_mgn"
        break
      fi
    done
    # Compose-label discovery if still unresolved
    if [[ -z "$resolved_container" ]]; then
      local _compose_name
      _compose_name=$(docker ps --format '{{.Names}}\t{{.Labels}}' 2>/dev/null \
        | grep -i 'com.docker.compose.service=memgraph' | head -1 | awk '{print $1}' || true)
      [[ -n "$_compose_name" ]] && resolved_container="$_compose_name"
    fi
    # Default to nominal 'memgraph' if nothing is running
    [[ -z "$resolved_container" ]] && resolved_container="memgraph"
  fi

  mkdir -p "$runtime_dir"
  {
    echo "# Helios Graph Runtime Contract — auto-generated by installer"
    echo "# Do not hand-edit; re-run installer to refresh."
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "MEMGRAPH_CONTAINER=${resolved_container}"
    echo "MEMGRAPH_BOLT_URL=bolt://127.0.0.1:7687"
    echo "MEMGRAPH_HOST=127.0.0.1"
    echo "MEMGRAPH_PORT=7687"
    echo "MEMGRAPH_USER=memgraph"
    echo "MEMGRAPH_PASS=memgraph"
    echo "OLLAMA_URL=http://localhost:11434"
    echo "HELIOS_GRAPH_BOOTSTRAP_STATE_DIR=$PI_AGENT_DIR/state/codebase-bootstrap"
  } > "$contract_file"
  success "Runtime contract written: $contract_file (container: $resolved_container)"
}

setup_memgraph() {
  step "Memgraph (Knowledge Graph)"

  # Check container runtime (OrbStack, Docker, Colima, etc.)
  local container_runtime=""
  if command -v orb &>/dev/null || command -v orbctl &>/dev/null; then
    container_runtime="OrbStack"
    # OrbStack provides docker CLI — ensure it's available
    if ! command -v docker &>/dev/null; then
      warn "OrbStack detected but 'docker' CLI not on PATH"
      info "Run: orb setup docker"
      info "Then re-run the installer to set up Memgraph"
      return 0
    fi
  elif command -v docker &>/dev/null; then
    container_runtime="Docker"
  fi

  if [[ -z "$container_runtime" ]]; then
    warn "No container runtime found — Memgraph will be skipped"
    info "Install OrbStack (recommended): https://orbstack.dev"
    info "Or Docker Engine / Colima / Podman"
    info "Then re-run the installer to set up Memgraph"
    INSTALL_WARNINGS+=("Memgraph skipped — install Docker or OrbStack, then re-run installer")
    return 0
  fi

  success "Container runtime: $container_runtime"

  if ! docker info &>/dev/null 2>&1; then
    warn "Container runtime (OrbStack/Docker) is installed but not running — start OrbStack (or your container runtime)"
    info "Then re-run the installer to set up Memgraph"
    return 0
  fi

  # Check if a Memgraph container already exists
  # Priority: exact 'memgraph' → legacy 'familiar-graph-1'
  local mg_container=""
  for name in memgraph familiar-graph-1; do
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

  # Apply graph schema — resolve running container (memgraph first, then legacy fallback)
  local mg_running=""
  for _mn in memgraph familiar-graph-1; do
    if docker ps --format '{{.Names}}' | grep -q "^${_mn}$" 2>/dev/null; then
      mg_running="$_mn"; break
    fi
  done
  local schema="$PI_AGENT_DIR/skills/skill-graph/scripts/schema.cypher"
  if [[ -n "$mg_running" ]] && [[ -f "$schema" ]]; then
    docker exec -i "$mg_running" mgconsole --username memgraph --password memgraph \
      < "$schema" >> "$LOG_FILE" 2>&1 && info "Graph schema applied" || true
  fi

  # Persist the resolved runtime contract
  persist_runtime_contract "$mg_running"
}

# ─── Ollama (Local Embeddings) ────────────────────────────────────────────────
setup_ollama() {
  step "Ollama (Local Embeddings — nomic-embed-text)"

  if ! command -v ollama &>/dev/null; then
    info "Ollama not found — skipping local embeddings"
    info "To enable semantic search later: brew install ollama && ollama pull nomic-embed-text"
    INSTALL_WARNINGS+=("Ollama skipped — install from ollama.ai for local embeddings")
    return 0
  fi

  success "Ollama installed"

  # Ensure Ollama is running
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    info "Starting Ollama..."
    if pgrep -x ollama &>/dev/null || launchctl list 2>/dev/null | grep -q com.ollama; then
      success "Ollama already running (managed by system)"
    else
      nohup ollama serve >> "$LOG_FILE" 2>&1 &
      disown 2>/dev/null || true
    fi
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
  # nomic-embed-text is primary (274MB, native 768d), granite-embedding is fallback (62MB)
  for model in nomic-embed-text granite-embedding; do
    if ollama list 2>/dev/null | awk '{print $1}' | grep -q "^${model}:"; then
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
    timeout 30 uvx --from mcp-memgraph mcp-memgraph --help >> "$LOG_FILE" 2>&1 || true
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
    server_count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1])).get('mcpServers',{})))" "$mcp_file" 2>/dev/null || echo "0")
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
import json, os, sys
target = sys.argv[1]
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
" "$mcp_file" 2>/dev/null && success "mcp.json written (figma-remote, memgraph, github)" || warn "Could not write mcp.json"
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
    read -t 120 -rs key_val || key_val=""
    echo ""  # newline after silent read

    if [[ -n "$key_val" ]]; then
      # Update the env file safely (avoid shell injection from unescaped values)
      grep -v "^${key_name}=" "$env_file" > "${env_file}.tmp" 2>/dev/null || true
      printf '%s=%s\n' "${key_name}" "${key_val}" >> "${env_file}.tmp"
      mv "${env_file}.tmp" "$env_file"
      success "$key_name saved"
    else
      warn "$key_name skipped — add to $env_file later"
      INSTALL_WARNINGS+=("$key_name not set — edit ~/.pi/agent/.env")
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
      read -t 120 -r aws_region || aws_region=""
      aws_region="${aws_region:-us-east-1}"
      grep -v "^AWS_DEFAULT_REGION=" "$env_file" > "${env_file}.tmp" 2>/dev/null || true
      printf '%s=%s\n' "AWS_DEFAULT_REGION" "${aws_region}" >> "${env_file}.tmp"
      mv "${env_file}.tmp" "$env_file"
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
    # L4 fix: use first-'='-only split so values containing '=' (e.g. base64
    # API keys, URLs with query strings like https://host?a=b) are preserved
    # verbatim.  The previous approach (IFS-equals-read) relied on bash re-joining
    # extra fields which is fragile for API keys that contain '=' padding.
    while IFS= read -r _env_line; do
      # Strip leading whitespace and skip comments / blanks
      _env_line="${_env_line#"${_env_line%%[! ]*}"}"
      [[ -z "$_env_line" || "$_env_line" == \#* ]] && continue
      # Split on FIRST '=' only
      _env_key="${_env_line%%=*}"
      _env_val="${_env_line#*=}"
      _env_key="${_env_key#export }"            # strip optional 'export ' prefix
      _env_key="${_env_key#"${_env_key%%[! ]*}"}" # trim leading whitespace
      _env_key="${_env_key%"${_env_key##*[! ]}"}" # trim trailing whitespace
      _env_val="${_env_val#"${_env_val%%[! ]*}"}" # trim leading whitespace
      _env_val="${_env_val%"${_env_val##*[! ]}"}" # trim trailing whitespace
      _env_val="${_env_val#\"}" ; _env_val="${_env_val%\"}"  # strip double quotes
      _env_val="${_env_val#\'}" ; _env_val="${_env_val%\'}"  # strip single quotes
      [[ "$_env_key" =~ ^[A-Z_][A-Z_0-9]*$ ]] && [[ -n "$_env_val" ]] && export "$_env_key=$_env_val"
    done < "$env_file"
    success "API keys loaded into current session"
  fi

  warn "Restart your terminal or run: source $shell_profile"
}

# ─── Familiar Skills ──────────────────────────────────────────────────────────
setup_familiar() {
  step "Familiar Skills (optional)"

  echo ""
  ask "Install Familiar skills? (Gmail, Calendar, Drive, transcription) [y/N]:"
  read -t 120 -r install_familiar || install_familiar=""
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
  read -t 120 -r confirm_familiar || confirm_familiar=""
  if [[ ! "$confirm_familiar" =~ ^[Yy]$ ]]; then
    warn "Familiar setup skipped"
    return 0
  fi

  if ! run_with_spinner "Cloning familiar → ~/.familiar/" \
    git clone --single-branch --depth 1 "https://$FAMILIAR_REPO.git" "$FAMILIAR_DIR"; then
    warn "Could not clone Familiar (repository may require authentication)"
    info "To install Familiar later: gh auth login && git clone https://$FAMILIAR_REPO.git ~/.familiar"
    info "Familiar enables Gmail, Calendar, and Drive skills — it's optional."
    INSTALL_WARNINGS+=("Familiar skills skipped — repo requires GitHub authentication")
    return 0
  fi
  success "Familiar cloned to $FAMILIAR_DIR"

  # Check if Familiar needs dependency installation
  if [[ -f "$FAMILIAR_DIR/pnpm-lock.yaml" ]]; then
    if command -v pnpm &>/dev/null; then
      ask "Run pnpm install for Familiar dependencies? [y/N]:"
      read -t 120 -r run_pnpm || run_pnpm=""
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

# ─── Deduplicate Skills & Extensions ──────────────────────────────────────────
dedup_skills_extensions() {
  step "Deduplicating Skills & Extensions"

  # Remove legacy local extensions that are now provided as git packages
  local legacy_exts=("pi-review-loop")
  for legacy_ext in "${legacy_exts[@]}"; do
    if [[ -d "$PI_AGENT_DIR/extensions/$legacy_ext" ]] && \
       [[ -d "$PI_AGENT_DIR/git/github.com/nicobailon/$legacy_ext" ]]; then
      info "Removing legacy extension $legacy_ext (now provided by git package)"
      rm -rf "$PI_AGENT_DIR/extensions/$legacy_ext"
    fi
  done

  local conflicts=0

  # Remove legacy ~/.familiar/skills that duplicate ~/.pi/agent/skills
  if [[ -d "$FAMILIAR_DIR/skills" ]] && [[ -d "$PI_AGENT_DIR/skills" ]]; then
    for familiar_skill in "$FAMILIAR_DIR/skills"/*/SKILL.md; do
      [[ -f "$familiar_skill" ]] || continue
      local skill_name
      skill_name=$(basename "$(dirname "$familiar_skill")")
      if [[ -d "$PI_AGENT_DIR/skills/$skill_name" ]]; then
        info "Removing duplicate skill from ~/.familiar/skills/$skill_name (already in ~/.pi/agent/skills/)"
        rm -rf "$FAMILIAR_DIR/skills/$skill_name"
        ((conflicts++)) || true
      fi
    done
  fi

  # Remove duplicate extension directories when both local and git-package versions exist
  if [[ -d "$PI_AGENT_DIR/extensions" ]] && [[ -d "$PI_AGENT_DIR/git" ]]; then
    for ext_dir in "$PI_AGENT_DIR/extensions"/*/; do
      [[ -d "$ext_dir" ]] || continue
      local ext_name
      ext_name=$(basename "$ext_dir")
      # Check if same extension exists as a git package (match package root only: dir/$ext_name/package.json)
      local git_ext
      git_ext=$(find "$PI_AGENT_DIR/git" -maxdepth 4 -type d -name "$ext_name" 2>/dev/null | while read -r d; do
        if [[ -f "$d/package.json" ]] && [[ -f "$d/index.ts" || -f "$d/index.js" ]]; then
          echo "$d"; break
        fi
      done)
      if [[ -n "$git_ext" ]]; then
        info "Removing duplicate extension ~/.pi/agent/extensions/$ext_name/ (installed as git package)"
        rm -rf "$ext_dir"
        ((conflicts++)) || true
      fi
    done
  fi

  if [[ "$conflicts" -gt 0 ]]; then
    success "Cleaned up $conflicts duplicate skill/extension registration(s)"
  else
    success "No duplicates found"
  fi
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
    if [[ "$agent_count" -ge 48 ]]; then
      success "Agents: $agent_count (expect 48+)"
    else
      warn "Agents: $agent_count (expected 48+) — packages may not be fully installed"
    fi
  fi

  # Count skills
  local skill_count=0
  skill_count=$(
    (find "$PI_AGENT_DIR/skills" -name "SKILL.md" 2>/dev/null
     find "$FAMILIAR_DIR/skills" -name "SKILL.md" 2>/dev/null
     true) | wc -l | tr -d ' '
  )
  if [[ "$skill_count" -ge 16 ]]; then
    success "Skills: $skill_count (expect 16+)"
  else
    warn "Skills: $skill_count (expected 16+)"
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
    keys_set=$(grep -v '^#' "$env_file" 2>/dev/null | grep -v '^$' | grep -v '=$' | wc -l | tr -d ' ') || keys_set=0
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
    configured_provider=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('defaultProvider','?'))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
      node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultProvider||'?')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
    success "settings.json: provider=$configured_provider"
  fi

  echo ""
  if [[ "$all_ok" == "true" ]]; then
    echo -e "  ${GREEN}${BOLD}✓ Verification passed${RESET}"
  else
    echo -e "  ${YELLOW}${BOLD}⚠ Verification completed with warnings — see above${RESET}"
  fi

  if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null 2>&1; then
      success "GitHub CLI authenticated"
    else
      warn "GitHub CLI not authenticated — run: gh auth login"
    fi
  fi
}

# ─── Quick-Start Guide ────────────────────────────────────────────────────────
print_quickstart() {
  if [[ ${#INSTALL_WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠ Components that need attention:${RESET}"
    for w in "${INSTALL_WARNINGS[@]}"; do
      echo -e "    ${YELLOW}•${RESET} $w"
    done
  fi
  echo ""
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${GREEN}  ✓ Helios + Pi Installation Complete!${RESET} ${DIM}(installer v${INSTALLER_VERSION})${RESET}"
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  # Ensure PATH is set for remainder of installer + user session
  if ! command -v helios &>/dev/null && [[ -f "$HOME/.local/bin/helios" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    echo ""
    warn "Run 'source ~/.zshrc' (or restart terminal) for the 'helios' command to work"
  fi
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
    keys_missing=$(grep -c '^[A-Z_]*=$' "$PI_AGENT_DIR/.env" 2>/dev/null || echo "0")
    keys_missing="${keys_missing//[^0-9]/}"
    keys_missing="${keys_missing:-0}"
    if [[ "${keys_missing:-0}" -gt 0 ]]; then
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
    [[ "$arg" == "--update" ]] && { UPDATE_MODE=true; return 0; }
  done

  # If agent dir exists with a configured provider and .env, this is an update
  if [[ -d "$PI_AGENT_DIR" ]] && [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local current_provider=""
    local current_model=""

    # Try python3 first, fall back to node, fall back to grep
    if command -v python3 &>/dev/null; then
      current_provider=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('defaultProvider',''))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
      current_model=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('defaultModel',''))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
    elif command -v node &>/dev/null; then
      current_provider=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultProvider||'')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
      current_model=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultModel||'')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
    else
      # Last resort: grep for the key (handles simple cases)
      current_provider=$(grep -o '"defaultProvider"[[:space:]]*:[[:space:]]*"[^"]*"' "$PI_AGENT_DIR/settings.json" 2>/dev/null | head -1 | sed 's/.*: *"//;s/"//' || echo "")
    fi

    if [[ -n "$current_provider" ]] && [[ "$current_provider" != "null" ]] && [[ "$current_provider" != "undefined" ]]; then
      if [[ -f "$PI_AGENT_DIR/.env" ]]; then
        UPDATE_MODE=true
        SELECTED_PROVIDER="$current_provider"
        SELECTED_MODEL="${current_model:-}"
        info "Existing install detected (provider: $SELECTED_PROVIDER)"
        info "Running in update mode — skipping provider/key prompts"
        info "To re-run full setup: bash install.sh --fresh"
        echo ""
      fi
    fi
  fi
}

# ─── Bootstrap Scheduling ────────────────────────────────────────────────────
#
# Writes queued state files and launches bootstrap-codebases.js in the background.
# Install is only considered successful when bootstrap completes OR durable queued
# state files are written and the background job is launched successfully.
#
schedule_bootstrap() {
  step "Codebase Bootstrap"

  local bootstrap_script="$PI_AGENT_DIR/skills/skill-graph/scripts/bootstrap-codebases.js"
  local bootstrap_dir="$PI_AGENT_DIR/state/codebase-bootstrap"

  if [[ ! -f "$bootstrap_script" ]]; then
    warn "bootstrap-codebases.js not found — skipping bootstrap scheduling"
    info "Re-run installer after pulling latest helios-agent to enable auto-bootstrap"
    return 0
  fi

  if ! command -v node &>/dev/null; then
    warn "node not found — cannot schedule bootstrap"
    return 0
  fi

  # Ensure state dir exists
  mkdir -p "$bootstrap_dir"

  # Determine targets and write queued state files
  local targets=("$PI_AGENT_DIR")
  local installer_cwd
  installer_cwd="$(pwd)"
  local resolved_agent
  resolved_agent="$(cd "$PI_AGENT_DIR" 2>/dev/null && pwd || echo "$PI_AGENT_DIR")"

  if [[ "$installer_cwd" != "$resolved_agent" ]] && [[ -d "$installer_cwd/.git" ]]; then
    targets+=("$installer_cwd")
    info "Bootstrap targets: ~/.pi/agent + CWD ($installer_cwd)"
  else
    info "Bootstrap target: ~/.pi/agent"
  fi

  # Write queued state files for each target (durable evidence before launch)
  local all_queued=true
  for target_path in "${targets[@]}"; do
    local status_key
    status_key=$(python3 -c "import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])" "$target_path" 2>/dev/null || \
                 node -e "const c=require('crypto');process.stdout.write(c.createHash('sha256').update(process.argv[1]).digest('hex').slice(0,16))" -- "$target_path" 2>/dev/null || echo "")
    if [[ -z "$status_key" ]]; then
      warn "Cannot compute status key for $target_path — skipping"
      all_queued=false
      continue
    fi
    local status_file="$bootstrap_dir/${status_key}.json"

    # Only write queued if not already running/complete
    local existing_state=""
    existing_state=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('state',''))" "$status_file" 2>/dev/null || echo "")
    if [[ "$existing_state" == "running" ]] || [[ "$existing_state" == "complete" ]]; then
      info "Bootstrap already $existing_state for $target_path — keeping"
      continue
    fi

    python3 -c "
import json, datetime, os, sys
target = sys.argv[1]
sf = sys.argv[2]
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
existing = {}
if os.path.exists(sf):
    try:
        with open(sf) as f:
            existing = json.load(f)
    except: pass
record = {
    'state': 'queued',
    'targetPath': target,
    'queuedAt': now,
    'startedAt': None,
    'completedAt': None,
    'error': None,
    'indexedFiles': 0,
    'totalChunks': 0,
}
existing.update(record)
os.makedirs(os.path.dirname(sf), exist_ok=True)
with open(sf, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
print('queued: ' + target)
" "$target_path" "$status_file" 2>/dev/null && info "Queued bootstrap: $target_path" || {
      warn "Failed to write bootstrap state for $target_path"
      all_queued=false
    }
  done

  if [[ "$all_queued" == false ]]; then
    warn "Some bootstrap state files could not be written"
  fi

  # Launch bootstrap-codebases.js in the background
  local bootstrap_log="$PI_AGENT_DIR/logs/bootstrap-codebases.log"
  mkdir -p "$(dirname "$bootstrap_log")"

  # Pass installer CWD via env so bootstrap knows which repo to add
  if BOOTSTRAP_CWD="$installer_cwd" nohup node "$bootstrap_script" \
      >> "$bootstrap_log" 2>&1 &
  then
    local bg_pid=$!
    disown "$bg_pid" 2>/dev/null || true
    success "Bootstrap job launched (PID $bg_pid) — indexing will complete in background"
    info "Log: $bootstrap_log"
    info "Status: ls $bootstrap_dir/"
  else
    warn "Failed to launch bootstrap background job"
    info "Manual run: node $bootstrap_script"
  fi
}

# ─── Deduplicate Extensions ───────────────────────────────────────────────────
deduplicate_extensions() {
  step "Deduplicating Extensions"
  local dominated_exts=("pi-review-loop")
  for ext in "${dominated_exts[@]}"; do
    local local_ext="$PI_AGENT_DIR/extensions/$ext"
    local git_ext="$PI_AGENT_DIR/git/github.com/nicobailon/$ext"
    if [[ -d "$local_ext" ]] && [[ -d "$git_ext" ]]; then
      info "Removing duplicate: $local_ext (git package $git_ext takes precedence)"
      rm -rf "$local_ext"
      success "Removed duplicate local extension: $ext (git package takes precedence)"
    fi
  done
}

# ─── Optional System Dependencies ─────────────────────────────────────────────
install_optional_deps() {
  step "Optional Dependencies"

  # ffmpeg — needed for video processing, surf-cli, yt-dlp
  if command -v ffmpeg &>/dev/null; then
    success "ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')"
  else
    info "Installing ffmpeg (video processing, surf-cli)..."
    if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
      brew install ffmpeg >> "$LOG_FILE" 2>&1 && success "ffmpeg installed" || warn "ffmpeg: install manually — brew install ffmpeg"
    elif command -v apt-get &>/dev/null; then
      sudo apt-get install -y ffmpeg >> "$LOG_FILE" 2>&1 && success "ffmpeg installed" || warn "ffmpeg: install manually"
    else
      warn "ffmpeg not found — install manually for video features"
    fi
  fi

  # yt-dlp — needed for YouTube video/transcript features
  if command -v yt-dlp &>/dev/null; then
    success "yt-dlp $(yt-dlp --version 2>/dev/null)"
  else
    info "Installing yt-dlp (YouTube video/transcript)..."
    if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
      brew install yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || true
    elif command -v pipx &>/dev/null; then
      pipx install yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || warn "yt-dlp: install manually"
    elif command -v pip3 &>/dev/null; then
      pip3 install --user yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || warn "yt-dlp: install manually — pip3 install --user yt-dlp"
    else
      warn "yt-dlp not found — install manually for YouTube features"
    fi
  fi

  # Vector dimension migration (ensures Memgraph schema_version=2)
  local fix_script="$PI_AGENT_DIR/scripts/fix-vector-dimensions.sh"
  if [[ -f "$fix_script" ]] && command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' | grep -q "^memgraph$" 2>/dev/null; then
      bash "$fix_script" >> "$LOG_FILE" 2>&1 && info "Vector dimensions verified" || true
    fi
  fi

  # Engineering skill (already in agent repo, no symlink needed)
  if [[ -d "$PI_AGENT_DIR/skills/engineering" ]]; then
    success "engineering skill (in ~/.pi/agent/skills/)"
  fi
}

# ─── Boot Services (LaunchAgents / cron) ──────────────────────────────────────
setup_boot_services() {
  step "Boot Services"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    local la_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$la_dir"

    # Memgraph auto-start on login
    local mg_plist="$la_dir/com.helios.memgraph.plist"
    if [[ ! -f "$mg_plist" ]]; then
      local docker_path
      docker_path=$(command -v docker 2>/dev/null || echo "/usr/local/bin/docker")
      cat > "$mg_plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.helios.memgraph</string>
  <key>ProgramArguments</key>
  <array><string>${docker_path}</string><string>start</string><string>memgraph</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/helios-memgraph.log</string>
  <key>StandardErrorPath</key><string>/tmp/helios-memgraph.err</string>
</dict>
</plist>
PLIST_EOF
      launchctl bootstrap "gui/$(id -u)" "$mg_plist" 2>/dev/null || launchctl load -w "$mg_plist" 2>/dev/null
      success "Memgraph LaunchAgent"
    else success "Memgraph LaunchAgent (exists)"; fi

    # Skill-graph daily ingestion at 2 AM
    local sg_plist="$la_dir/com.helios.skill-graph-daily.plist"
    if [[ ! -f "$sg_plist" ]]; then
      cat > "$sg_plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.helios.skill-graph-daily</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${HOME}/.pi/agent/scripts/ingest-session-decisions.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>${HOME}/.pi/agent/.skill-graph-daily.log</string>
  <key>StandardErrorPath</key><string>${HOME}/.pi/agent/.skill-graph-daily.err</string>
</dict>
</plist>
PLIST_EOF
      launchctl bootstrap "gui/$(id -u)" "$sg_plist" 2>/dev/null || launchctl load -w "$sg_plist" 2>/dev/null
      success "Skill-graph daily LaunchAgent"
    else success "Skill-graph daily LaunchAgent (exists)"; fi

    # Session consolidation (hourly)
    local con_plist="$la_dir/com.helios.consolidation.plist"
    if [[ ! -f "$con_plist" ]]; then
      if [[ -f "$PI_AGENT_DIR/scripts/com.helios.consolidation.plist" ]]; then
        cp "$PI_AGENT_DIR/scripts/com.helios.consolidation.plist" "$con_plist"
      else
        cat > "$con_plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.helios.consolidation</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${HOME}/.pi/agent/scripts/consolidate-sessions.sh</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>StandardOutPath</key><string>${HOME}/.pi/agent/.consolidation.log</string>
  <key>StandardErrorPath</key><string>${HOME}/.pi/agent/.consolidation.err</string>
</dict>
</plist>
PLIST_EOF
      fi
      launchctl bootstrap "gui/$(id -u)" "$con_plist" 2>/dev/null || launchctl load -w "$con_plist" 2>/dev/null
      success "Session consolidation LaunchAgent"
    else success "Session consolidation LaunchAgent (exists)"; fi

    # Ollama: skip if already managed by Ollama.app
    if launchctl list 2>/dev/null | grep -q "com.ollama"; then
      success "Ollama auto-start (managed by Ollama.app)"
    else
      info "Ollama: install via Ollama.app for auto-start, or manage manually"
    fi

  elif is_wsl; then
    # WSL: no systemd by default, no persistent cron. Use Windows Task Scheduler hints.
    info "WSL detected — background services work differently here"
    echo ""
    echo -e "  ${DIM}WSL doesn't auto-start background services like macOS/Linux.${RESET}"
    echo -e "  ${DIM}You'll need to start services manually each session:${RESET}"
    echo ""
    echo -e "    ${BOLD}# Start Memgraph (if using Docker Desktop):${RESET}"
    echo -e "    ${DIM}docker start helios-memgraph 2>/dev/null || true${RESET}"
    echo ""
    echo -e "    ${BOLD}# Start Ollama:${RESET}"
    echo -e "    ${DIM}ollama serve &${RESET}"
    echo ""
    echo -e "  ${DIM}Tip: Add these to your ~/.bashrc to auto-start on WSL launch.${RESET}"
    echo ""
    
    # Offer to add auto-start to .bashrc
    local wsl_autostart_marker="# Helios WSL auto-start"
    if ! grep -q "$wsl_autostart_marker" "$HOME/.bashrc" 2>/dev/null; then
      ask "Add Helios service auto-start to ~/.bashrc? [y/N]:"
      read -t 120 -r add_autostart || add_autostart=""
      if [[ "$add_autostart" =~ ^[Yy]$ ]]; then
        cat >> "$HOME/.bashrc" << 'WSLSTART'

# Helios WSL auto-start
# Start Docker containers and Ollama on WSL session launch
# Start Memgraph if Docker is ready
if docker info &>/dev/null 2>&1; then
  (docker start helios-memgraph 2>/dev/null &)
else
  echo "[helios] Docker not ready — start Docker Desktop, then: docker start helios-memgraph"
fi
# Start Ollama if not already running
if ! pgrep -x ollama >/dev/null 2>&1; then
  (nohup ollama serve >> /tmp/ollama.log 2>&1 & disown) 2>/dev/null
fi
WSLSTART
        success "Added Helios auto-start to ~/.bashrc"
      fi
    fi

  elif [[ "$(uname -s)" == "Linux" ]]; then
    # Docker restart policy (already in compose, but ensure)
    docker update --restart=unless-stopped memgraph 2>/dev/null && success "Memgraph restart policy" || true

    # Ollama systemd
    if command -v systemctl &>/dev/null; then
      systemctl --user enable ollama 2>/dev/null && success "Ollama systemd enabled" || true
    fi

    # Cron for skill-graph daily
    if ! crontab -l 2>/dev/null | grep -q "skill-graph"; then
      (crontab -l 2>/dev/null; echo "0 2 * * * ${HOME}/.pi/agent/scripts/ingest-session-decisions.sh >> ${HOME}/.pi/agent/.skill-graph-daily.log 2>&1") | crontab -
      success "Skill-graph daily cron"
    else success "Skill-graph daily cron (exists)"; fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        echo "Usage: bash install.sh [options]"
        echo ""
        echo "Options:"
        echo "  --fresh    Force full interactive setup (re-prompt provider, keys)"
        echo "  --update   Run in update mode (skip interactive prompts)"
        echo "  --help     Show this help message"
        echo ""
        echo "First install (team members):"
        echo "  curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"
        echo ""
        echo "Re-run / update:"
        echo "  helios update"
        exit 0
        ;;
    esac
  done

  print_banner
  echo -e "  ${BOLD}Starting Helios installation...${RESET}"
  echo -e "  ${DIM}This will install Pi CLI, Helios agent, and supporting tools.${RESET}"
  echo -e "  ${DIM}Estimated time: 3-5 minutes.${RESET}"
  echo ""
  detect_update_mode "$@"

  # ─── Check for --fresh flag (for checkpoint system) ──────────────────────
  FRESH_INSTALL=false
  for _arg in "$@"; do
    [[ "$_arg" == "--fresh" ]] && FRESH_INSTALL=true
  done
  export FRESH_INSTALL

  # ─── Resume offer ────────────────────────────────────────────────────────
  if type load_checkpoint &>/dev/null; then
    _last_checkpoint=$(load_checkpoint)
    if [[ "$_last_checkpoint" -gt 0 ]] && [[ "$FRESH_INSTALL" == false ]] && [[ "$UPDATE_MODE" == false ]]; then
      echo ""
      echo -e "  ${CYAN}ℹ${RESET}  Previous install reached step $_last_checkpoint of $TOTAL_STEPS"
      ask "Resume from where you left off? [Y/n]:"
      read -t 30 -r _resume_choice || _resume_choice="y"
      if [[ "$_resume_choice" =~ ^[Nn]$ ]]; then
        clear_checkpoint
      else
        echo -e "  ${GREEN}✓${RESET} Resuming — skipping completed steps"
      fi
      echo ""
    fi
  fi

  if [[ "$UPDATE_MODE" == false ]]; then
    run_step "Prerequisites"     check_prerequisites
    run_step "Pi CLI"            install_pi
    run_step "Helios Agent"      setup_helios_agent
    run_step "Helios CLI"        install_helios_cli
    run_step "Provider Selection" select_provider
  fi

  # Ensure Pi is available before running packages (may have been uninstalled)
  if ! command -v pi &>/dev/null; then
    warn "Pi CLI not found — installing..."
    install_pi
  fi

  run_step "Pi Packages"       install_packages
  deduplicate_extensions
  run_step "Skill Dependencies" install_skill_deps
  run_step "Governance Deps"    install_governance_deps

  if [[ "$UPDATE_MODE" == false ]]; then
    run_step "Git Hooks"         install_git_hooks
    run_step "Dep Allowlist"     setup_dep_allowlist
    run_step "Memgraph"          setup_memgraph
    run_step "Ollama"            setup_ollama
    run_step "MCP Servers"       setup_mcp_servers
    run_step "Optional Deps"     install_optional_deps
    setup_boot_services   # LaunchAgents (macOS) / cron (Linux)
    schedule_bootstrap    # Queue + launch codebase indexing in background
    setup_api_keys        # Interactive: prompt for keys
    wire_env_to_shell     # Add .env sourcing to shell profile
    setup_familiar        # Interactive: optional Familiar install
  fi

  dedup_skills_extensions
  run_verification
  print_quickstart

  # Clear checkpoint on successful completion
  if type clear_checkpoint &>/dev/null; then
    clear_checkpoint
  fi

  # Ensure installer exit trap doesn't print error message on clean exit
  trap - EXIT
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
