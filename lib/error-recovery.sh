#!/usr/bin/env bash
# =============================================================================
# lib/error-recovery.sh — Error Recovery Helper Library
# =============================================================================
# Sourced by install.sh (do NOT execute directly).
#
# Provides:
#   1. Step tracking     — step_start / step_done / step_fail
#   2. Retry backoff     — retry_with_backoff
#   3. Diagnostic dump   — generate_diagnostic_dump
#   4. Known-fix DB      — lookup_known_fix
#   5. Troubleshooter    — offer_troubleshoot
#   6. Checkpoint/resume — save_checkpoint / load_checkpoint / should_skip_step
#   7. Orchestrator      — run_step
#
# Assumes the following color variables are already set by install.sh:
#   RED, GREEN, YELLOW, CYAN, BOLD, DIM, RESET
# If this file is sourced before colors are defined, a safe no-op fallback is
# applied so the functions still work (just without color).
# =============================================================================

# ─── Color fallback (safe when sourced standalone / in tests) ─────────────────
RED="${RED:-}"
GREEN="${GREEN:-}"
YELLOW="${YELLOW:-}"
CYAN="${CYAN:-}"
BOLD="${BOLD:-}"
DIM="${DIM:-}"
RESET="${RESET:-}"

# =============================================================================
# 1. STEP TRACKING
# =============================================================================

# TOTAL_STEPS should be set by the calling script before run_step calls
TOTAL_STEPS=${TOTAL_STEPS:-0}
CURRENT_STEP=0

# step_start <step_name>
# Increments CURRENT_STEP and prints the step header (no newline — step_done
# will print the result on the same line via \r overwrite).
step_start() {
  local step_name="$1"
  CURRENT_STEP=$(( CURRENT_STEP + 1 ))
  # Store for step_fail to reference
  _CURRENT_STEP_NAME="$step_name"
  printf "  ${CYAN}▶ [%d/%d]${RESET} ${BOLD}%s${RESET} ..." \
    "$CURRENT_STEP" "$TOTAL_STEPS" "$step_name"
}

# step_done
# Prints ✓ on the same line (clears the trailing dots with spaces).
step_done() {
  printf " ${GREEN}✓${RESET}\n"
}

# step_fail <error_msg>
# Prints ✗ FAILED on the same line, then runs diagnostics / troubleshooter.
step_fail() {
  local error_msg="${1:-unknown error}"
  local exit_code="${2:-1}"
  printf " ${RED}✗ FAILED${RESET}\n"
  echo -e "  ${RED}Error:${RESET} ${error_msg}" >&2
  generate_diagnostic_dump "${_CURRENT_STEP_NAME:-unknown}" "$exit_code"
  offer_troubleshoot "$error_msg" "${_CURRENT_STEP_NAME:-unknown}"
}

# =============================================================================
# 2. RETRY WITH BACKOFF
# =============================================================================

# retry_with_backoff <max_retries> <description> <command...>
# Retries <command> up to <max_retries> times with increasing delays.
# Backoff schedule (seconds): 2, 5, 10, 20, 20, 20, ...
# Returns the exit code of the last attempt.
retry_with_backoff() {
  local max_retries="$1"
  local description="$2"
  shift 2
  # Backoff delays (indexed from 0 = first retry)
  local backoff_delays="2 5 10 20"
  local attempt=0
  local exit_code=0
  local delay=20
  local i=0

  while true; do
    "$@" ; exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      return 0
    fi

    attempt=$(( attempt + 1 ))
    if [ "$attempt" -ge "$max_retries" ]; then
      return "$exit_code"
    fi

    # Pick delay: use the nth value if available, else last value (20)
    delay=20
    i=0
    # Intentional unquoted: space-delimited string iterated as words (Bash 3.2 compat)
    # shellcheck disable=SC2086
    for d in $backoff_delays; do
      if [ "$i" -eq "$(( attempt - 1 ))" ]; then
        delay="$d"
        break
      fi
      i=$(( i + 1 ))
    done

    echo -e "  ${YELLOW}Retry ${attempt}/${max_retries} in ${delay}s...${RESET} (${description})"
    sleep "$delay"
  done
}

# =============================================================================
# 3. DIAGNOSTIC DUMP
# =============================================================================

INSTALL_LOG="${INSTALL_LOG:-$HOME/helios-install.log}"
DIAGNOSTIC_FILE="$HOME/helios-install-debug.txt"

