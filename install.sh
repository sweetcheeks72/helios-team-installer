#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Team Installer
# =============================================================================
# Installs: Helios CLI, Helios Agent, 20 git packages, extensions, Familiar skills,
# API key setup
# =============================================================================
INSTALLER_VERSION="2.1.0"

set -euo pipefail
INSTALL_WARNINGS=()

# install.sh expects the full checked-out repository so it can source lib/*.
# If someone runs the raw file via `curl .../install.sh | bash`, hand off to
# the pipe-safe bootstrap entrypoint instead of crashing on BASH_SOURCE/lib paths.
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "${BASH_SOURCE[0]:-}" ]]; then
  echo "install.sh was run from stdin; switching to bootstrap.sh..."
  curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash -s -- "$@"
  exit $?
fi

# ─── Update Recursion Guard ───────────────────────────────────────────────────
# Prevents install.sh from calling itself recursively (e.g., helios update →
# install.sh → install_packages → helios update → install.sh).
if [[ "${_HELIOS_INSTALLER_RUNNING:-}" == "true" ]]; then
  echo "ERROR: Installer recursion detected — aborting re-entrant call." >&2
  echo "  The installer is already running in a parent process." >&2
  exit 0
fi
export _HELIOS_INSTALLER_RUNNING=true

# ─── Source error recovery library ────────────────────────────────────────────
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$INSTALLER_DIR/lib/error-recovery.sh" ]]; then
  # shellcheck source=lib/error-recovery.sh
  source "$INSTALLER_DIR/lib/error-recovery.sh"
fi

# ─── Source platform detection library ────────────────────────────────────────
if [[ -f "$INSTALLER_DIR/lib/platform.sh" ]]; then
  source "$INSTALLER_DIR/lib/platform.sh"
fi

# ─── Source containers library ────────────────────────────────────────────────
if [[ -f "$INSTALLER_DIR/lib/containers.sh" ]]; then
  source "$INSTALLER_DIR/lib/containers.sh"
fi

# ─── Source secrets manager library ───────────────────────────────────────────
if [[ -f "$INSTALLER_DIR/lib/secrets-manager.sh" ]]; then
  source "$INSTALLER_DIR/lib/secrets-manager.sh"
fi

# ─── Early arg check (before tty redirect) ───────────────────────────────────
CHECK_ONLY=false
DRY_RUN=false
LOCAL_PACKAGE=""
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
      echo "  --dry-run  Show what would happen without making changes"
      echo "  --check    Verify installation status without installing"
      echo "  --help     Show this help message"
      echo ""
      echo "Install or update:"
      echo "  curl -fsSL https://github.com/helios-agi/helios-team-installer/releases/latest/download/bootstrap.sh | bash"
      echo ""
      echo "Re-run / update:"
      echo "  helios update"
      exit 0
      ;;
    --check|--verify)
      CHECK_ONLY=true
      ;;
    --dry-run)
      DRY_RUN=true
      CHECK_ONLY=true
      ;;
    --local-package)
      ;;
  esac
  # Capture --local-package value (next arg)
  if [[ "$_arg" == "--local-package" ]]; then
    _capture_next=true
  elif [[ "${_capture_next:-}" == "true" ]]; then
    LOCAL_PACKAGE="$_arg"
    _capture_next=""
  fi
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "\n  ══════════════════════════════════════"
  echo -e "  ║  DRY RUN — no changes will be made  ║"
  echo -e "  ══════════════════════════════════════\n"
fi

# ─── Restore stdin from terminal (critical for curl|bash piping) ─────────────
# When run via `curl ... | bash`, stdin is the pipe (EOF after script downloads).
# Reopen stdin from /dev/tty so interactive `read` commands work.
if [[ ! -t 0 ]]; then
  if [[ "${DRY_RUN:-false}" == "true" ]] || [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    : # dry-run/check mode doesn't need interactive stdin
  elif [[ -e /dev/tty ]]; then
    exec < /dev/tty 2>/dev/null || true
  else
    echo "ERROR: No terminal available (/dev/tty). Run this script directly instead of piping." >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh -o /tmp/helios-bootstrap.sh && bash /tmp/helios-bootstrap.sh" >&2
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
# is_wsl and current_platform are provided by lib/platform.sh (sourced above).
# These fallback definitions are only used if the lib failed to load.
if ! declare -f is_wsl &>/dev/null; then
  is_wsl() {
    [[ -f /proc/version ]] && grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
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
fi

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
step()    {
  # Skip if already inside run_step (step_start handles the header)
  [[ "${_INSIDE_RUN_STEP:-}" == "true" ]] && return 0
  echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"
}
ask()     { echo -en "${MAGENTA}  ? ${RESET}$* "; }
_count()  { wc -l | tr -d ' '; }

# User files/dirs preserved during updates — single source of truth.
# Keep in sync with auto-update.ts RELEASE_MANIFEST (which lists managed files;
# everything NOT in that manifest is considered user data and preserved).
HELIOS_PRESERVE_FILES=(
  .env settings.json governance sessions .helios auth.json
  run-history.jsonl mcp.json dep-allowlist.json .secrets state
  models.json pi-messenger.json .update-state.json VERSION
  .update-log.jsonl .update-lock runtime
)

HELIOS_RELEASE_URL="https://github.com/helios-agi/helios-team-installer/releases/latest/download"

# ─── Platform/arch detection for arch-aware tarball selection ─────────────────
INST_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
INST_ARCH="$(uname -m)"
case "${INST_ARCH}" in
  aarch64) INST_ARCH="arm64" ;;
  x86_64)  INST_ARCH="x64" ;;
esac
# Prefer arch-specific tarball; fall back to universal if the arch-specific one
# is not available on the release server (e.g. older releases pre-multi-arch).
HELIOS_AGENT_TARBALL="helios-agent-latest-${INST_OS}-${INST_ARCH}.tar.gz"
HELIOS_AGENT_TARBALL_UNIVERSAL="helios-agent-latest.tar.gz"
HELIOS_CLI_RELEASE_URL="https://github.com/helios-agi/helios-installer/releases/latest/download"
FAMILIAR_REPO="github.com/helios-agi/familiar"
PI_AGENT_DIR="$HOME/.pi/agent"
FAMILIAR_DIR="$HOME/.familiar"
LOG_FILE="$INSTALLER_DIR/install.log"

LEGACY_PI_DIRS=(
  extensions
  lib
  git
  prompts
  skills
)

LEGACY_MARIO_SCOPE="@mariozechner"
LEGACY_NPM_PACKAGES=(
  @helios-agent/pi-coding-agent
  @helios-agent/cli
  "${LEGACY_MARIO_SCOPE}/pi-coding-agent"
  "${LEGACY_MARIO_SCOPE}/pi"
)

# ─── Migrate settings.json packages from git: (clone) to git/ (local path) ──
# Tarball bundles packages into ~/.pi/agent/git/..., so settings.json must
# reference them as local paths (git/github.com/...) not remote sources
# (git:github.com/...) which would trigger git clone against private repos.
_migrate_settings_packages() {
  local settings_file="$PI_AGENT_DIR/settings.json"
  [[ -f "$settings_file" ]] || return 0

  # Migrate URL-style git: prefix to local path style git/
  if grep -q '"git:github\.com/' "$settings_file" 2>/dev/null; then
    sed -i.bak 's|"git:github\.com/|"git/github.com/|g' "$settings_file"
    sed -i.bak "s|'git:github\.com/|'git/github.com/|g" "$settings_file"
    rm -f "${settings_file}.bak"
    info "Migrated settings.json packages: git: → git/ (local paths)"
  fi

  # Normalize legacy org names to helios-agi
  for _old_org in sweetcheeks72 nicobailon; do
    if grep -q "git/github\.com/${_old_org}/" "$settings_file" 2>/dev/null; then
      sed -i.bak "s|git/github\.com/${_old_org}/|git/github.com/helios-agi/|g" "$settings_file"
      rm -f "${settings_file}.bak"
      info "Migrated settings.json org: ${_old_org} → helios-agi"
    fi
  done
}

# Prune stale org directories from previous installs
_prune_stale_org_dirs() {
  for _stale_org in sweetcheeks72 nicobailon; do
    if [[ -d "$PI_AGENT_DIR/git/github.com/$_stale_org" ]]; then
      info "Removing stale org dir: git/github.com/$_stale_org/"
      rm -rf "$PI_AGENT_DIR/git/github.com/$_stale_org"
    fi
  done
}

# One-pass cleanup for machines that have mixed generations of Pi/Helios.
# The current tarball loader reads from ~/.pi/agent; legacy top-level ~/.pi/*
# directories can register duplicate tools and stale dependencies before the
# new runtime has a chance to win. Quarantine them instead of deleting.
doctor_legacy_install() {
  step "Legacy Install Doctor"

  local backup_root="$HOME/.pi-backups/doctor.$(date +%Y%m%d_%H%M%S)"
  local moved=0
  local legacy

  mkdir -p "$backup_root"

  for legacy in "${LEGACY_PI_DIRS[@]}"; do
    if [[ -e "$HOME/.pi/$legacy" ]]; then
      info "Quarantining legacy ~/.pi/$legacy"
      mv "$HOME/.pi/$legacy" "$backup_root/$legacy"
      ((moved++)) || true
    fi
  done

  if [[ "$moved" -gt 0 ]]; then
    success "Legacy ~/.pi paths moved to $backup_root"
  else
    rmdir "$backup_root" 2>/dev/null || true
    success "No legacy top-level ~/.pi paths found"
  fi

  # Ensure the freshly installed shim directory wins in this process.
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
  hash -r 2>/dev/null || true

  # Old global npm packages can hijack `pi`/`helios` and run their own
  # updater. Remove only known package names, and ignore machines without npm.
  if command -v npm &>/dev/null; then
    local installed=()
    local pkg
    for pkg in "${LEGACY_NPM_PACKAGES[@]}"; do
      if npm ls -g "$pkg" --depth=0 >/dev/null 2>&1; then
        installed+=("$pkg")
      fi
    done
    if [[ "${#installed[@]}" -gt 0 ]]; then
      info "Removing legacy global npm package(s): ${installed[*]}"
      npm uninstall -g "${installed[@]}" >/dev/null 2>&1 || \
        warn "Could not remove every legacy npm package; continuing with ~/.local/bin first in PATH"
      hash -r 2>/dev/null || true
    else
      success "No legacy global Helios packages found"
    fi
  fi
}

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
  ║              Team Installer  •  Helios Orchestrator            ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${RESET}"
  echo -e "  ${DIM}Log: $LOG_FILE${RESET}\n"
}

# ─── Timeout Wrapper (macOS lacks GNU timeout) ────────────────────────────────
_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    timeout "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$@"
  else
    local duration=$1; shift
    "$@" &
    local cmd_pid=$!
    ( sleep "$duration" && kill -9 "$cmd_pid" 2>/dev/null ) &
    local killer_pid=$!
    wait "$cmd_pid" 2>/dev/null
    local exit_code=$?
    kill "$killer_pid" 2>/dev/null 2>&1
    wait "$killer_pid" 2>/dev/null 2>&1
    return $exit_code
  fi
}

# ─── Retry with Exponential Backoff ──────────────────────────────────────────
# Usage: retry_with_backoff [max_attempts] [initial_delay_seconds] <command> [args...]
# Defaults: 3 attempts, 2s initial delay (doubles each retry)
retry_with_backoff() {
  local max_attempts="${1:-3}"
  local delay="${2:-2}"
  shift 2
  local cmd=("$@")
  local attempt=1
  while (( attempt <= max_attempts )); do
    if "${cmd[@]}"; then
      return 0
    fi
    if (( attempt < max_attempts )); then
      warn "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
      sleep "$delay"
      delay=$(( delay * 2 ))
    fi
    (( attempt++ ))
  done
  error "Failed after $max_attempts attempts: ${cmd[*]}"
  return 1
}