# generate_diagnostic_dump <failed_step> <exit_code>
# Writes a comprehensive diagnostic snapshot to ~/helios-install-debug.txt.
generate_diagnostic_dump() {
  local failed_step="${1:-unknown}"
  local exit_code="${2:-1}"

  {
    echo "============================================================"
    echo "Helios Installer — Diagnostic Dump"
    echo "Timestamp : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "============================================================"
    echo ""

    # ── OS / Architecture ────────────────────────────────────────────
    echo "── System ──────────────────────────────────────────────────"
    if command -v sw_vers >/dev/null 2>&1; then
      echo "OS        : macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    elif [ -f /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release 2>/dev/null
      echo "OS        : ${PRETTY_NAME:-Linux}"
    else
      echo "OS        : $(uname -s) $(uname -r)"
    fi
    echo "Arch      : $(uname -m)"
    echo "Shell     : ${SHELL:-unknown} (bash ${BASH_VERSION:-?})"
    echo ""

    # ── Tool versions ─────────────────────────────────────────────────
    echo "── Tool Versions ────────────────────────────────────────────"
    for tool in node npm git brew docker python3 pnpm ollama; do
      if command -v "$tool" >/dev/null 2>&1; then
        local ver
        case "$tool" in
          node)    ver="$(node --version 2>/dev/null)" ;;
          npm)     ver="$(npm --version 2>/dev/null)" ;;
          git)     ver="$(git --version 2>/dev/null)" ;;
          brew)    ver="$(brew --version 2>/dev/null | head -1)" ;;
          docker)  ver="$(docker --version 2>/dev/null)" ;;
          python3) ver="$(python3 --version 2>/dev/null)" ;;
          pnpm)    ver="$(pnpm --version 2>/dev/null)" ;;
          ollama)  ver="$(ollama --version 2>/dev/null)" ;;
          *)       ver="present" ;;
        esac
        printf "  %-10s %s\n" "$tool" "${ver:-unknown}"
      else
        printf "  %-10s %s\n" "$tool" "NOT FOUND"
      fi
    done
    echo ""

    # ── PATH ──────────────────────────────────────────────────────────
    echo "── PATH ─────────────────────────────────────────────────────"
    echo "$PATH" | tr ':' '\n' | sed 's/^/  /'
    echo ""

    # ── Disk space ────────────────────────────────────────────────────
    echo "── Disk Space (HOME) ────────────────────────────────────────"
    df -h "$HOME" 2>/dev/null || df -h / 2>/dev/null || echo "  (df unavailable)"
    echo ""

    # ── Failure context ───────────────────────────────────────────────
    echo "── Failure Context ──────────────────────────────────────────"
    echo "Failed step : $failed_step"
    echo "Exit code   : $exit_code"
    echo ""

    # ── Last 30 lines of install log ──────────────────────────────────
    echo "── Last 30 Lines of Install Log ─────────────────────────────"
    if [ -f "$INSTALL_LOG" ]; then
      tail -30 "$INSTALL_LOG" 2>/dev/null || echo "  (could not read $INSTALL_LOG)"
    else
      echo "  (no log file found at $INSTALL_LOG)"
    fi
    echo ""

    # ── Network connectivity ──────────────────────────────────────────
    echo "── Network Connectivity ─────────────────────────────────────"
    if curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
      echo "  github.com : REACHABLE"
    else
      echo "  github.com : UNREACHABLE (check firewall / VPN / DNS)"
    fi
    echo ""

    # ── Docker status ─────────────────────────────────────────────────
    echo "── Docker / Container Runtime ───────────────────────────────"
    if command -v docker >/dev/null 2>&1; then
      if docker info >/dev/null 2>&1; then
        echo "  Docker daemon : RUNNING"
        docker version --format '  Client: {{.Client.Version}}  Server: {{.Server.Version}}' 2>/dev/null \
          || echo "  (docker version unavailable)"
      else
        echo "  Docker daemon : NOT RUNNING"
      fi
    else
      echo "  Docker        : NOT INSTALLED"
    fi
    echo ""

    # ── Memgraph container ────────────────────────────────────────────
    echo "── Memgraph Container ───────────────────────────────────────"
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      local mg_status
      mg_status="$(docker ps --filter name=memgraph --format '{{.Status}}' 2>/dev/null)"
      if [ -n "$mg_status" ]; then
        echo "  Memgraph : $mg_status"
      else
        local mg_all
        mg_all="$(docker ps -a --filter name=memgraph --format '{{.Status}}' 2>/dev/null)"
        if [ -n "$mg_all" ]; then
          echo "  Memgraph (stopped) : $mg_all"
        else
          echo "  Memgraph : no container found"
        fi
      fi
    else
      echo "  (Docker not available — cannot check Memgraph)"
    fi
    echo ""
    echo "============================================================"
    echo "End of Diagnostic Dump"
    echo "============================================================"
  } > "$DIAGNOSTIC_FILE" 2>&1

  echo -e "  ${DIM}Diagnostic info saved to ${DIAGNOSTIC_FILE}${RESET}"
}

# =============================================================================
# 4. KNOWN ERROR DATABASE
# =============================================================================
# Bash 3.2 does NOT support associative arrays (declare -A).
# We use two parallel indexed arrays: _KNOWN_FIX_PATTERNS and _KNOWN_FIX_CMDS.
# lookup_known_fix() iterates them in lock-step.
# =============================================================================

_KNOWN_FIX_PATTERNS=(
  "EACCES"
  "SSL certificate"
  "SSL_ERROR"
  "brew link"
  "already installed"
  "Cannot connect to the Docker daemon"
  "address already in use"
  "ENOMEM"
  "Cannot allocate"
  "ENOSPC"
  "No space left"
  "xcode-select"
  "xcrun"
  "permission denied"
)

_KNOWN_FIX_CMDS=(
  "sudo chown -R \$(whoami) ~/.npm && npm cache clean --force"
  "git config --global http.sslVerify false"
  "git config --global http.sslVerify false"
  "brew link --overwrite NODE_FORMULA"
  "brew link --overwrite NODE_FORMULA"
  "open -a OrbStack || open -a Docker"
  "lsof -ti:7687 | xargs kill -9"
  "Close other apps to free memory"
  "Close other apps to free memory"
  "Free up disk space (need 500MB+)"
  "Free up disk space (need 500MB+)"
  "xcode-select --install"
  "xcode-select --install"
  "Check file permissions or run with sudo"
)

# lookup_known_fix <error_output>
# Searches the parallel arrays for the first matching pattern.
# Prints the corresponding fix command and returns 0.
# Returns 1 (and prints nothing) if no match found.
lookup_known_fix() {
  local error_output="$1"
  local i=0
  local pattern_count="${#_KNOWN_FIX_PATTERNS[@]}"

  # Special case: port-conflict fix only when 7687 also appears
  # (the generic "address already in use" entry must be refined here)

  while [ "$i" -lt "$pattern_count" ]; do
    local pattern="${_KNOWN_FIX_PATTERNS[$i]}"
    local fix="${_KNOWN_FIX_CMDS[$i]}"

    # For the port-conflict pattern require 7687 to also be present
    if [ "$pattern" = "address already in use" ]; then
      if echo "$error_output" | grep -qi "$pattern" && \
         echo "$error_output" | grep -q "7687"; then
        echo "$fix"
        return 0
      fi
    else
      if echo "$error_output" | grep -qi "$pattern"; then
        echo "$fix"
        return 0
      fi
    fi

    i=$(( i + 1 ))
  done

  return 1
}

# =============================================================================
# 5. INTERACTIVE TROUBLESHOOTER
# =============================================================================

# offer_troubleshoot <error_output> <failed_step>
# Looks up a known fix and optionally applies it.
# Returns 0 if the fix was applied (caller should retry).
# Returns 1 if no fix / user declined / fix failed.
offer_troubleshoot() {
  local error_output="$1"
  local failed_step="${2:-unknown}"

  local fix
  fix="$(lookup_known_fix "$error_output")"

  if [ -n "$fix" ]; then
    echo -e "\n  ${YELLOW}Known fix available:${RESET}"
    echo -e "    ${BOLD}\$ ${fix}${RESET}"
    printf "  Try this fix? [Y/n]: "

    local answer
    if [ -t 0 ]; then
      read -r answer
    else
      # Non-interactive fallback (piped install): default to No
      answer="n"
      echo "n (non-interactive)"
    fi

    case "${answer:-Y}" in
      [Yy]* | "")
        echo -e "  ${CYAN}Applying fix...${RESET}"
        # SAFE: $fix is only from static _KNOWN_FIX_CMDS — no user input
        # shellcheck disable=SC2091
        if eval "$fix"; then
          echo -e "  ${GREEN}Fix applied successfully.${RESET}"
          return 0
        else
          echo -e "  ${RED}Fix failed — please apply manually.${RESET}" >&2
          return 1
        fi
        ;;
      *)
        return 1
        ;;
    esac
  else
    echo -e "  ${DIM}No automatic fix available.${RESET}"
    echo -e "  ${DIM}Diagnostic info saved to ${DIAGNOSTIC_FILE}${RESET}"
    echo -e "  ${CYAN}Get help: https://github.com/sweetcheeks72/helios-team-installer/issues${RESET}"
    return 1
  fi
}