# ─── Progress Spinner ─────────────────────────────────────────────────────────
spin_pid=""
start_spinner() {
  local msg="${1:-Working...}"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  printf '\033[?25l'
  while true; do
    echo -ne "  ${CYAN}${frames[$i]}${RESET}  ${msg}\r" > /dev/tty 2>/dev/null || true
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
  # NOTE: stdin is /dev/null — commands passed here must not read stdin
  _timeout_cmd "${STEP_TIMEOUT:-300}" "$@" >> "$LOG_FILE" 2>"$tmp_err" </dev/null &
  local cmd_pid=$!
  # Use || cmd_exit=$? to prevent set -e from firing on failed wait, which would
  # skip stop_spinner and leave the terminal in a corrupt state.
  local cmd_exit=0
  wait $cmd_pid || cmd_exit=$?
  if [[ $cmd_exit -eq 124 ]]; then
    echo "  ⚠ Timed out after ${STEP_TIMEOUT:-300}s" >> "$tmp_err" 2>/dev/null || true
  fi
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

# ── npm install with cache recovery ──────────────────────────────────────────
# Runs npm install with automatic cache repair on EACCES/EEXIST failures.
# Usage: npm_install_with_recovery <dir> [label] [extra_flags]
npm_install_with_recovery() {
  local dir="$1"
  local label="${2:-npm install}"
  local extra_flags="${3:-}"

  # First attempt
  if run_with_spinner "$label" \
    _timeout_cmd 300 env NPM_DIR="$dir" bash -c 'cd "$NPM_DIR" && npm install --production --legacy-peer-deps --no-audit --no-fund --prefer-offline '$extra_flags' 2>&1'; then
    return 0
  fi

  # Diagnose and repair npm cache
  warn "$label failed — attempting npm cache repair..."
  local npm_cache_dir
  npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")

  # Fix ownership if cache dir exists and is owned by someone else
  if [[ -d "$npm_cache_dir" ]]; then
    local npm_owner
    npm_owner=$(stat -f '%Su' "$npm_cache_dir" 2>/dev/null || stat -c '%U' "$npm_cache_dir" 2>/dev/null || echo "")
    if [[ -n "$npm_owner" && "$npm_owner" != "$(whoami)" ]]; then
      info "Fixing npm cache ownership ($npm_owner → $(whoami))..."
      if ! chown -R "$(whoami)" "$npm_cache_dir" 2>/dev/null; then
        error "Cannot fix npm cache ownership — run: sudo chown -R \$(whoami) $npm_cache_dir"
        return 1
      fi
    fi
  fi

  # Clean and verify cache
  npm cache clean --force 2>/dev/null || true
  npm cache verify 2>/dev/null || true

  # Retry
  info "Retrying $label after cache repair..."
  run_with_spinner "$label (retry)" \
    _timeout_cmd 300 env NPM_DIR="$dir" bash -c 'cd "$NPM_DIR" && npm install --production --legacy-peer-deps --no-audit --no-fund --prefer-offline '$extra_flags' 2>&1'
}

# Verify SHA256 checksum of a file against a checksum file.
# Returns 0 on match (or no sha256 tool available), 1 on mismatch.
_verify_sha256() {
  local file="$1" checksum_file="$2"
  local expected actual
  expected="$(awk '{print $1}' "$checksum_file")"
  if command -v sha256sum &>/dev/null; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    warn "No sha256 tool found — skipping checksum verification"
    return 0
  fi
  if [[ -z "$actual" ]]; then
    warn "SHA256 tool produced no output — skipping checksum verification"
    return 0
  fi
  if [[ "$actual" != "$expected" ]]; then
    warn "SHA256 mismatch (expected ${expected:0:12}..., got ${actual:0:12}...)"
    return 1
  fi
  return 0
}

# ─── Settings.json Schema Validation ──────────────────────────────────────────
# Validates that settings.json has all required fields and is well-formed.
validate_settings() {
  local settings_file="${1:-$PI_AGENT_DIR/settings.json}"
  
  if [[ ! -f "$settings_file" ]]; then
    warn "settings.json not found at $settings_file"
    return 1
  fi

  # Validate JSON syntax and required fields
  local validation_result=""
  if command -v node &>/dev/null; then
    validation_result=$(node -e "
      const fs = require('fs');
      const f = process.argv[1];
      try {
        const data = JSON.parse(fs.readFileSync(f, 'utf8'));
        const required = ['defaultProvider'];
        const recommended = ['defaultModel', 'customInstructions'];
        const missing = required.filter(k => !data[k]);
        const missingRec = recommended.filter(k => !data[k]);
        if (missing.length > 0) {
          console.log('FAIL:missing_required:' + missing.join(','));
          process.exit(1);
        }
        if (typeof data.defaultProvider !== 'string' || data.defaultProvider.trim() === '') {
          console.log('FAIL:empty_provider');
          process.exit(1);
        }
        const validProviders = ['anthropic', 'amazon-bedrock', 'openai', 'google', 'openrouter'];
        if (!validProviders.includes(data.defaultProvider)) {
          console.log('WARN:unknown_provider:' + data.defaultProvider);
        }
        if (missingRec.length > 0) {
          console.log('WARN:missing_recommended:' + missingRec.join(','));
        } else {
          console.log('OK');
        }
      } catch (e) {
        console.log('FAIL:invalid_json:' + e.message);
        process.exit(1);
      }
    " "$settings_file" 2>/dev/null)
  elif command -v python3 &>/dev/null; then
    validation_result=$(python3 -c "
import json, sys
f = sys.argv[1]
try:
    with open(f) as fh:
        data = json.load(fh)
    required = ['defaultProvider']
    missing = [k for k in required if k not in data]
    if missing:
        print('FAIL:missing_required:' + ','.join(missing))
        sys.exit(1)
    if not isinstance(data.get('defaultProvider'), str) or not data['defaultProvider'].strip():
        print('FAIL:empty_provider')
        sys.exit(1)
    valid = ['anthropic', 'amazon-bedrock', 'openai', 'google', 'openrouter']
    if data['defaultProvider'] not in valid:
        print('WARN:unknown_provider:' + data['defaultProvider'])
    else:
        print('OK')
except json.JSONDecodeError as e:
    print('FAIL:invalid_json:' + str(e))
    sys.exit(1)
" "$settings_file" 2>/dev/null)
  else
    warn "Neither node nor python3 available — skipping settings validation"
    return 0
  fi

  case "$validation_result" in
    OK)
      success "settings.json valid"
      return 0
      ;;
    WARN:unknown_provider:*)
      local unknown_prov="${validation_result#WARN:unknown_provider:}"
      warn "settings.json: unrecognized provider '$unknown_prov' (may still work)"
      return 0
      ;;
    WARN:missing_recommended:*)
      local missing_rec="${validation_result#WARN:missing_recommended:}"
      info "settings.json: recommended fields missing: $missing_rec"
      return 0
      ;;
    FAIL:missing_required:*)
      local missing_req="${validation_result#FAIL:missing_required:}"
      error "settings.json: missing required fields: $missing_req"
      return 1
      ;;
    FAIL:empty_provider)
      error "settings.json: defaultProvider is empty"
      return 1
      ;;
    FAIL:invalid_json:*)
      local json_err="${validation_result#FAIL:invalid_json:}"
      error "settings.json: invalid JSON — $json_err"
      return 1
      ;;
    *)
      error "settings.json validation failed"
      return 1
      ;;
  esac
}

# ─── Per-Component Timeout Configuration ──────────────────────────────────────
# Each major install step has its own timeout (seconds). Override via env vars.
DOCKER_INSTALL_TIMEOUT="${DOCKER_INSTALL_TIMEOUT:-600}"
MEMGRAPH_TIMEOUT="${MEMGRAPH_TIMEOUT:-300}"
OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-300}"
NODE_INSTALL_TIMEOUT="${NODE_INSTALL_TIMEOUT:-300}"
NPM_INSTALL_TIMEOUT="${NPM_INSTALL_TIMEOUT:-300}"
PACKAGE_SYNC_TIMEOUT="${PACKAGE_SYNC_TIMEOUT:-600}"
OFFLINE_MODE="${OFFLINE_MODE:-false}"