# =============================================================================
# 6. CHECKPOINT / RESUME
# =============================================================================

CHECKPOINT_FILE="${CHECKPOINT_FILE:-$HOME/.pi/agent/.install-checkpoint}"

# save_checkpoint
# Persists CURRENT_STEP (and metadata) to the checkpoint file as JSON.
save_checkpoint() {
  mkdir -p "$(dirname "$CHECKPOINT_FILE")" 2>/dev/null || true
  cat > "$CHECKPOINT_FILE" << EOF
{"step":$CURRENT_STEP,"stepName":"${_CURRENT_STEP_NAME:-unknown}","installerVersion":"${INSTALLER_VERSION:-unknown}"}
EOF
}

# load_checkpoint
# Echoes the last completed step number, or 0 if none / version mismatch.
load_checkpoint() {
  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    echo 0
    return
  fi
  local content
  content="$(cat "$CHECKPOINT_FILE")"
  # Handle legacy bare-integer format
  if [[ "$content" =~ ^[0-9]+$ ]]; then
    echo "$content"
    return
  fi
  # Validate installer version matches
  local saved_version
  saved_version=$(echo "$content" | grep -o '"installerVersion":"[^"]*"' | cut -d'"' -f4)
  if [[ "$saved_version" != "${INSTALLER_VERSION:-unknown}" ]]; then
    echo 0  # Version mismatch — start fresh
    return
  fi
  echo "$content" | grep -o '"step":[0-9]*' | grep -o '[0-9]*'
}

# clear_checkpoint
# Removes the checkpoint file (used after a successful full install).
clear_checkpoint() {
  rm -f "$CHECKPOINT_FILE"
}

# should_skip_step <step_number>
# Returns 0 (true → skip) when:
#   - step_number <= checkpoint value AND
#   - --fresh flag was NOT passed (FRESH_INSTALL is unset or not "true")
# Returns 1 (false → do not skip) otherwise.
should_skip_step() {
  local step_number="$1"
  local checkpoint
  checkpoint="$(load_checkpoint)"

  if [ "${FRESH_INSTALL:-false}" = "true" ]; then
    return 1
  fi

  if [ "$step_number" -le "$checkpoint" ] 2>/dev/null; then
    return 0
  fi

  return 1
}

# =============================================================================
# 7. run_step — MAIN ORCHESTRATOR
# =============================================================================

# run_step <step_name> <command...>
# Full lifecycle: start → skip-check → execute → handle result.
run_step() {
  local step_name="$1"
  shift
  local cmd=("$@")

  step_start "$step_name"

  # ── Skip check ──────────────────────────────────────────────────────
  if should_skip_step "$CURRENT_STEP"; then
    printf " ${DIM}skipped (already done)${RESET}\n"
    return 0
  fi

  # ── Capture output to temp file ────────────────────────────────────
  local tmp_output
  tmp_output="$(mktemp /tmp/helios-step-XXXXXX 2>/dev/null || echo "/tmp/helios-step-$$")"

  # ── Run command ─────────────────────────────────────────────────────
  local exit_code=0
  export _INSIDE_RUN_STEP=true
  if "${cmd[@]}" >"$tmp_output" 2>&1; then
    _INSIDE_RUN_STEP=false
    step_done
    save_checkpoint
    rm -f "$tmp_output"
    return 0
  else
    exit_code=$?
    _INSIDE_RUN_STEP=false
    local captured_output
    captured_output="$(cat "$tmp_output" 2>/dev/null)"
    rm -f "$tmp_output"

    step_fail "$captured_output" "$exit_code"

    # ── Troubleshoot and optionally retry once ──────────────────────
    if offer_troubleshoot "$captured_output" "$step_name"; then
      # Fix was applied — retry the step once
      local retry_output
      retry_output="$(mktemp /tmp/helios-step-retry-XXXXXX 2>/dev/null || echo "/tmp/helios-step-retry-$$")"
      echo -e "  ${CYAN}Retrying step: ${step_name}...${RESET}"
      if "${cmd[@]}" >"$retry_output" 2>&1; then
        step_done
        save_checkpoint
        rm -f "$retry_output"
        return 0
      else
        exit_code=$?
        local retry_out
        retry_out="$(cat "$retry_output" 2>/dev/null)"
        rm -f "$retry_output"
        echo -e "  ${RED}Step still failed after fix attempt.${RESET}" >&2
        echo -e "  ${DIM}${retry_out}${RESET}" >&2
        return "$exit_code"
      fi
    else
      return "$exit_code"
    fi
  fi
}