check_prerequisites() {
  step "Prerequisites (auto-installing missing dependencies)"

  local platform
  platform="$(current_platform)"

  # Diagnostic: show environment for debugging
  info "Platform: $platform | bash: ${BASH_VERSION:-unknown} | user: $(whoami)"
  info "Node: $(node -v 2>/dev/null || echo 'not found') | npm: $(npm -v 2>/dev/null || echo 'not found') | prefix: $(npm config get prefix 2>/dev/null || echo 'n/a')"

  # ── Homebrew (macOS — REQUIRED) ────────────────────────────────────────────
  if [[ "$platform" == "macos" ]] && ! command -v brew &>/dev/null; then
    info "Installing Homebrew (required for macOS package management)..."
    info "You may be prompted for your password."
    # Ensure we have admin access
    if ! sudo -v 2>/dev/null; then
      error "Homebrew requires admin privileges."
      echo -e "    ${BOLD}Fix:${RESET} Run this command first to get admin access:"
      echo -e "    ${DIM}  su - admin_username  # switch to an admin account${RESET}"
      echo -e "    ${DIM}  # Or: System Settings → Users & Groups → make '$(whoami)' an Admin${RESET}"
      echo -e "    Then re-run the installer."
      exit 1
    fi
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/aec7285/install.sh)" >> "$LOG_FILE" 2>&1
    # Add brew to PATH for this session
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
    if ! command -v brew &>/dev/null; then
      error "Homebrew install failed."
      echo -e "    Install manually: ${BOLD}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}"
      echo -e "    Then re-run the installer."
      exit 1
    fi
    success "Homebrew installed"
    # Persist Homebrew PATH to shell profile
    brew_shellenv=""
    if [[ -x /opt/homebrew/bin/brew ]]; then
      brew_shellenv='eval "$(/opt/homebrew/bin/brew shellenv)"'
    elif [[ -x /usr/local/bin/brew ]]; then
      brew_shellenv='eval "$(/usr/local/bin/brew shellenv)"'
    fi
    if [[ -n "$brew_shellenv" ]]; then
      for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
        if [[ -f "$rc" ]] || [[ "$rc" == *"zprofile"* ]]; then
          if ! grep -qF 'brew shellenv' "$rc" 2>/dev/null; then
            echo "$brew_shellenv" >> "$rc"
          fi
        fi
      done
    fi
  elif [[ "$platform" == "macos" ]]; then
    success "Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
  fi

  # ── One-time apt-get update (linux/wsl) ────────────────────────────────────
  if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
    # shellcheck disable=SC2024
    sudo apt-get update -y >> "$LOG_FILE" 2>&1 || true
  fi

  # ── Helper: install a dependency ───────────────────────────────────────────
  # _install_dep is provided by lib/platform.sh (sourced at top of script).
  # Fallback inline definition used only when the lib failed to load.
  if ! declare -f _install_dep &>/dev/null; then
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
          # shellcheck disable=SC2024
          sudo apt-get install -y "$apt_pkg" >> "$LOG_FILE" 2>&1 ;;
        *)
          warn "$cmd: unsupported platform ($platform) — install manually"
          return 1 ;;
      esac
      command -v "$cmd" &>/dev/null
    }
  fi

  # ── Node.js 22 LTS (pinned — native modules in tarball require Node 22) ────
  local node_ok=false
  local NODE_MAJOR_MIN=18
  local NODE_MAJOR_MAX=22  # tarball native modules compiled against Node 22
  if command -v node &>/dev/null; then
    local node_major
    node_major=$(node -e "console.log(parseInt(process.version.slice(1)))" 2>/dev/null || echo 0)
    if [[ "$node_major" -ge "$NODE_MAJOR_MIN" ]] && [[ "$node_major" -le "$NODE_MAJOR_MAX" ]]; then
      node_ok=true
      success "Node.js $(node -v)"
    elif [[ "$node_major" -gt "$NODE_MAJOR_MAX" ]]; then
      warn "Node.js $(node -v) is too new — native modules require Node ${NODE_MAJOR_MAX}.x LTS"
      warn "better-sqlite3 and other native addons will fail with NODE_MODULE_VERSION mismatch"
      if [[ "$(current_platform)" == "macos" ]] && command -v brew &>/dev/null; then
        info "Downgrading to Node ${NODE_MAJOR_MAX} LTS via Homebrew..."
        brew install node@${NODE_MAJOR_MAX} >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        brew link --overwrite node@${NODE_MAJOR_MAX} >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        if command -v node &>/dev/null; then
          node_major=$(node -e "console.log(parseInt(process.version.slice(1)))" 2>/dev/null || echo 0)
          if [[ "$node_major" -le "$NODE_MAJOR_MAX" ]]; then
            node_ok=true
            success "Node.js $(node -v) (downgraded to LTS)"
          fi
        fi
      fi
      if [[ "$node_ok" == false ]]; then
        warn "Could not auto-downgrade Node. Install Node ${NODE_MAJOR_MAX} LTS manually:"
        warn "  brew install node@${NODE_MAJOR_MAX} && brew link --overwrite node@${NODE_MAJOR_MAX}"
        warn "Continuing with $(node -v) — native module rebuild will be attempted"
        node_ok=true  # allow install to continue; repair will be attempted later
      fi
    else
      warn "Node.js $(node -v) is too old (need ${NODE_MAJOR_MIN}+) — upgrading..."
    fi
  fi

  if [[ "$node_ok" == false ]]; then
    info "Installing Node.js..."
    # Delegates to lib/platform.sh's _install_nodejs() which handles
    # apt/dnf/pacman/zypper on Linux/WSL and brew on macOS.
    _timeout_cmd "$NODE_INSTALL_TIMEOUT" bash -c '_install_nodejs' 2>/dev/null || _install_nodejs
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

  # ── Bun (required by Helios CLI binary for package resolution) ─────────────
  if command -v bun &>/dev/null; then
    success "bun $(bun --version)"
  else
    info "Installing Bun runtime..."
    if _timeout_cmd 60 bash -c 'curl -fsSL --max-time 30 https://bun.sh/install | BUN_INSTALL="$HOME/.bun" bash' >> "${LOG_FILE:-/dev/null}" 2>&1; then
      export PATH="$HOME/.bun/bin:$PATH"
      hash -r 2>/dev/null || true
      if command -v bun &>/dev/null; then
        success "bun $(bun --version) installed"
      else
        warn "Bun installed but not in PATH — add ~/.bun/bin to PATH"
      fi
    else
      warn "Bun installation failed — helios CLI may not resolve packages correctly"
      warn "Install manually: curl -fsSL https://bun.sh/install | bash"
    fi
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
        # shellcheck disable=SC2024
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
    retry_with_backoff 3 2 npm install -g pnpm >> "$LOG_FILE" 2>&1 && success "pnpm installed" || warn "pnpm install failed — not critical"
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
        _timeout_cmd "$DOCKER_INSTALL_TIMEOUT" retry_with_backoff 3 5 brew install --cask orbstack >> "$LOG_FILE" 2>&1 && {
          success "OrbStack installed — launch it to start Docker"
        } || warn "OrbStack install failed — install manually: https://orbstack.dev"
        ;;
      linux)
        info "Installing Docker CE..."
        if command -v curl &>/dev/null; then
          info "This will run the Docker install script with sudo permissions"
          _timeout_cmd "$DOCKER_INSTALL_TIMEOUT" retry_with_backoff 3 5 bash -c "curl -fsSL https://get.docker.com | sh" >> "$LOG_FILE" 2>&1 && {
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

# ─── Network connectivity check ──────────────────────────────────────────────
check_network() {
  step "Network Connectivity"
  
  OFFLINE_MODE=false
  
  # Check npm registry
  if curl -fsSL --connect-timeout 5 --max-time 10 https://registry.npmjs.org/ -o /dev/null 2>/dev/null; then
    success "npm registry reachable"
  else
    warn "npm registry unreachable — will use bundled packages only"
    OFFLINE_MODE=true
  fi
  
  # Check GitHub
  if curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/ -o /dev/null 2>/dev/null; then
    success "GitHub API reachable"
  else
    warn "GitHub API unreachable — will skip updates"
    OFFLINE_MODE=true
  fi
  
  if [[ "$OFFLINE_MODE" == "true" ]]; then
    info "Running in OFFLINE MODE — relying on bundled tarball deps"
  fi
}

# ─── Pi Installation ──────────────────────────────────────────────────────────
install_pi() {
  step "Helios CLI (tarball from helios-agi/helios-installer)"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    if command -v helios &>/dev/null || [[ -f "$HOME/.helios-cli/helios" ]]; then
      info "[dry-run] CLI binary already installed"
    else
      info "[dry-run] Would install Helios CLI binary"
    fi
    return 0
  fi

  # If local package provided, install CLI from it
  if [[ -n "${LOCAL_PACKAGE:-}" ]] && [[ -d "$LOCAL_PACKAGE/cli/pi" || -f "$LOCAL_PACKAGE/cli/pi/pi" ]]; then
    local pi_binary="$LOCAL_PACKAGE/cli/pi/pi"
    if [[ ! -f "$pi_binary" ]]; then
      pi_binary=$(find "$LOCAL_PACKAGE/cli" -name "pi" -type f ! -name "*.json" 2>/dev/null | head -1)
    fi
    if [[ -n "$pi_binary" && -f "$pi_binary" ]]; then
      chmod +x "$pi_binary"
      local HELIOS_CLI_FALLBACK="$HOME/.helios-cli/helios"
      mkdir -p "$(dirname "$HELIOS_CLI_FALLBACK")"
      cp "$pi_binary" "$HELIOS_CLI_FALLBACK"
      chmod +x "$HELIOS_CLI_FALLBACK"
      local pi_binary_dir
      pi_binary_dir="$(dirname "$pi_binary")"
      [[ -f "$pi_binary_dir/package.json" ]] && cp "$pi_binary_dir/package.json" "$(dirname "$HELIOS_CLI_FALLBACK")/package.json"
      success "Helios CLI installed from package"
      PI_INSTALLED=true
      return 0
    fi
  fi

  # Architecture:
  #   /usr/local/bin/helios  = REAL CLI binary (helios-agi fork of pi, from tarball)
  #   ~/.local/bin/helios    = symlink → wrapper (agent/bin/helios) [created by install_helios_cli]
  #   ~/.pi/agent/bin/helios = wrapper script (the product — NEVER removed)
  #
  # The wrapper's resolve_cli() finds the real binary at /usr/local/bin/helios
  # because it has a different realpath than the wrapper. PATH order ensures
  # ~/.local/bin/helios (wrapper) is found first by the shell.
  #
  # RULE: Never remove the wrapper. Only install/replace the real CLI binary.
  local HELIOS_CLI_BIN="/usr/local/bin/helios"
  local HELIOS_CLI_FALLBACK="$HOME/.helios-cli/helios"

  # ── Check if the real CLI binary (not the wrapper) already exists ─────────
  local real_cli=""
  for loc in "$HELIOS_CLI_BIN" "$HELIOS_CLI_FALLBACK" /opt/homebrew/bin/helios; do
    # Must be a real file (not a symlink to wrapper) and must execute
    if [[ -f "$loc" && ! -L "$loc" ]] && "$loc" --version &>/dev/null; then
      real_cli="$loc"
      break
    fi
  done

  if [[ -n "$real_cli" ]]; then
    local cli_ver
    cli_ver=$(_timeout_cmd 10 "$real_cli" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    success "Helios CLI binary already installed: $cli_ver ($real_cli)"
    PI_INSTALLED=true
    return 0
  fi

  info "Helios CLI binary not found — installing from tarball..."

  # ── Detect platform ──────────────────────────────────────────────────────
  local os_name arch platform_tarball
  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${os_name}" in
    darwin)
      case "$arch" in
        arm64|aarch64) platform_tarball="pi-darwin-arm64.tar.gz" ;;
        x86_64)        platform_tarball="pi-darwin-x64.tar.gz" ;;
        *)             warn "Unsupported macOS architecture: $arch"; return 1 ;;
      esac
      ;;
    linux)
      case "$arch" in
        aarch64|arm64) platform_tarball="pi-linux-arm64.tar.gz" ;;
        x86_64)        platform_tarball="pi-linux-x64.tar.gz" ;;
        *)             warn "Unsupported Linux architecture: $arch"; return 1 ;;
      esac
      ;;
    *)
      warn "Unsupported OS: $os_name ($arch)"
      return 1
      ;;
  esac

  # ── Check disk space (≥100MB for download + extraction) ──────────────────
  local available_mb
  if command -v df &>/dev/null; then
    available_mb=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_mb" ]] && [[ "$available_mb" -lt 100 ]]; then
      warn "Low disk space on /tmp: ${available_mb}MB available (need ~100MB)"
      echo -e "  ${BOLD}Fix:${RESET} Free up disk space and re-run the installer."
      return 1
    fi
  fi

  # ── Proxy detection ──────────────────────────────────────────────────────
  if [[ -n "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]]; then
    info "Proxy detected: ${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
  fi

  # ── Download with multi-source fallback ──────────────────────────────────
  local tarball_url="${HELIOS_CLI_RELEASE_URL}/${platform_tarball}"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local download_ok=false

  # Strategy 1: Primary URL (public helios-installer repo)
  info "Downloading $platform_tarball..."
  if curl -fsSL --retry 3 --retry-delay 5 --max-time 120 \
       -w "\nHTTP_CODE=%{http_code} SIZE=%{size_download} TIME=%{time_total}s\n" \
       "$tarball_url" -o "$tmp_dir/cli.tar.gz" >> "$LOG_FILE" 2>&1; then
    download_ok=true
  else
    local http_code
    http_code=$(curl -sI -o /dev/null -w "%{http_code}" "$tarball_url" 2>/dev/null || echo "000")
    warn "Primary download failed (HTTP $http_code) — trying fallback..."
  fi

  # Strategy 2: Fallback to helios-team-installer releases
  if [[ "$download_ok" != true ]]; then
    local fallback_url="${HELIOS_RELEASE_URL}/${platform_tarball}"
    if curl -fsSL --retry 2 --retry-delay 3 --max-time 120 \
         "$fallback_url" -o "$tmp_dir/cli.tar.gz" >> "$LOG_FILE" 2>&1; then
      download_ok=true
      info "Downloaded from fallback URL"
    else
      warn "Fallback download also failed"
    fi
  fi

  # Strategy 3: gh release download (if user has repo access)
  if [[ "$download_ok" != true ]] && command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    info "Trying gh CLI download (authenticated)..."
    if gh release download --repo helios-agi/helios-installer \
         --pattern "$platform_tarball" \
         --dir "$tmp_dir" >> "$LOG_FILE" 2>&1; then
      mv "$tmp_dir/$platform_tarball" "$tmp_dir/cli.tar.gz" 2>/dev/null
      download_ok=true
      info "Downloaded via gh CLI"
    fi
  fi

  if [[ "$download_ok" != true ]]; then
    error "Failed to download Helios CLI from all sources"
    echo -e "  Tried:"
    echo -e "    1. ${tarball_url}"
    echo -e "    2. ${HELIOS_RELEASE_URL}/${platform_tarball}"
    echo -e "    3. gh release download (if available)"
    if [[ -n "${HTTPS_PROXY:-}${https_proxy:-}" ]]; then
      echo -e "  ${BOLD}Note:${RESET} Proxy detected — set CURL_CA_BUNDLE if using custom CA."
    fi
    echo -e "  ${BOLD}Manual fix:${RESET}"
    echo -e "    curl -fsSL ${tarball_url} -o /tmp/cli.tar.gz"
    echo -e "    tar xzf /tmp/cli.tar.gz -C /tmp"
    echo -e "    # The binary is inside the tarball at pi/pi"
    echo -e "    sudo cp /tmp/pi/pi /usr/local/bin/helios && sudo chmod +x /usr/local/bin/helios"
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi

  # ── Validate download ────────────────────────────────────────────────────
  local tarball_size
  tarball_size=$(wc -c < "$tmp_dir/cli.tar.gz" 2>/dev/null || echo "0")
  if [[ "$tarball_size" -lt 1048576 ]]; then
    error "Downloaded tarball is suspiciously small (${tarball_size} bytes) — likely corrupt or error page"
    head -c 200 "$tmp_dir/cli.tar.gz" >> "$LOG_FILE" 2>/dev/null
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi

  # Validate gzip magic bytes (1f 8b)
  local magic
  magic=$(xxd -p -l 2 "$tmp_dir/cli.tar.gz" 2>/dev/null || od -A n -t x1 -N 2 "$tmp_dir/cli.tar.gz" 2>/dev/null | tr -d ' ')
  if [[ "$magic" != "1f8b" ]]; then
    error "Downloaded file is not a valid gzip archive (got: $magic)"
    echo -e "  This usually means the download URL returned an HTML error page."
    head -c 500 "$tmp_dir/cli.tar.gz" >> "$LOG_FILE" 2>/dev/null
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi

  # ── SHA256 checksum verification ─────────────────────────────────────────
  local checksum_url="${tarball_url}.sha256"
  local tmp_checksum
  tmp_checksum="$(mktemp)"
  if curl -fsSL --max-time 30 "$checksum_url" -o "$tmp_checksum" 2>/dev/null; then
    if ! _verify_sha256 "$tmp_dir/cli.tar.gz" "$tmp_checksum"; then
      error "SHA256 checksum mismatch — tarball may be corrupt or tampered with"
      rm -f "$tmp_checksum"
      rm -rf "$tmp_dir" 2>/dev/null
      return 1
    fi
    info "SHA256 checksum verified"
  else
    info "No checksum file available — skipping verification"
  fi
  rm -f "$tmp_checksum"

  # ── Extract tarball ──────────────────────────────────────────────────────
  if ! tar xzf "$tmp_dir/cli.tar.gz" -C "$tmp_dir" >> "$LOG_FILE" 2>&1; then
    error "Failed to extract tarball — file may be corrupt"
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi

  # ── Locate the binary (handle varying tarball structures) ────────────────
  local pi_binary=""
  for candidate in \
    "$tmp_dir/pi/pi" \
    "$tmp_dir/pi/helios" \
    "$tmp_dir/helios" \
    "$tmp_dir/pi"; do
    if [[ -f "$candidate" ]] && [[ -x "$candidate" || $(file "$candidate" 2>/dev/null) == *executable* ]]; then
      pi_binary="$candidate"
      break
    fi
  done
  if [[ -z "$pi_binary" ]]; then
    pi_binary=$(find "$tmp_dir" -name "pi" -type f ! -name "*.gz" ! -name "*.json" 2>/dev/null | head -1)
  fi
  if [[ -z "$pi_binary" || ! -f "$pi_binary" ]]; then
    error "Tarball extracted but CLI binary not found"
    find "$tmp_dir" -type f | head -20 | sed 's/^/    /' | tee -a "$LOG_FILE"
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi
  chmod +x "$pi_binary"

  # ── Verify binary runs ──────────────────────────────────────────────────
  if ! _timeout_cmd 15 "$pi_binary" --version &>/dev/null; then
    local bin_arch
    bin_arch=$(file "$pi_binary" 2>/dev/null || echo "unknown")
    error "CLI binary exists but won't execute"
    echo -e "  Binary: $bin_arch"
    echo -e "  System: $(uname -m) — possible architecture mismatch"
    rm -rf "$tmp_dir" 2>/dev/null
    return 1
  fi
  local installed_ver
  installed_ver=$(_timeout_cmd 10 "$pi_binary" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")

  # ── Install the real CLI binary ──────────────────────────────────────────
  # PRIMARY: ~/.helios-cli/helios (survives macOS upgrades — Tahoe 26 wipes /usr/local)
  # SECONDARY: /usr/local/bin/helios (convenience, on PATH by default)
  # The wrapper's resolve_cli() checks both locations.
  local install_target=""

  # Always install to ~/.helios-cli/ (durable, no sudo, survives OS upgrades)
  mkdir -p "$(dirname "$HELIOS_CLI_FALLBACK")"
  cp "$pi_binary" "$HELIOS_CLI_FALLBACK"
  chmod +x "$HELIOS_CLI_FALLBACK"
  install_target="$HELIOS_CLI_FALLBACK"

  local pi_binary_dir
  pi_binary_dir="$(dirname "$pi_binary")"
  local fallback_dir
  fallback_dir="$(dirname "$HELIOS_CLI_FALLBACK")"
  if [[ -f "$pi_binary_dir/package.json" ]]; then
    cp "$pi_binary_dir/package.json" "$fallback_dir/package.json"
  fi

  # Also install to /usr/local/bin as convenience (may be wiped by macOS upgrades)
  if [[ ! -d "/usr/local/bin" ]]; then
    sudo -n mkdir -p /usr/local/bin 2>/dev/null && \
      sudo chmod 755 /usr/local/bin 2>/dev/null || true
  fi
  if [[ -d "/usr/local/bin" ]]; then
    [[ -L "$HELIOS_CLI_BIN" ]] && { rm -f "$HELIOS_CLI_BIN" 2>/dev/null || sudo rm -f "$HELIOS_CLI_BIN" 2>/dev/null || true; }
    if [[ -w "/usr/local/bin" ]]; then
      cp "$pi_binary" "$HELIOS_CLI_BIN" 2>/dev/null && chmod +x "$HELIOS_CLI_BIN" 2>/dev/null || true
      [[ -f "$pi_binary_dir/package.json" ]] && cp "$pi_binary_dir/package.json" /usr/local/bin/package.json 2>/dev/null || true
    elif sudo -n true 2>/dev/null; then
      sudo cp "$pi_binary" "$HELIOS_CLI_BIN" 2>/dev/null && sudo chmod +x "$HELIOS_CLI_BIN" 2>/dev/null || true
      [[ -f "$pi_binary_dir/package.json" ]] && sudo cp "$pi_binary_dir/package.json" /usr/local/bin/package.json 2>/dev/null || true
    fi
  fi

  # Remove macOS quarantine attribute
  if [[ "$(uname -s)" == "Darwin" ]] && command -v xattr &>/dev/null; then
    xattr -d com.apple.quarantine "$install_target" 2>/dev/null || true
  fi

  rm -rf "$tmp_dir" 2>/dev/null
  hash -r 2>/dev/null || true
  PI_INSTALLED=true
  success "Helios CLI $installed_ver installed at $install_target"
}

# ─── Helios CLI Update ────────────────────────────────────────────────────────────
update_pi_cli() {
  step "Helios CLI Update"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    info "[dry-run] Would update Helios CLI binary"
    return 0
  fi

  local real_cli=""
  for loc in /usr/local/bin/helios "$HOME/.helios-cli/helios" /opt/homebrew/bin/helios; do
    if [[ -f "$loc" && ! -L "$loc" ]]; then
      real_cli="$loc"
      break
    fi
  done

  if [[ -z "$real_cli" ]]; then
    warn "Helios CLI binary not found — installing..."
    install_pi
    return
  fi

  local current_ver
  current_ver=$(_timeout_cmd 10 "$real_cli" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")

  info "Reinstalling Helios CLI from tarball (current: $current_ver)..."

  # Backup the primary binary, then remove ALL known locations so install_pi
  # doesn't find an old copy and short-circuit. Without this, install_pi finds
  # ~/.helios-cli/helios (still present) and returns early without downloading.
  local backup="${real_cli}.backup-$(date +%s)"
  if ! (cp "$real_cli" "$backup" 2>/dev/null || sudo cp "$real_cli" "$backup" 2>/dev/null); then
    warn "Cannot create backup — aborting update to preserve existing binary"
    return 1
  fi

  # Remove ALL real binary locations (and accompanying package.json) so install_pi does a fresh download
  local _dir=""
  for _loc in /usr/local/bin/helios "$HOME/.helios-cli/helios" /opt/homebrew/bin/helios; do
    if [[ -f "$_loc" && ! -L "$_loc" ]]; then
      rm -f "$_loc" 2>/dev/null || sudo rm -f "$_loc" 2>/dev/null || true
      _dir="$(dirname "$_loc")"
      rm -f "$_dir/package.json" 2>/dev/null || sudo rm -f "$_dir/package.json" 2>/dev/null || true
    fi
  done
  hash -r 2>/dev/null || true

  if ! install_pi; then
    # Restore backup on failure
    if [[ -f "$backup" ]]; then
      mv "$backup" "$real_cli" 2>/dev/null || sudo mv "$backup" "$real_cli" 2>/dev/null || true
      warn "Install failed — restored previous Helios CLI version"
    fi
    return 1
  fi

  rm -f "$backup" 2>/dev/null || sudo rm -f "$backup" 2>/dev/null || true
}

# ─── Helios Agent (Tarball) ───────────────────────────────────────────────────
setup_helios_agent() {
  step "Helios Agent (~/.pi/agent/)"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    if [[ -d "$PI_AGENT_DIR" ]] && [[ -f "$PI_AGENT_DIR/VERSION" ]]; then
      info "[dry-run] Agent installed: $(cat "$PI_AGENT_DIR/VERSION")"
    else
      info "[dry-run] Would download and install helios-agent tarball"
    fi
    return 0
  fi

  # Use local package if available (all-in-one tarball)
  if [[ -n "${LOCAL_PACKAGE:-}" ]] && [[ -d "$LOCAL_PACKAGE/agent" ]]; then
    info "Installing agent from local package..."
    local tmp_stash
    tmp_stash="$(mktemp -d)"
    if [[ -d "$PI_AGENT_DIR" ]]; then
      for preserve in "${HELIOS_PRESERVE_FILES[@]}"; do
        [[ -e "$PI_AGENT_DIR/$preserve" ]] && cp -a "$PI_AGENT_DIR/$preserve" "$tmp_stash/"
      done
    fi
    rm -rf "$PI_AGENT_DIR"
    mkdir -p "$HOME/.pi"
    cp -a "$LOCAL_PACKAGE/agent" "$PI_AGENT_DIR"
    for preserve in "${HELIOS_PRESERVE_FILES[@]}"; do
      [[ -e "$tmp_stash/$preserve" ]] && cp -a "$tmp_stash/$preserve" "$PI_AGENT_DIR/"
    done
    rm -rf "$tmp_stash"
    if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
      cat "$LOCAL_PACKAGE/VERSION" > "$PI_AGENT_DIR/VERSION" 2>/dev/null || echo "local" > "$PI_AGENT_DIR/VERSION"
    fi
    _migrate_settings_packages
    _prune_stale_org_dirs
    success "Helios agent installed from package"
    return 0
  fi

  _helios_download() {
    local url="$1" dest="$2"
    local fname
    fname="$(basename "$url")"
    printf "  ↓ %s " "$fname" > /dev/tty 2>/dev/null || true
    if curl -fSL --retry 3 --retry-delay 5 --max-time 300 -o "$dest" "$url"; then
      printf "✓\n" > /dev/tty 2>/dev/null || true
      return 0
    else
      printf "✗\n" > /dev/tty 2>/dev/null || true
      return 1
    fi
  }

  # ── Resolve arch-specific tarball (fall back to universal if not found) ────
  if ! curl -fsSI --retry 3 --retry-delay 5 --max-time 30 "${HELIOS_RELEASE_URL}/${HELIOS_AGENT_TARBALL}" &>/dev/null; then
    info "Arch-specific tarball not found (${HELIOS_AGENT_TARBALL}) — using universal tarball"
    HELIOS_AGENT_TARBALL="${HELIOS_AGENT_TARBALL_UNIVERSAL}"
  else
    info "Using arch-specific tarball: ${HELIOS_AGENT_TARBALL}"
  fi

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
      # Verify install is healthy before declaring up-to-date
      if [[ -d "$PI_AGENT_DIR/node_modules" ]] && [[ -d "$PI_AGENT_DIR/extensions" ]] && [[ -f "$PI_AGENT_DIR/bin/helios" ]]; then
        success "Helios agent is already up to date ($local_version)"
        return 0
      fi
      info "Version matches but install appears incomplete — re-extracting..."
    fi

    info "Update available: $local_version → $remote_version — downloading…"

    # Stash user files before extraction
    local tmp_stash
    tmp_stash="$(mktemp -d)"
    for preserve in "${HELIOS_PRESERVE_FILES[@]}"; do
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
      if ! _verify_sha256 "$tmp_tarball" "$tmp_checksum"; then
        warn "Tarball checksum mismatch — skipping update"
        rm -rf "$tmp_stash" "$tmp_tarball" "$tmp_checksum"
        return 0
      fi
    fi
    rm -f "$tmp_checksum"

    # Extract to temp dir first (atomic swap prevents broken state on interrupt)
    local tmp_extract
    tmp_extract="$(mktemp -d)"
    if ! tar -xzf "$tmp_tarball" -C "$tmp_extract" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
      warn "Tarball extraction failed — keeping existing install"
      rm -rf "$tmp_extract" "$tmp_stash" "$tmp_tarball"
      return 0
    fi
    rm -f "$tmp_tarball"

    # Swap: old dir → trash, new dir → PI_AGENT_DIR
    local trash_dir="${PI_AGENT_DIR}.old-$(date +%s)"
    mv "$PI_AGENT_DIR" "$trash_dir" 2>/dev/null || rm -rf "$PI_AGENT_DIR"
    mv "$tmp_extract" "$PI_AGENT_DIR"

    # Restore user files
    for preserve in "${HELIOS_PRESERVE_FILES[@]}"; do
      [[ -e "$tmp_stash/$preserve" ]] && cp -a "$tmp_stash/$preserve" "$PI_AGENT_DIR/"
    done
    rm -rf "$tmp_stash" "$trash_dir"

    # Migrate preserved settings.json from git: (clone) to git/ (local path)
    _migrate_settings_packages
    _prune_stale_org_dirs

    success "Helios agent updated to $remote_version"
    # Ensure VERSION file exists after update
    if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
      echo "$remote_version" > "$PI_AGENT_DIR/VERSION"
    fi

    # /update uses tarball mechanism (same as this installer) — no git needed
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
  free_mb=$(df -Pm "$HOME" 2>/dev/null | awk 'NR>1 {print $4; exit}')
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

  if _helios_download "$HELIOS_RELEASE_URL/$HELIOS_AGENT_TARBALL.sha256" "$tmp_checksum"; then
    if ! _verify_sha256 "$tmp_tarball" "$tmp_checksum"; then
      warn "Tarball checksum mismatch — skipping extraction"
      rm -f "$tmp_tarball" "$tmp_checksum"
      return 1
    fi
  else
    info "Checksum file not available — skipping verification"
  fi
  rm -f "$tmp_checksum"

  mkdir -p "$HOME/.pi"
  local tmp_extract
  tmp_extract="$(mktemp -d)"
  if ! tar -xzf "$tmp_tarball" -C "$tmp_extract" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
    warn "Tarball extraction failed — skipping helios-agent install"
    rm -rf "$tmp_extract" "$tmp_tarball"
    return 1
  fi
  rm -f "$tmp_tarball"

  rm -rf "$PI_AGENT_DIR"
  mv "$tmp_extract" "$PI_AGENT_DIR"
  success "Helios agent installed to $PI_AGENT_DIR"

  # Ensure VERSION file exists (tarball may be missing it)
  if [[ ! -f "$PI_AGENT_DIR/VERSION" ]]; then
    echo "tarball-$(date +%Y%m%d)" > "$PI_AGENT_DIR/VERSION"
    warn "VERSION file missing from tarball — created placeholder"
  fi
}

# ─── Agent Directory Update (git-based) ──────────────────────────────────────
update_agent_dir() {
  step "Agent Directory"
  setup_helios_agent
}

# ─── Update Snapshot ──────────────────────────────────────────────────────────
snapshot_state() {
  local snapshot_file="$PI_AGENT_DIR/.update-snapshot.json"
  local pi_version agent_version timestamp

  pi_version=$(_timeout_cmd 10 helios --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  agent_version=$(cat "$PI_AGENT_DIR/VERSION" 2>/dev/null || echo "unknown")
  timestamp=$(date +%s)

  printf '{"pi_version":"%s","agent_version":"%s","timestamp":%s}\n' \
    "$pi_version" "$agent_version" "$timestamp" > "$snapshot_file"
}

# ─── Update Verification ──────────────────────────────────────────────────────
verify_update() {
  step "Update Verification"

  local all_pass=true

  # Check 1: helios --version responds and returns a version string
  local pi_ver
  if pi_ver=$(_timeout_cmd 15 helios --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) && [[ -n "$pi_ver" ]]; then
    success "Helios CLI responds: $pi_ver"
  else
    error "Helios CLI check failed — cannot get version"
    all_pass=false
  fi

  # Check 2: settings.json exists, is valid JSON, and has required fields
  local settings_file="$PI_AGENT_DIR/settings.json"
  if [[ -f "$settings_file" ]]; then
    if validate_settings "$settings_file"; then
      : # validate_settings prints its own success/warn messages
    else
      error "settings.json validation failed"
      all_pass=false
    fi
  else
    error "settings.json not found at $settings_file"
    all_pass=false
  fi

  # Check 3: extensions directory exists
  if [[ -d "$PI_AGENT_DIR/extensions" ]]; then
    success "Extensions directory exists"
  else
    error "Extensions directory not found at $PI_AGENT_DIR/extensions"
    all_pass=false
  fi

  if [[ "$all_pass" == true ]]; then
    success "All update checks passed"
    return 0
  else
    warn "One or more update checks failed"
    return 1
  fi
}

# ─── Update Rollback ──────────────────────────────────────────────────────────
rollback_update() {
  step "Rolling Back Update"

  local snapshot_file="$PI_AGENT_DIR/.update-snapshot.json"
  if [[ ! -f "$snapshot_file" ]]; then
    warn "No snapshot found at $snapshot_file — cannot roll back"
    return 1
  fi

  local saved_pi_version saved_agent_sha
  saved_pi_version=$(python3 -c "import json; print(json.load(open('$snapshot_file'))['pi_version'])" 2>/dev/null || \
                     node -e "console.log(JSON.parse(require('fs').readFileSync('$snapshot_file','utf8')).pi_version)" 2>/dev/null || echo "")
  saved_agent_sha=$(python3 -c "import json; print(json.load(open('$snapshot_file'))['agent_sha'])" 2>/dev/null || \
                    node -e "console.log(JSON.parse(require('fs').readFileSync('$snapshot_file','utf8')).agent_sha)" 2>/dev/null || echo "")

  if [[ -z "$saved_pi_version" ]] || [[ -z "$saved_agent_sha" ]]; then
    error "Could not parse snapshot — manual rollback required"
    return 1
  fi

  local rolled_back=false

  # Roll back agent directory if SHA differs and it's a git repo
  if [[ -d "$PI_AGENT_DIR/.git" ]] && [[ "$saved_agent_sha" != "unknown" ]]; then
    local current_sha
    current_sha=$(git -C "$PI_AGENT_DIR" rev-parse HEAD 2>/dev/null || echo "")
    if [[ "$current_sha" != "$saved_agent_sha" ]]; then
      info "Rolling back agent: ${current_sha:0:7} → ${saved_agent_sha:0:7}"
      if git -C "$PI_AGENT_DIR" reset --hard "$saved_agent_sha" 2>/dev/null; then
        success "Agent rolled back to ${saved_agent_sha:0:7}"
        rolled_back=true
      else
        error "Agent rollback failed — manual fix: git -C $PI_AGENT_DIR reset --hard $saved_agent_sha"
      fi
    else
      info "Agent SHA unchanged — no rollback needed"
    fi
  fi

  # Roll back Helios CLI if version differs
  if [[ "$saved_pi_version" != "unknown" ]]; then
    local current_ver
    current_ver=$(_timeout_cmd 10 helios --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    if [[ "$current_ver" != "$saved_pi_version" ]]; then
      info "Rolling back Helios CLI: $current_ver → $saved_pi_version"
      if npm install -g "@helios-agent/cli@${saved_pi_version}" 2>/dev/null; then
        success "Helios CLI rolled back to $saved_pi_version"
        rolled_back=true
      else
        error "Helios CLI rollback failed — manual fix: npm install -g @helios-agent/cli@${saved_pi_version}"
      fi
    else
      info "Helios CLI version unchanged — no rollback needed"
    fi
  fi

  if [[ "$rolled_back" == true ]]; then
    warn "Rollback complete — resolve update issues before retrying"
  else
    info "Nothing to roll back — state matches snapshot"
  fi
}

# ─── Helios CLI Command ──────────────────────────────────────────────────────
install_helios_cli() {
  step "Helios CLI (wrapper)"

  local helios_bin="$PI_AGENT_DIR/bin/helios"
  if [[ ! -f "$helios_bin" ]]; then
    info "bin/helios not found in agent repo — skipping wrapper setup"
    return 0
  fi

  chmod +x "$helios_bin"

  # Verify the real CLI binary exists. The wrapper delegates to it via resolve_cli().
  # If the real binary is missing, install it first.
  local real_cli_found=false
  for loc in /usr/local/bin/helios "$HOME/.helios-cli/helios" /opt/homebrew/bin/helios; do
    if [[ -f "$loc" && ! -L "$loc" ]]; then
      real_cli_found=true
      break
    fi
  done
  if [[ "$real_cli_found" == false ]]; then
    warn "Helios CLI binary not found — the wrapper needs it to function"
    info "Installing Helios CLI binary..."
    install_pi || {
      warn "Could not install CLI binary — wrapper will fall back to npx"
    }
  fi

  # ── Install wrapper symlinks to ~/.local/bin ─────────────────────────────
  # IMPORTANT: Do NOT symlink the wrapper to /usr/local/bin/helios — that's
  # where the real CLI binary lives. The wrapper goes to ~/.local/bin which
  # has PATH priority, so 'helios' resolves to wrapper first.
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$helios_bin" "$HOME/.local/bin/helios"
  ln -sfn "$helios_bin" "$HOME/.local/bin/pi"
  success "helios → ~/.local/bin/helios (wrapper)"
  success "pi → ~/.local/bin/pi (wrapper alias)"

  # Add to PATH in shell profile if not already there
  local shell_rc
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    shell_rc="$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      shell_rc="$HOME/.bash_profile"
    else
      shell_rc="$HOME/.bashrc"
    fi
  else
    shell_rc="$HOME/.zshrc"
  fi
  touch "$shell_rc" 2>/dev/null || true
  if ! grep -q 'HELIOS PATH' "$shell_rc" 2>/dev/null; then
    {
      echo ''
      echo '# HELIOS PATH: keep Helios shims ahead of older npm/nvm pi installs'
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$shell_rc"
    success "Added Helios PATH block to $(basename "$shell_rc")"
  fi
  export PATH="$HOME/.local/bin:$PATH"
  info "Restart your terminal or run: source $(basename "$shell_rc")"

  # Also symlink fd if present and not already in PATH
  local fd_bin="$PI_AGENT_DIR/bin/fd"
  if [[ -f "$fd_bin" ]] && ! command -v fd &>/dev/null; then
    chmod +x "$fd_bin"
    if [[ -d "$HOME/.local/bin" ]]; then
      ln -sfn "$fd_bin" "$HOME/.local/bin/fd"
      success "fd → ~/.local/bin/fd"
    fi
  fi

  success "Type 'helios' to launch"
}


# ─── Pi Update (Install Packages) ─────────────────────────────────────────────
install_packages() {
  step "Installing Helios packages"

  # Quick skip: if all packages already present, don't re-sync
  local existing_count=0
  for _org in helios-agi sweetcheeks72 nicobailon; do
    local org_dir="$PI_AGENT_DIR/git/github.com/$_org"
    if [[ -d "$org_dir" ]]; then
      existing_count=$(find "$org_dir" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
      break
    fi
  done
  if [[ $existing_count -ge 18 ]]; then
    success "All $existing_count packages already present — skipping sync"
    return 0
  fi

  # CHECK_ONLY mode: report status without installing
  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    info "[check] install_packages: $existing_count packages found (need 18) — would sync"
    return 0
  fi

  # Check if packages were bundled in the tarball
  # Resolve the org directory: helios-agi (current) → sweetcheeks72 (legacy) → nicobailon (fallback)
  local bundled_count=0
  local GIT_ORG_DIR=""
  for _org in helios-agi sweetcheeks72 nicobailon; do
    if [[ -d "$PI_AGENT_DIR/git/github.com/$_org" ]]; then
      GIT_ORG_DIR="$PI_AGENT_DIR/git/github.com/$_org"
      break
    fi
  done

  if [[ -n "$GIT_ORG_DIR" ]]; then
    bundled_count=$(find "$GIT_ORG_DIR" -maxdepth 1 -type d 2>/dev/null | _count)
    ((bundled_count--)) || true  # subtract the parent dir itself
  fi

  if [[ ! -f "$PI_AGENT_DIR/settings.json" ]]; then
    warn "settings.json not found — using Anthropic default"
    cp "$INSTALLER_DIR/provider-configs/anthropic.json" "$PI_AGENT_DIR/settings.json"
  fi

  # Resolve the actual CLI binary — bypass the helios wrapper to avoid
  # infinite loop (wrapper's update calls install.sh which calls this function)
  local cli_bin=""
  cli_bin="$(npm prefix -g 2>/dev/null)/bin/helios" 2>/dev/null
  if [[ ! -x "$cli_bin" ]] || grep -q "helios — AI operating layer" "$cli_bin" 2>/dev/null; then
    cli_bin="$(npm prefix -g 2>/dev/null)/bin/pi" 2>/dev/null
  fi
  local -a cli_cmd
  if [[ -x "$cli_bin" ]]; then
    cli_cmd=("$cli_bin")
  else
    cli_cmd=(npx @helios-agent/cli)
  fi

  if [[ "$bundled_count" -ge 15 ]]; then
    success "Packages pre-bundled in tarball ($bundled_count packages)"

    # Install npm dependencies for bundled packages that have package.json
    info "Installing npm dependencies for bundled packages..."
    for pkg_dir in "$GIT_ORG_DIR"/*/; do
      if [[ -f "${pkg_dir}package.json" ]] && [[ ! -d "${pkg_dir}node_modules" ]]; then
        local pkg_name
        pkg_name="$(basename "$pkg_dir")"
        run_with_spinner "npm install: $pkg_name" npm install --prefix "$pkg_dir" --production --legacy-peer-deps --no-audit --no-fund 2>>"${LOG_FILE:-/dev/null}" || {
          warn "npm install failed for $pkg_name — may work without it"
        }
      elif [[ -d "${pkg_dir}node_modules" ]]; then
        : # node_modules already present from tarball — skip npm install
      fi
    done

    # Verify @helios-agent peer deps are resolvable from agent root
    if [[ ! -d "$PI_AGENT_DIR/node_modules/@helios-agent/pi-coding-agent" ]]; then
      info "Installing @helios-agent peer dependencies in agent root..."
      npm_install_with_recovery "$PI_AGENT_DIR" "npm install (peer deps)" || {
        warn "Agent root npm install failed — packages with @helios-agent peer deps may not work"
      }
    fi

    success "Helios packages installed"
  else
    info "Packages not bundled — running npm install for agent root deps"
    npm_install_with_recovery "$PI_AGENT_DIR" "npm install (agent root)" || {
      warn "npm install failed — some packages may be missing"
    }
    success "Helios packages installed"
  fi
}

# ─── Bedrock AWS Credentials ──────────────────────────────────────────────────
_setup_bedrock_credentials() {
  local env_file="$PI_AGENT_DIR/.env"

  echo ""
  info "Bedrock requires AWS credentials"
  echo -e "  ${DIM}  Get them from: AWS Console → IAM → Security Credentials${RESET}"
  echo ""

  ask "Set up AWS credentials now? [Y/n]:"
  read -t 120 -r do_aws || do_aws=""
  do_aws="${do_aws:-y}"

  if [[ ! "$do_aws" =~ ^[Yy]$ ]]; then
    warn "Skipping — add AWS credentials to ~/.pi/agent/.env before using Bedrock"
    return 0
  fi

  ask "AWS_ACCESS_KEY_ID:"
  read -t 120 -r aws_key_id || aws_key_id=""
  if [[ -z "$aws_key_id" ]]; then
    warn "No access key — add to ~/.pi/agent/.env later"
    return 0
  fi

  ask "AWS_SECRET_ACCESS_KEY:"
  read -t 120 -rs aws_secret || aws_secret=""
  echo ""
  if [[ -z "$aws_secret" ]]; then
    warn "No secret key — add to ~/.pi/agent/.env later"
    return 0
  fi

  ask "AWS_DEFAULT_REGION (default: us-east-1):"
  read -t 120 -r aws_region || aws_region=""
  aws_region="${aws_region:-us-east-1}"

  touch "$env_file"
  # Remove existing AWS entries, then append
  grep -v "^AWS_ACCESS_KEY_ID=\|^AWS_SECRET_ACCESS_KEY=\|^AWS_DEFAULT_REGION=" "$env_file" > "${env_file}.tmp" 2>/dev/null || true
  {
    echo "AWS_ACCESS_KEY_ID=${aws_key_id}"
    echo "AWS_SECRET_ACCESS_KEY=${aws_secret}"
    echo "AWS_DEFAULT_REGION=${aws_region}"
  } >> "${env_file}.tmp"
  mv "${env_file}.tmp" "$env_file"
  chmod 600 "$env_file"

  # Also store secrets in secure backend (Keychain / secret-tool) when available
  if declare -f secrets_store &>/dev/null; then
    secrets_store "AWS_ACCESS_KEY_ID" "$aws_key_id"
    secrets_store "AWS_SECRET_ACCESS_KEY" "$aws_secret"
    info "AWS credentials also saved to secure storage ($(_secrets_backend))"
  fi

  success "AWS credentials saved (region: $aws_region)"
}

# ─── Provider Selection ───────────────────────────────────────────────────────
select_provider() {
  step "Provider Configuration"

  if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local current_provider
    current_provider=$(python3 -c "import json; print(json.load(open('$PI_AGENT_DIR/settings.json')).get('defaultProvider','unknown'))" 2>/dev/null || echo "unknown")
    success "Current provider: $current_provider"
    ask "Change provider? [y/N]:"
    read -t 120 -r change_provider || change_provider=""
    if [[ ! "$change_provider" =~ ^[Yy]$ ]]; then
      return 0
    fi
  fi

  echo ""
  echo -e "  ${BOLD}Select your AI provider:${RESET}"
  echo ""
  echo -e "  ${CYAN}1)${RESET} ${BOLD}Anthropic${RESET}                (Claude via direct API)"
  echo -e "     ${DIM}Auth: browser login — run 'helios' and type /login${RESET}"
  echo ""
  echo -e "  ${CYAN}2)${RESET} ${BOLD}Amazon Bedrock${RESET}           (Claude via AWS)"
  echo -e "     ${DIM}Auth: AWS access key + secret key${RESET}"
  echo ""
  echo -e "  ${CYAN}3)${RESET} ${BOLD}OpenAI${RESET}                   (GPT models)"
  echo -e "     ${DIM}Auth: browser login — run 'helios' and type /login${RESET}"
  echo ""
  ask "Selection [1-3] (default: 1):"
  read -t 120 -r provider_choice || provider_choice=""
  provider_choice="${provider_choice:-1}"

  case "$provider_choice" in
    1)
      SELECTED_PROVIDER="anthropic"
      [[ -f "$INSTALLER_DIR/provider-configs/anthropic.json" ]] && \
        _apply_provider_config "$INSTALLER_DIR/provider-configs/anthropic.json"
      success "Selected: Anthropic — run 'helios' and type /login to authenticate"
      ;;
    2)
      SELECTED_PROVIDER="amazon-bedrock"
      [[ -f "$INSTALLER_DIR/provider-configs/bedrock.json" ]] && \
        _apply_provider_config "$INSTALLER_DIR/provider-configs/bedrock.json"
      success "Selected: Amazon Bedrock"
      _setup_bedrock_credentials
      ;;
    3)
      SELECTED_PROVIDER="openai"
      [[ -f "$INSTALLER_DIR/provider-configs/openai.json" ]] && \
        _apply_provider_config "$INSTALLER_DIR/provider-configs/openai.json"
      success "Selected: OpenAI — run 'helios' and type /login to authenticate"
      ;;
    *)
      SELECTED_PROVIDER="anthropic"
      [[ -f "$INSTALLER_DIR/provider-configs/anthropic.json" ]] && \
        _apply_provider_config "$INSTALLER_DIR/provider-configs/anthropic.json"
      success "Defaulting to Anthropic"
      ;;
  esac
}

# Apply provider config to settings.json using additive merge (preserves user customizations).
# Falls back to direct copy if merge tools unavailable or settings.json is absent.
_apply_provider_config() {
  local provider_cfg="$1"
  if [[ ! -f "$provider_cfg" ]]; then
    return 0
  fi
  # If settings.json already exists, use additive merge via lib/json-merge.js so that
  # user-customized keys (extensions, skills, packages) are not overwritten.
  if [[ -f "$PI_AGENT_DIR/settings.json" ]] && command -v node &>/dev/null && \
     [[ -f "$INSTALLER_DIR/lib/json-merge.js" ]]; then
    node "$INSTALLER_DIR/lib/json-merge.js" \
      "$PI_AGENT_DIR/settings.json" "$provider_cfg" 2>/dev/null || \
      cp "$provider_cfg" "$PI_AGENT_DIR/settings.json"
  else
    cp "$provider_cfg" "$PI_AGENT_DIR/settings.json"
  fi
}

# ─── Agent Root Dependencies ──────────────────────────────────────────────────
# ~/.pi/agent/package.json declares core deps (awilix, neo4j-driver, typebox,
# @helios-agent/pi-coding-agent, etc.) that extensions import at runtime.
# Without this step, ~40+ extensions fail with "Cannot find module" errors.
install_agent_deps() {
  step "Agent Dependencies (verify or install)"

  if [[ ! -f "$PI_AGENT_DIR/package.json" ]]; then
    info "No package.json in agent dir — skipping"
    return 0
  fi

  _better_sqlite3_ok() {
    [[ -d "$PI_AGENT_DIR/node_modules/better-sqlite3" ]] || return 0
    _timeout_cmd 15 node -e "require('$PI_AGENT_DIR/node_modules/better-sqlite3')" 2>/dev/null
  }

  _repair_better_sqlite3() {
    local node_ver
    node_ver=$(node -p 'process.versions.node' 2>/dev/null || echo unknown)
    info "Fetching better-sqlite3 prebuild for Node ${node_ver}..."

    # Attempt 1: prebuild-install downloads the correct binary for this Node ABI
    local bs3_dir="$PI_AGENT_DIR/node_modules/better-sqlite3"
    local pbi_bin="$PI_AGENT_DIR/node_modules/prebuild-install/bin.js"
    if [[ -f "$pbi_bin" ]]; then
      run_with_spinner "Download better-sqlite3 prebuild" \
        bash -c "cd '$bs3_dir' && node '$pbi_bin' --runtime napi 2>&1" || true
    elif [[ -f "$bs3_dir/node_modules/prebuild-install/bin.js" ]]; then
      run_with_spinner "Download better-sqlite3 prebuild" \
        bash -c "cd '$bs3_dir' && node node_modules/prebuild-install/bin.js --runtime napi 2>&1" || true
    else
      run_with_spinner "Download better-sqlite3 prebuild" \
        bash -c "cd '$PI_AGENT_DIR' && npx --yes prebuild-install --cwd node_modules/better-sqlite3 --runtime napi 2>&1" || true
    fi

    if _better_sqlite3_ok; then
      success "better-sqlite3 prebuild installed for Node ${node_ver} ✓"
      return 0
    fi

    # Attempt 2: npm rebuild from source (requires Xcode CLT)
    local node_major
    node_major=$(node -e 'console.log(parseInt(process.version.slice(1)))' 2>/dev/null || echo 0)
    if [[ "$node_major" -gt 22 ]]; then
      warn "Node ${node_ver} is newer than supported — native modules may fail"
    fi

    run_with_spinner "Rebuild better-sqlite3 from source" \
      bash -c "cd '$PI_AGENT_DIR' && npm rebuild better-sqlite3 --build-from-source 2>&1" || {
      warn "better-sqlite3 rebuild failed"
    }

    if _better_sqlite3_ok; then
      success "better-sqlite3 rebuilt for Node ${node_ver} ✓"
      return 0
    fi

    # Attempt 3: full reinstall
    rm -rf "$PI_AGENT_DIR/node_modules/better-sqlite3"
    run_with_spinner "Reinstall better-sqlite3" \
      bash -c "cd '$PI_AGENT_DIR' && npm install better-sqlite3 --no-audit --no-fund 2>&1" || {
      warn "better-sqlite3 reinstall failed"
      return 1
    }

    if _better_sqlite3_ok; then
      success "better-sqlite3 reinstalled for Node ${node_ver} ✓"
      return 0
    fi

    warn "better-sqlite3 does not load — try: cd ~/.pi/agent && npm rebuild better-sqlite3"
    return 1
  }

  # CHECK_ONLY mode: report status without installing
  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    if [[ -d "$PI_AGENT_DIR/node_modules/awilix" ]] && \
       [[ -d "$PI_AGENT_DIR/node_modules/neo4j-driver" ]]; then
      info "[check] install_agent_deps: awilix + neo4j-driver present"
    else
      info "[check] install_agent_deps: deps missing — would run npm install"
    fi
    return 0
  fi

  # Check if deps were bundled in tarball (self-contained install)
  if [[ -d "$PI_AGENT_DIR/node_modules/awilix" ]] && \
     [[ -d "$PI_AGENT_DIR/node_modules/neo4j-driver" ]]; then

    # Verify native modules load on this architecture
    local native_ok=true
    _better_sqlite3_ok || native_ok=false

    if [[ "$native_ok" == "true" ]]; then
      # After native modules check passes, also verify ESM import works
      local esm_ok=true
      if [[ -f "$PI_AGENT_DIR/node_modules/@helios-agent/pi-coding-agent/dist/index.js" ]]; then
        _timeout_cmd 30 node --input-type=module -e "
          import { pathToFileURL } from 'url';
          await import(pathToFileURL('$PI_AGENT_DIR/node_modules/@helios-agent/pi-coding-agent/dist/index.js'));
        " 2>/dev/null || esm_ok=false
      else
        esm_ok=false
      fi

      if [[ "$esm_ok" == "true" ]]; then
        success "Agent deps verified — pi-coding-agent ESM import OK ✓"
        return 0
      fi
      # ESM import failed — fall through to full npm install
    else
      info "Deps present but native modules need rebuild for $(uname -m)..."
      if _repair_better_sqlite3; then
        return 0
      fi
      warn "Native module repair failed — trying full dependency reinstall"
    fi
  fi

  # Backup bundled node_modules before npm install (restore on failure)
  local nm_backup=""
  if [[ -d "$PI_AGENT_DIR/node_modules" ]]; then
    nm_backup="$PI_AGENT_DIR/node_modules.pre-install-backup"
    mv "$PI_AGENT_DIR/node_modules" "$nm_backup" 2>/dev/null || nm_backup=""
  fi

  # Fallback: full npm install (deps not in tarball or rebuild failed)
  if [[ "$OFFLINE_MODE" == "true" ]]; then
    warn "Offline mode — skipping npm install, using bundled deps only"
    return 0
  fi

  info "Installing agent dependencies via npm (not bundled in tarball)..."
  npm_install_with_recovery "$PI_AGENT_DIR" "npm install (agent root)" || {
    fail "npm install (agent root)"
    warn "Agent root npm install failed — many extensions will not load"
    info "You can retry: cd ~/.pi/agent && npm install --production"
    INSTALL_WARNINGS+=("Agent root deps failed — extensions will be broken")
    
    # Restore bundled node_modules from backup
    if [[ -n "$nm_backup" ]] && [[ -d "$nm_backup" ]]; then
      info "Restoring bundled node_modules from backup..."
      rm -rf "$PI_AGENT_DIR/node_modules"
      mv "$nm_backup" "$PI_AGENT_DIR/node_modules"
      warn "Restored pre-install node_modules — bundled deps should still work"
    fi
    
    return 1
  }
  
  # Clean up backup on success
  [[ -n "$nm_backup" ]] && rm -rf "$nm_backup"

  if ! _better_sqlite3_ok; then
    _repair_better_sqlite3 || {
      fail "better-sqlite3 native module"
      INSTALL_WARNINGS+=("better-sqlite3 failed — graph cache disabled or unstable")
      return 1
    }
  fi
  
  success "Agent dependencies installed"
}

# ─── Skill-Graph Dependencies ─────────────────────────────────────────────────
install_skill_deps() {
  step "Skill-Graph Dependencies"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    info "[dry-run] Would install skill-graph dependencies"
    return 0
  fi

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

# ─── Helios Browse (Browser Automation) ───────────────────────────────────────
setup_helios_browse() {
  step "Helios Browse (Browser Automation)"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    info "[dry-run] Would install playwright-core and Chromium"
    return 0
  fi

  # Install playwright-core if not present
  if _timeout_cmd 10 node -e "require('playwright-core')" 2>/dev/null; then
    success "playwright-core available"
  else
    run_with_spinner "Installing playwright-core" \
      bash -c "cd '$PI_AGENT_DIR' && npm install --no-save playwright-core 2>&1" || {
      warn "playwright-core install failed — browser automation will be unavailable"
      info "You can retry: cd ~/.pi/agent && npm install playwright-core"
      INSTALL_WARNINGS+=("playwright-core failed — browser automation unavailable")
      return 0
    }
  fi

  # Install Chromium browser binary
  if compgen -G "$HOME/.cache/ms-playwright/chromium-*" > /dev/null 2>&1; then
    success "Chromium browser already installed"
  else
    run_with_spinner "Installing Chromium for browser automation" \
      bash -c "npx playwright-core install chromium 2>&1" || {
      warn "Chromium install failed — you can install later: npx playwright-core install chromium"
      INSTALL_WARNINGS+=("Chromium not installed — run: npx playwright-core install chromium")
    }
  fi

  # Apply browse Memgraph schema
  local migrate="$PI_AGENT_DIR/scripts/skill-graph/migrate-browse-schema.js"
  if [[ -f "$migrate" ]]; then
    local mg_running=""
    mg_running=$(resolve_memgraph_container 2>/dev/null) || mg_running=""
    if [[ -n "$mg_running" ]]; then
      node "$migrate" >> "$LOG_FILE" 2>&1 && info "Browse schema applied" || \
        warn "Browse schema migration had issues — see $LOG_FILE"
    else
      info "Memgraph not running — browse schema will apply on first use"
    fi
  fi

  # Create browser profile/session directories
  mkdir -p "$HOME/.pi/browser-profiles" "$HOME/.pi/browser-sessions"
  chmod 700 "$HOME/.pi/browser-profiles"
  success "Helios Browse configured"
}

# ─── Governance Extension Dependencies ────────────────────────────────────────
install_governance_deps() {
  step "Governance Extension Dependencies"

  if [[ "${CHECK_ONLY:-false}" == "true" ]]; then
    info "[dry-run] Would install governance deps"
    return 0
  fi

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

# ─── Runtime Contract: persist resolved Memgraph settings ───────────────────────
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
    # Resolve container via shared lib (containers.sh); fallback to 'memgraph'
    resolved_container=$(resolve_memgraph_container) || resolved_container="memgraph"
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
    echo "MEMGRAPH_PASSWORD=memgraph"
    echo "OLLAMA_URL=http://localhost:11434"
    echo "HELIOS_GRAPH_BOOTSTRAP_STATE_DIR=$PI_AGENT_DIR/state/codebase-bootstrap"
  } > "$contract_file"
  chmod 600 "$contract_file"
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

  # Check if a Memgraph container already exists (running or stopped)
  # Priority: exact 'memgraph' → legacy 'familiar-graph-1' → compose label
  local mg_container=""
  local _name
  for name in memgraph familiar-graph-1; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
      mg_container="$name"
      break
    fi
  done
  # Fallback: check compose label if direct names not found
  if [[ -z "$mg_container" ]]; then
    mg_container=$(docker ps -a --format '{{.Names}}\t{{.Labels}}' 2>/dev/null \
      | grep "com.docker.compose.service=memgraph" \
      | head -1 | cut -f1) || mg_container=""
  fi

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
      # Set DOCKER_DEFAULT_PLATFORM so compose pulls the image for the host arch.
      # The docker-compose.yml uses `platform: "${DOCKER_DEFAULT_PLATFORM}"` for
      # the memgraph service, preventing cross-arch emulation on Apple Silicon.
      local platform_flag
      platform_flag=$(docker_platform)
      STEP_TIMEOUT="$MEMGRAPH_TIMEOUT" run_with_spinner "Starting Memgraph (first time — downloading image)" \
        bash -c "cd '$PI_AGENT_DIR/proxies/memgraph' && DOCKER_DEFAULT_PLATFORM='$platform_flag' $compose_cmd up -d" || {
        warn "Memgraph failed to start — you can set it up later"
        return 0
      }
      success "Memgraph started"
    else
      warn "No docker-compose.yml found — skipping Memgraph"
      return 0
    fi
  fi

  # Apply graph schema — resolve running container via shared lib
  local mg_running=""
  mg_running=$(resolve_memgraph_container) || mg_running=""
  local schema="$PI_AGENT_DIR/skills/skill-graph/scripts/schema.cypher"
  if [[ -n "$mg_running" ]] && [[ -f "$schema" ]]; then
    docker exec -i "$mg_running" mgconsole --username memgraph --password memgraph \
      < "$schema" >> "$LOG_FILE" 2>&1 && info "Graph schema applied" || true
  fi

  # Verify Memgraph Bolt connectivity (TASK-04: capture result, retry, show logs on failure)
  if [[ -n "$mg_running" ]]; then
    local bolt_ok=false
    local bolt_attempt
    for bolt_attempt in 1 2 3; do
      if echo "RETURN 1 AS alive;" | docker exec -i "$mg_running" mgconsole \
           --username "${MEMGRAPH_USER:-memgraph}" --password "${MEMGRAPH_PASSWORD:-memgraph}" \
           --output-format csv >> "$LOG_FILE" 2>&1; then
        bolt_ok=true
        break
      fi
      if (( bolt_attempt < 3 )); then
        warn "Memgraph Bolt check failed (attempt $bolt_attempt/3) — retrying in 5s..."
        sleep 5
      fi
    done
    if [[ "$bolt_ok" == true ]]; then
      success "Memgraph Bolt connection verified"
    else
      warn "Memgraph Bolt verification failed after 3 attempts"
      info "Container logs:"
      docker logs --tail 20 "$mg_running" 2>&1 | sed 's/^/  /' || true
      INSTALL_WARNINGS+=("Memgraph Bolt check failed — check container logs: docker logs $mg_running")
    fi
  fi

  # Persist the resolved runtime contract
  persist_runtime_contract "$mg_running"
}

# ─── Ollama (Local LLM Inference — Optional) ─────────────────────────────────
setup_ollama() {
  # DEPRECATED: Embeddings now use MAGE (built into memgraph-mage image).
  # Ollama is no longer required. This function is retained for users who
  # want local LLM inference but is not called during standard install.
  step "Ollama (Optional — Local LLM Inference)"

  if ! command -v ollama &>/dev/null; then
    info "Ollama not found — skipping local embeddings"
    info "To enable semantic search later: brew install ollama && ollama pull nomic-embed-text"
    INSTALL_WARNINGS+=("Ollama skipped — install from ollama.ai for local embeddings")
    return 0
  fi

  success "Ollama installed"

  # Ensure Ollama is running
  if ! curl -fs http://localhost:11434/api/tags &>/dev/null; then
    info "Starting Ollama..."
    if pgrep -x ollama &>/dev/null \
       || { [[ "$(uname -s)" == "Darwin" ]] && launchctl list 2>/dev/null | grep -q com.ollama; }; then
      success "Ollama already running (managed by system)"
    else
      nohup ollama serve >> "$LOG_FILE" 2>&1 &
      disown 2>/dev/null || true
    fi
    # Wait with retry loop (up to 15s)
    local ollama_ready=false
    for i in {1..15}; do
      if curl -fs http://localhost:11434/api/tags &>/dev/null; then
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
  local OLLAMA_PULL_TIMEOUT="${OLLAMA_PULL_TIMEOUT:-300}"
  for model in nomic-embed-text granite-embedding; do
    if ollama list 2>/dev/null | awk '{print $1}' | grep -q "^${model}:"; then
      success "$model model ready"
    else
      run_with_spinner "Pulling $model (this may take a few minutes)" \
        _timeout_cmd "$OLLAMA_PULL_TIMEOUT" retry_with_backoff 3 10 ollama pull "$model" || {
        if [[ $? -eq 124 ]]; then
          warn "Ollama pull of $model timed out after ${OLLAMA_PULL_TIMEOUT}s"
        else
          warn "Failed to pull $model"
        fi
        info "Retry manually: ollama pull $model"
      }
    fi
  done
}

# ─── MCP Servers ──────────────────────────────────────────────────────────────

# ─── SearXNG (Private Search Engine) ────────────────────────────────────────
setup_searxng() {
  step "SearXNG (Private Search Engine)"

  if ! command -v docker &>/dev/null; then
    warn "Docker not available — SearXNG skipped"
    return 0
  fi

  if ! docker info &>/dev/null 2>&1; then
    warn "Docker not running — SearXNG skipped"
    return 0
  fi

  # Check if container already exists
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^helios-searxng$"; then
    if docker ps --format '{{.Names}}' | grep -q "^helios-searxng$" 2>/dev/null; then
      success "SearXNG running (helios-searxng)"
    else
      info "Starting existing SearXNG container..."
      docker start helios-searxng >> "$LOG_FILE" 2>&1 && \
        success "SearXNG started" || \
        warn "Could not start helios-searxng"
    fi
    return 0
  fi

  # SearXNG config is bundled in the tarball — resolve org directory with fallback
  local SEARXNG_DIR=""
  for _org in helios-agi sweetcheeks72 nicobailon; do
    if [[ -f "$PI_AGENT_DIR/git/github.com/$_org/helios-searxng/helios-compose.yml" ]]; then
      SEARXNG_DIR="$PI_AGENT_DIR/git/github.com/$_org/helios-searxng"
      break
    fi
  done

  if [[ -z "$SEARXNG_DIR" ]]; then
    warn "SearXNG config (helios-compose.yml) not found under any org dir"
    info "Re-run the installer or update your helios-agent tarball"
    INSTALL_WARNINGS+=("SearXNG skipped — config not in bundle")
    return 0
  fi

  # Generate a unique secret key for this installation
  local SECRET_KEY
  SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -A n -t x1 | tr -d ' \n')
  if [[ -f "$SEARXNG_DIR/helios-settings/settings.yml" ]]; then
    # macOS sed needs -i '' ; Linux sed needs -i
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i "" "s/secret_key: .*/secret_key: \"${SECRET_KEY}\"/" "$SEARXNG_DIR/helios-settings/settings.yml" \
        || warn "Failed to set SearXNG secret key"
    else
      sed -i "s/secret_key: .*/secret_key: \"${SECRET_KEY}\"/" "$SEARXNG_DIR/helios-settings/settings.yml" \
        || warn "Failed to set SearXNG secret key"
    fi
  fi

  info "Starting SearXNG container..."
  (cd "$SEARXNG_DIR" && docker compose -f helios-compose.yml up -d) >> "$LOG_FILE" 2>&1 || {
    warn "Failed to start SearXNG — check docker logs"
    return 0
  }

  # Wait for SearXNG to be ready
  local retries=0
  while [[ $retries -lt 10 ]]; do
    if curl -sf http://localhost:8080/healthz > /dev/null 2>&1 || \
       curl -sf http://localhost:8080/ > /dev/null 2>&1; then
      success "SearXNG ready at http://localhost:8080"
      info "  Engines: General (DDG/Brave/Bing), Legal (CourtListener), Science, Code, News"
      return 0
    fi
    sleep 2
    retries=$((retries + 1))
  done

  if docker ps --format '{{.Names}}' | grep -q "^helios-searxng$" 2>/dev/null; then
    success "SearXNG container running (health check pending)"
  else
    warn "SearXNG container failed to start"
  fi
}

setup_mcp_servers() {
  step "MCP Servers"

  # uv/uvx — needed for mcp-memgraph
  if ! command -v uvx &>/dev/null; then
    info "Installing uv (Python package manager for MCP servers)..."
    if curl -fLsS https://astral.sh/uv/install.sh 2>/dev/null | sh >> "$LOG_FILE" 2>&1; then
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
    if command -v timeout &>/dev/null; then
      timeout 30 uvx --from mcp-memgraph mcp-memgraph --help >> "$LOG_FILE" 2>&1 || true
    elif command -v gtimeout &>/dev/null; then
      gtimeout 30 uvx --from mcp-memgraph mcp-memgraph --help >> "$LOG_FILE" 2>&1 || true
    else
      # macOS without coreutils: run with background kill
      uvx --from mcp-memgraph mcp-memgraph --help >> "$LOG_FILE" 2>&1 &
      local _uvx_pid=$!
      ( sleep 30 && kill "$_uvx_pid" 2>/dev/null ) &
      local _kill_pid=$!
      wait "$_uvx_pid" 2>/dev/null || true
      kill "$_kill_pid" 2>/dev/null || true
    fi
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
    except (json.JSONDecodeError, OSError):
        pass  # corrupted or missing file — start fresh
with open(target, 'w') as f:
    json.dump(mcp, f, indent=2)
    f.write('\n')
" "$mcp_file" 2>/dev/null && success "mcp.json written (figma-remote, memgraph, github)" || warn "Could not write mcp.json"
  chmod 600 "$mcp_file" 2>/dev/null || true
}

# ─── API Key Setup ────────────────────────────────────────────────────────────
setup_api_keys() {
  step "Service Keys (optional)"

  # Helios handles AI provider auth via OAuth (browser login on first run).
  # These are only for ancillary services that need API keys.

  local env_file="$PI_AGENT_DIR/.env"

  if [[ -f "$env_file" ]]; then
    info ".env exists — skipping (edit manually if needed)"
    success "Service keys file present"
    return
  fi

  # Create minimal .env for ancillary services only
  cat > "$env_file" << 'ENV_EOF'
# Helios Service Keys (optional)
# AI provider auth is handled by Helios OAuth — run 'helios' to log in.
# These keys are for ancillary services only.

# GitHub token — for PR review via MCP (github.com/settings/tokens)
GITHUB_TOKEN=

# AWS credentials — required for Amazon Bedrock provider
# Get from: AWS Console → IAM → Security Credentials
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1

# Groq — for Whisper transcription (console.groq.com)
GROQ_API_KEY=

# Figma — for design MCP (figma.com → Account → API tokens)
FIGMA_MCP_TOKEN=
ENV_EOF
  chmod 600 "$env_file"

  echo ""
  echo -e "  ${DIM}Optional service keys can be added to: ~/.pi/agent/.env${RESET}"
  echo -e "  ${DIM}Helios handles AI provider auth automatically when you run 'helios'.${RESET}"

  success ".env created (service keys — edit later if needed)"
}

# ─── Wire Service Keys to Shell ──────────────────────────────────────────────
wire_env_to_shell() {
  step "Shell Environment"

  local env_file="$PI_AGENT_DIR/.env"

  if [[ ! -f "$env_file" ]]; then
    info "No .env file — skipping shell wiring"
    return
  fi

  local shell_profile=""
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    shell_profile="$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      shell_profile="$HOME/.bash_profile"
    else
      shell_profile="$HOME/.bashrc"
    fi
  else
    shell_profile="$HOME/.profile"
  fi

  local source_cmd="[ -f ~/.pi/agent/.env ] && set -a && source ~/.pi/agent/.env && set +a"

  if grep -qF ".pi/agent/.env" "$shell_profile" 2>/dev/null; then
    success "Shell already sources .env"
  else
    echo "" >> "$shell_profile"
    echo "# Helios service keys" >> "$shell_profile"
    echo "$source_cmd" >> "$shell_profile"
    success "Added .env sourcing to $shell_profile"
  fi

  # Source now for immediate use.
  # L4 fix: use first-'='-only split so values containing '=' (e.g. base64
  # API keys, URLs with query strings like https://host?a=b) are preserved
  # verbatim.  Splitting on IFS-equals then re-reading is fragile for such values.
  while IFS= read -r _env_line; do
    # Strip leading whitespace and skip comments / blanks
    _env_line="${_env_line#"${_env_line%%[! ]*}"}"
    [[ -z "$_env_line" || "$_env_line" == \#* ]] && continue
    # Split on FIRST '=' only using %%=* (key) and #*= (value)
    _env_key="${_env_line%%=*}"
    _env_val="${_env_line#*=}"
    _env_key="${_env_key#export }"              # strip optional 'export ' prefix
    _env_key="${_env_key#"${_env_key%%[! ]*}"}" # trim leading whitespace
    _env_key="${_env_key%"${_env_key##*[! ]}"}" # trim trailing whitespace
    _env_val="${_env_val#"${_env_val%%[! ]*}"}" # trim leading whitespace
    _env_val="${_env_val%"${_env_val##*[! ]}"}" # trim trailing whitespace
    _env_val="${_env_val#\"}" ; _env_val="${_env_val%\"}"  # strip double quotes
    _env_val="${_env_val#\'}" ; _env_val="${_env_val%\'}"  # strip single quotes
    [[ "$_env_key" =~ ^[A-Z_][A-Z_0-9]*$ ]] && [[ -n "$_env_val" ]] && export "$_env_key=$_env_val"
  done < "$env_file"
  success "API keys loaded into current session"

  warn "Restart your terminal or run: source $shell_profile"
}

# ─── Pi Auth (OAuth browser login) ────────────────────────────────────────────
setup_pi_auth() {
  step "AI Provider Login"

  # Check if Pi is available
  local pi_cmd=""
  if command -v helios &>/dev/null; then
    pi_cmd="helios"
  elif command -v pi &>/dev/null; then
    pi_cmd="pi"
  elif [[ -f "$HOME/.npm-global/bin/pi" ]]; then
    pi_cmd="$HOME/.npm-global/bin/pi"
  elif [[ -f "$HOME/.local/bin/helios" ]]; then
    pi_cmd="$HOME/.local/bin/helios"
  fi

  if [[ -z "$pi_cmd" ]]; then
    warn "Helios CLI not found — you can log in later by running 'helios'"
    return 0
  fi

  # Check if user already has auth tokens
  local auth_file="$PI_AGENT_DIR/auth.json"
  if [[ -f "$auth_file" ]]; then
    local has_tokens
    has_tokens=$(node -e "
      const a = require('$auth_file');
      const providers = Object.keys(a).filter(k => a[k].type === 'oauth' || a[k].type === 'api_key');
      console.log(providers.length);
    " 2>/dev/null || echo "0")
    if [[ "${has_tokens:-0}" -gt 0 ]]; then
      success "Already logged in ($has_tokens provider(s) configured)"
      return 0
    fi
  fi

  echo ""
  echo -e "  ${BOLD}Helios needs to connect to an AI provider.${RESET}"
  echo ""
  echo -e "  ${DIM}This will open Pi, where you can log in to your AI provider${RESET}"
  echo -e "  ${DIM}(Anthropic, OpenAI, Google, etc.) via your browser.${RESET}"
  echo ""
  echo -e "  ${DIM}Inside Pi:${RESET}"
  echo -e "    ${CYAN}1.${RESET} Type ${BOLD}/login${RESET} and press Enter"
  echo -e "    ${CYAN}2.${RESET} Select your AI provider"
  echo -e "    ${CYAN}3.${RESET} Log in via the browser window that opens"
  echo -e "    ${CYAN}4.${RESET} Type ${BOLD}/exit${RESET} to return to the installer"
  echo ""
  # Skip if non-interactive (e.g., piped install, CI)
  if [[ ! -t 0 ]]; then
    info "Non-interactive mode — skipping login (run 'helios' later and type /login)"
    return 0
  fi

  ask "Open Helios now to log in? [Y/n]:"
  read -t 120 -r do_login || do_login=""
  do_login="${do_login:-y}"

  if [[ "$do_login" =~ ^[Yy]$ ]]; then
    echo ""
    info "Launching Helios — type /login to connect your AI provider, then /exit when done"
    echo -e "  ${DIM}────────────────────────────────────────────────────${RESET}"
    echo ""

    # Launch Pi interactively — user will type /login, authenticate, then /exit
    "$pi_cmd" || true

    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────────────${RESET}"

    # Check if auth was successful
    if [[ -f "$auth_file" ]]; then
      local post_tokens
      post_tokens=$(node -e "
        const a = require('$auth_file');
        const providers = Object.keys(a).filter(k => a[k].type === 'oauth' || a[k].type === 'api_key');
        console.log(providers.length);
      " 2>/dev/null || echo "0")
      if [[ "${post_tokens:-0}" -gt 0 ]]; then
        success "Logged in to $post_tokens provider(s)"
      else
        warn "No providers configured — run 'helios' later and type /login"
      fi
    else
      warn "Auth not completed — run 'helios' later and type /login"
    fi
  else
    info "Skipping login — run 'helios' later and type /login to connect your AI provider"
  fi
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

  if [[ -d "$FAMILIAR_DIR" ]] && [[ -f "$FAMILIAR_DIR/VERSION" ]]; then
    local local_ver
    local_ver="$(cat "$FAMILIAR_DIR/VERSION" 2>/dev/null || echo "0")"
    local remote_ver
    remote_ver="$(curl -fsSL --max-time 15 "$HELIOS_RELEASE_URL/familiar-VERSION" 2>/dev/null || echo "")"
    if [[ -n "$remote_ver" && "$local_ver" == "$remote_ver" ]]; then
      success "Familiar already up to date ($local_ver)"
      return 0
    fi
    if [[ -n "$remote_ver" ]]; then
      info "Familiar update available: $local_ver → $remote_ver"
    fi
  fi

  info "Downloading Familiar runtime tarball..."
  local tmp_tarball
  tmp_tarball="$(mktemp)"
  if ! curl -fSL --retry 3 --retry-delay 5 --max-time 300 \
       -o "$tmp_tarball" "$HELIOS_RELEASE_URL/familiar-latest.tar.gz" 2>>"${LOG_FILE:-/dev/null}"; then
    warn "Could not download Familiar tarball"
    rm -f "$tmp_tarball"
    INSTALL_WARNINGS+=("Familiar skills skipped — download failed")
    return 0
  fi

  local tarball_size
  tarball_size=$(wc -c < "$tmp_tarball" 2>/dev/null || echo "0")
  if [[ "$tarball_size" -lt 1048576 ]]; then
    warn "Familiar tarball suspiciously small (${tarball_size} bytes) — skipping"
    rm -f "$tmp_tarball"
    return 0
  fi

  if [[ -d "$FAMILIAR_DIR" ]]; then
    local backup_dir="${FAMILIAR_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -a "$FAMILIAR_DIR" "$backup_dir" 2>/dev/null || true
    rm -rf "$FAMILIAR_DIR"
  fi

  mkdir -p "$FAMILIAR_DIR"
  if ! tar -xzf "$tmp_tarball" -C "$FAMILIAR_DIR" --strip-components=1 2>>"${LOG_FILE:-/dev/null}"; then
    warn "Familiar tarball extraction failed"
    if [[ -d "${backup_dir:-}" ]]; then
      mv "$backup_dir" "$FAMILIAR_DIR"
    fi
    rm -f "$tmp_tarball"
    return 0
  fi
  rm -f "$tmp_tarball"

  success "Familiar installed to $FAMILIAR_DIR"
}

# ─── Deduplicate Skills & Extensions ──────────────────────────────────────────
dedup_skills_extensions() {
  step "Deduplicating Skills & Extensions"

  # Remove legacy local extensions that are now provided as git packages
  local legacy_exts=("pi-review-loop")
  for legacy_ext in "${legacy_exts[@]}"; do
    local _found_pkg=false
    for _org in helios-agi sweetcheeks72 nicobailon; do
      if [[ -d "$PI_AGENT_DIR/git/github.com/$_org/$legacy_ext" ]]; then
        _found_pkg=true
        break
      fi
    done
    if [[ -d "$PI_AGENT_DIR/extensions/$legacy_ext" ]] && $_found_pkg; then
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
  if command -v helios &>/dev/null; then
    success "helios binary found: $(which helios)"
  else
    error "helios binary not in PATH"
    all_ok=false
  fi

  if command -v pi &>/dev/null; then
    local pi_path
    pi_path="$(command -v pi)"
    case "$pi_path" in
      "$HOME/.local/bin/pi"|/usr/local/bin/pi)
        success "pi shim found: $pi_path"
        ;;
      *)
        warn "pi resolves to legacy path: $pi_path"
        warn "Open a new terminal or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
        INSTALL_WARNINGS+=("Legacy pi command is still ahead of ~/.local/bin in PATH")
        ;;
    esac
  fi

  # Agent dir
  if [[ -d "$PI_AGENT_DIR" ]]; then
    success "~/.pi/agent/ exists"
  else
    error "~/.pi/agent/ not found"
    all_ok=false
  fi

  local legacy_path
  for legacy_path in "$HOME/.pi/git" "$HOME/.pi/extensions" "$HOME/.pi/lib"; do
    if [[ -e "$legacy_path" ]]; then
      warn "Legacy path remains and may cause duplicate loader errors: $legacy_path"
      INSTALL_WARNINGS+=("Legacy path remains: $legacy_path")
      all_ok=false
    fi
  done

  # Count agents
  local agent_count=0
  if [[ -d "$PI_AGENT_DIR/agents" ]]; then
    agent_count=$(find "$PI_AGENT_DIR/agents" -name "*.md" 2>/dev/null | _count)
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
     true) | _count
  )
  if [[ "$skill_count" -ge 16 ]]; then
    success "Skills: $skill_count (expect 16+)"
  else
    warn "Skills: $skill_count (expected 16+)"
  fi

  # Count extensions
  local ext_count=0
  if [[ -d "$PI_AGENT_DIR/extensions" ]]; then
    ext_count=$(find "$PI_AGENT_DIR/extensions" -name "*.js" -o -name "index.ts" 2>/dev/null | _count)
    success "Extensions: found in ~/.pi/agent/extensions/"
  fi

  # .env has at least one key set
  local env_file="$PI_AGENT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    local keys_set
    keys_set=$(grep -v '^#' "$env_file" 2>/dev/null | grep -v '^$' | grep -v '=$' | _count) || keys_set=0
    if [[ "$keys_set" -gt 0 ]]; then
      success ".env: $keys_set service key(s) configured"
    else
      info ".env exists — no service keys set (optional, AI auth handled by Helios)"
    fi
  else
    info ".env not found — service keys are optional (AI auth handled by Helios)"
  fi

  # settings.json — full schema validation
  if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local configured_provider
    configured_provider=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('defaultProvider','?'))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || \
      node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultProvider||'?')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "?")
    success "settings.json: provider=$configured_provider"
    validate_settings "$PI_AGENT_DIR/settings.json" || all_ok=false
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
  echo -e "${BOLD}${GREEN}  ✓ Helios Installation Complete!${RESET} ${DIM}(installer v${INSTALLER_VERSION})${RESET}"
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  local helios_ver
  helios_ver=$("$HOME/.local/bin/helios" --version 2>/dev/null || helios --version 2>/dev/null || echo "unknown")
  echo -e "  ${GREEN}${BOLD}Helios ${helios_ver}${RESET} ${DIM}(installer v${INSTALLER_VERSION})${RESET}"

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
  echo -e "    ${DIM}~/.pi/agent/.env${RESET}          — Service keys (GitHub, Groq — optional)"
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
  echo -e "    ${DIM}bash install.sh --fresh${RESET}  — Re-run full setup"
  echo ""
  echo -e "  ${BOLD}Troubleshooting:${RESET}  ${DIM}See $INSTALLER_DIR/README.md${RESET}"
  echo ""
  echo -e "  ${CYAN}ℹ ${RESET}${BOLD}Run 'helios' to log in to your AI provider.${RESET}"
  echo -e "  ${DIM}  Helios handles authentication via browser login — no API keys needed.${RESET}"
  echo ""
}

# ─── Update Detection ─────────────────────────────────────────────────────────
# If helios is already installed and configured, skip interactive steps.
# User can force fresh setup with: bash install.sh --fresh
detect_update_mode() {
  UPDATE_MODE=false
  FULL_UPDATE=false

  # --fresh flag forces full interactive setup
  for arg in "$@"; do
    [[ "$arg" == "--fresh" ]] && return 0
    [[ "$arg" == "--full" ]] && { FULL_UPDATE=true; UPDATE_MODE=true; return 0; }
    [[ "$arg" == "--update" ]] && { UPDATE_MODE=true; return 0; }
  done

  # If agent dir exists with VERSION file, this is an update (regardless of settings state)
  if [[ -d "$PI_AGENT_DIR" ]] && [[ -f "$PI_AGENT_DIR/VERSION" ]]; then
    UPDATE_MODE=true
    info "Existing install detected ($(cat "$PI_AGENT_DIR/VERSION" 2>/dev/null || echo '?'))"
    info "Running in update mode — skipping interactive steps"
    info "To re-run full setup: bash install.sh --fresh"
    echo ""
    return 0
  fi

  # Fallback: settings.json with a configured provider also indicates existing install
  if [[ -d "$PI_AGENT_DIR" ]] && [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
    local current_provider=""
    if command -v python3 &>/dev/null; then
      current_provider=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('defaultProvider',''))" "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
    elif command -v node &>/dev/null; then
      current_provider=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).defaultProvider||'')" -- "$PI_AGENT_DIR/settings.json" 2>/dev/null || echo "")
    fi

    if [[ -n "$current_provider" ]] && [[ "$current_provider" != "null" ]]; then
      UPDATE_MODE=true
      info "Existing install detected (no VERSION file, but settings.json configured)"
      info "Running in update mode — skipping interactive steps"
      info "To re-run full setup: bash install.sh --fresh"
      echo ""
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
    except (json.JSONDecodeError, OSError):
        pass  # corrupted or missing — start fresh
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
    sleep 1
    if kill -0 "$bg_pid" 2>/dev/null; then
      success "Bootstrap job launched (PID $bg_pid)"
    else
      warn "Bootstrap job failed to start — check $bootstrap_log"
    fi
    info "Log: $bootstrap_log"
    info "Status: ls $bootstrap_dir/"
  else
    warn "Failed to launch bootstrap background job"
    info "Manual run: node $bootstrap_script"
  fi
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
      # shellcheck disable=SC2024
      sudo apt-get install -y ffmpeg >> "$LOG_FILE" 2>&1 && success "ffmpeg installed" || warn "ffmpeg: install manually"
    elif command -v dnf &>/dev/null; then
      # shellcheck disable=SC2024
      sudo dnf install -y ffmpeg >> "$LOG_FILE" 2>&1 && success "ffmpeg installed" || warn "ffmpeg: install manually — sudo dnf install ffmpeg"
    elif command -v pacman &>/dev/null; then
      # shellcheck disable=SC2024
      sudo pacman -S --noconfirm ffmpeg >> "$LOG_FILE" 2>&1 && success "ffmpeg installed" || warn "ffmpeg: install manually — sudo pacman -S ffmpeg"
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
    elif command -v apt-get &>/dev/null; then
      # shellcheck disable=SC2024
      sudo apt-get install -y yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || \
        { command -v pip3 &>/dev/null && pip3 install --user yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed (pip3)"; } || \
        warn "yt-dlp: install manually — pip3 install --user yt-dlp"
    elif command -v dnf &>/dev/null; then
      # shellcheck disable=SC2024
      sudo dnf install -y yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || \
        { command -v pip3 &>/dev/null && pip3 install --user yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed (pip3)"; } || \
        warn "yt-dlp: install manually — pip3 install --user yt-dlp"
    elif command -v pacman &>/dev/null; then
      # shellcheck disable=SC2024
      sudo pacman -S --noconfirm yt-dlp >> "$LOG_FILE" 2>&1 && success "yt-dlp installed" || \
        warn "yt-dlp: install manually — sudo pacman -S yt-dlp"
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
    if is_memgraph_running 2>/dev/null; then
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
      local mg_container_name
      mg_container_name=$(resolve_memgraph_container 2>/dev/null) || mg_container_name="memgraph"
      cat > "$mg_plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.helios.memgraph</string>
  <key>ProgramArguments</key>
  <array><string>${docker_path}</string><string>start</string><string>${mg_container_name}</string></array>
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

    # Ollama: only manage if user explicitly has it installed (optional)
    if command -v ollama &>/dev/null; then
      if launchctl list 2>/dev/null | grep -q "com.ollama"; then
        success "Ollama auto-start (managed by Ollama.app)"
      else
        info "Ollama: install via Ollama.app for auto-start, or manage manually"
      fi
    fi

  elif is_wsl; then
    # WSL: no systemd by default, no persistent cron. Use Windows Task Scheduler hints.
    info "WSL detected — background services work differently here"
    # Resolve the actual container name once (C4: was hardcoded as helios-memgraph)
    local mg_name
    mg_name=$(resolve_memgraph_container) || mg_name="memgraph"
    echo ""
    echo -e "  ${DIM}WSL doesn't auto-start background services like macOS/Linux.${RESET}"
    echo -e "  ${DIM}You'll need to start services manually each session:${RESET}"
    echo ""
    echo -e "    ${BOLD}# Start Memgraph (if using Docker Desktop):${RESET}"
    echo -e "    ${DIM}docker start ${mg_name} 2>/dev/null || true${RESET}"
    echo ""
    echo -e "  ${DIM}Tip: Add these to your ~/.bashrc to auto-start on WSL launch.${RESET}"
    echo ""
    
    # Offer to add auto-start to .bashrc
    local wsl_autostart_marker="# Helios WSL auto-start"
    if ! grep -q "$wsl_autostart_marker" "$HOME/.bashrc" 2>/dev/null; then
      ask "Add Helios service auto-start to ~/.bashrc? [y/N]:"
      read -t 120 -r add_autostart || add_autostart=""
      if [[ "$add_autostart" =~ ^[Yy]$ ]]; then
        # Unquoted heredoc: $mg_name expands at write time (correct — we embed
        # the resolved name so the .bashrc reflects the actual container name).
        cat >> "$HOME/.bashrc" << WSLSTART

# Helios WSL auto-start
# Start Docker containers on WSL session launch
# Start Memgraph if Docker is ready
if docker info &>/dev/null 2>&1; then
  (docker start ${mg_name} 2>/dev/null &)
else
  echo "[helios] Docker not ready — start Docker Desktop, then: docker start ${mg_name}"
fi
# Start Ollama only if user explicitly installed it (optional — not required)
if command -v ollama >/dev/null 2>&1 && ! pgrep -x ollama >/dev/null 2>&1; then
  (nohup ollama serve >> /tmp/ollama.log 2>&1 & disown) 2>/dev/null
fi
WSLSTART
        success "Added Helios auto-start to ~/.bashrc"
      fi
    fi

  elif [[ "$(uname -s)" == "Linux" ]]; then
    # Docker restart policy (already in compose, but ensure)
    local mg_boot_name
    mg_boot_name=$(resolve_memgraph_container 2>/dev/null) || mg_boot_name="memgraph"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "^${mg_boot_name}$"; then
      docker update --restart=unless-stopped "$mg_boot_name" >> "${LOG_FILE:-/dev/null}" 2>&1 \
        && success "Memgraph restart policy" || info "Memgraph restart policy (skipped)"
    fi

    # Ollama systemd (only if user explicitly installed Ollama)
    if command -v ollama &>/dev/null && command -v systemctl &>/dev/null; then
      systemctl --user enable ollama 2>/dev/null && success "Ollama systemd enabled" || info "Ollama systemd (skipped — no user session)"
    fi

    # Cron for skill-graph daily
    # Note: crontab -l returns exit code 1 when no crontab exists.
    # Under set -e, piping it directly causes the script to exit.
    # Fix: capture into a variable first with || true.
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)
    if ! echo "$existing_crontab" | grep -q "skill-graph"; then
      printf '%s\n%s\n' "$existing_crontab" "0 2 * * * ${HOME}/.pi/agent/scripts/ingest-session-decisions.sh >> ${HOME}/.pi/agent/.skill-graph-daily.log 2>&1" | crontab - 2>/dev/null \
        && success "Skill-graph daily cron" || info "Skill-graph daily cron (skipped)"
    else success "Skill-graph daily cron (exists)"; fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  print_banner
  echo -e "  ${BOLD}Starting Helios installation...${RESET}"
  echo -e "  ${DIM}This will install Helios CLI, Helios agent, and supporting tools.${RESET}"
  echo -e "  ${DIM}Estimated time: 3-5 minutes.${RESET}"
  echo ""
  detect_update_mode "$@"

  # Set TOTAL_STEPS accurately for this run (error-recovery.sh defaults to 0)
  # Full install: 15 run_step calls. Update mode: 7 run_step calls.
  if [[ "$UPDATE_MODE" == true ]]; then
    TOTAL_STEPS=7
    CURRENT_STEP=0
  else
    TOTAL_STEPS=14
    CURRENT_STEP=0
  fi

  if [[ "${FULL_UPDATE:-false}" == true ]]; then
    TOTAL_STEPS=10
  fi

  # ─── Hotfix: patch known wrapper bugs ──────────────────────────────────────
  # The wrapper at ~/.pi/agent/bin/helios ships via tarball and may have known
  # bugs. Patch them in-place so the wrapper works after this update completes.
  # This is idempotent — safe to run on already-fixed wrappers.
  local _wrapper="$PI_AGENT_DIR/bin/helios"
  if [[ -f "$_wrapper" ]]; then
    # Fix: 'local' outside function crashes bash 4.x (line ~84)
    if grep -q 'local depth="\${_HELIOS_UPDATE_DEPTH' "$_wrapper" 2>/dev/null; then
      sed -i.hotfix 's/local depth="${_HELIOS_UPDATE_DEPTH/depth="${_HELIOS_UPDATE_DEPTH/' "$_wrapper"
      rm -f "${_wrapper}.hotfix" 2>/dev/null
      info "Patched wrapper: removed 'local' outside function"
    fi
    # Fix: stale npm error messages
    if grep -q 'npm install -g @helios-agent/cli' "$_wrapper" 2>/dev/null; then
      sed -i.hotfix 's|npm install -g @helios-agent/cli|cd ~/helios-team-installer \&\& bash install.sh|g' "$_wrapper"
      rm -f "${_wrapper}.hotfix" 2>/dev/null
    fi
  fi

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

  run_step "Legacy Install Doctor" doctor_legacy_install

  if [[ "$UPDATE_MODE" == false ]]; then
    run_step "Prerequisites"     check_prerequisites
    run_step "Network Connectivity" check_network
    run_step "Helios CLI"  install_pi
    run_step "Helios Agent"          setup_helios_agent || { error "Helios Agent setup failed"; exit 1; }
    run_step "Helios CLI (wrapper)"  install_helios_cli
    # Interactive — must not go through run_step (captures stdout, breaks read prompts)
    select_provider
    # Normalize org paths in settings.json after provider selection (fresh install)
    _migrate_settings_packages
    _prune_stale_org_dirs
  fi

  # Ensure Pi is available before running packages (may have been uninstalled)
  if ! command -v helios &>/dev/null && ! command -v pi &>/dev/null; then
    warn "Helios CLI not found — installing..."
    install_pi
  fi

  if [[ "$UPDATE_MODE" == true ]]; then
    # Clear checkpoint so update steps are never skipped — a previous failed
    # install/update may have checkpointed past these steps without completing them.
    if type clear_checkpoint &>/dev/null; then
      clear_checkpoint
    fi
    # Quick network probe for update mode
    if ! curl -fsSL --connect-timeout 5 --max-time 10 https://registry.npmjs.org/ -o /dev/null 2>/dev/null; then
      OFFLINE_MODE=true
      warn "Network unreachable — using bundled deps only"
    fi
    # Lightweight prereq check for update mode
    if ! command -v node &>/dev/null; then
      error "Node.js not found — required for update. Install: https://nodejs.org"
      exit 1
    fi
    if ! command -v npm &>/dev/null; then
      error "npm not found — required for update. Install Node.js from https://nodejs.org"
      exit 1
    fi
    # Ensure bun is available (CLI binary requires it for package resolution)
    if ! command -v bun &>/dev/null; then
      info "Installing Bun (required by Helios CLI)..."
      if _timeout_cmd 60 bash -c 'curl -fsSL --max-time 30 https://bun.sh/install | BUN_INSTALL="$HOME/.bun" bash' >> "${LOG_FILE:-/dev/null}" 2>&1; then
        export PATH="$HOME/.bun/bin:$PATH"
        hash -r 2>/dev/null || true
        if command -v bun &>/dev/null; then
          success "Bun $(bun --version) installed"
        fi
      else
        warn "Bun installation failed — CLI binary may not work correctly"
        warn "Install manually: curl -fsSL https://bun.sh/install | bash"
      fi
    fi
    snapshot_state
    run_step "Helios CLI"             update_pi_cli
    run_step "Agent Directory"    update_agent_dir
  fi

  run_step "Agent Root Deps"       install_agent_deps
  run_step "Helios Packages"       install_packages
  run_step "Skill Dependencies" install_skill_deps
  run_step "Helios Browse"      setup_helios_browse
  run_step "Governance Deps"    install_governance_deps

  if [[ "$UPDATE_MODE" == true ]]; then
    if ! verify_update; then
      warn "Update verification had issues — continuing (non-fatal)"
    fi
  fi

  if [[ "${FULL_UPDATE:-false}" == true ]]; then
    run_step "Memgraph"          setup_memgraph
    run_step "SearXNG"           setup_searxng
    run_step "MCP Servers"       setup_mcp_servers
  fi

  if [[ "$UPDATE_MODE" == false ]]; then
    run_step "Dep Allowlist"     setup_dep_allowlist
    run_step "Memgraph"          setup_memgraph
    run_step "SearXNG"           setup_searxng
    run_step "MCP Servers"       setup_mcp_servers
    run_step "Optional Deps"     install_optional_deps
    setup_boot_services || warn "Boot services setup had non-fatal errors (install continues)"
    schedule_bootstrap    # Queue + launch codebase indexing in background

    # Interactive — bypasses run_step to avoid stdout capture
    setup_api_keys
    wire_env_to_shell

    setup_familiar        # Interactive: optional Familiar install

    # Walk user through Pi OAuth login
    setup_pi_auth
  fi

  # Non-interactive but light-weight — checkpoint not critical
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
