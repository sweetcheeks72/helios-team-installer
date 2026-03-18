#!/usr/bin/env bash
# =============================================================================
# Helios + Pi Uninstaller
# =============================================================================
# Safely removes the Helios + Pi setup with confirmation prompts.
# Does NOT remove API keys from shell profiles.
# =============================================================================

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}  ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*"; }
ask()     { echo -en "${YELLOW}  ? ${RESET}$* "; }

PI_AGENT_DIR="$HOME/.pi/agent"
FAMILIAR_DIR="$HOME/.familiar"
PI_DIR="$HOME/.pi"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${RED}  ╔═══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${RED}  ║    Helios + Pi Uninstaller                ║${RESET}"
echo -e "${BOLD}${RED}  ╚═══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${YELLOW}This will remove the Helios + Pi setup.${RESET}"
echo -e "  ${DIM}Your API keys in shell profiles will NOT be removed.${RESET}"
echo ""

# ─── Master Confirmation ──────────────────────────────────────────────────────
ask "Are you sure you want to uninstall? [y/N]:"
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo ""
  info "Uninstall cancelled"
  exit 0
fi

echo ""

# ─── 1. Remove ~/.pi/agent/ ───────────────────────────────────────────────────
if [[ -d "$PI_AGENT_DIR" || -L "$PI_AGENT_DIR" ]]; then
  echo -e "  ${BOLD}~/.pi/agent/${RESET}"
  if [[ -L "$PI_AGENT_DIR" ]]; then
    info "~/.pi/agent/ is a symlink → $(readlink "$PI_AGENT_DIR")"
  fi

  ask "Remove ~/.pi/agent/ (Helios agent, configs, skills)? [y/N]:"
  read -r remove_agent
  if [[ "$remove_agent" =~ ^[Yy]$ ]]; then
    # Backup .env first
    if [[ -f "$PI_AGENT_DIR/.env" ]]; then
      env_backup="$HOME/.pi-agent-env.backup.$(date +%Y%m%d_%H%M%S)"
      cp "$PI_AGENT_DIR/.env" "$env_backup"
      success "API keys backed up to: $env_backup"
    fi
    rm -rf "$PI_AGENT_DIR"
    success "~/.pi/agent/ removed"
  else
    info "Keeping ~/.pi/agent/"
  fi
fi

# ─── 2. Remove ~/.pi/ (packages cache etc.) ───────────────────────────────────
if [[ -d "$PI_DIR" ]]; then
  ask "Remove entire ~/.pi/ directory (packages cache)? [y/N]:"
  read -r remove_pi_dir
  if [[ "$remove_pi_dir" =~ ^[Yy]$ ]]; then
    rm -rf "$PI_DIR"
    success "~/.pi/ removed"
  else
    info "Keeping ~/.pi/"
  fi
fi

# ─── 3. Remove Pi CLI ─────────────────────────────────────────────────────────
if command -v pi &>/dev/null; then
  ask "Remove Pi CLI (npm uninstall -g @helios-agent/cli)? [y/N]:"
  read -r remove_pi_cli
  if [[ "$remove_pi_cli" =~ ^[Yy]$ ]]; then
    if npm uninstall -g @helios-agent/cli 2>/dev/null; then
      success "Pi CLI removed"
    else
      warn "Could not remove Pi CLI automatically — run: npm uninstall -g @helios-agent/cli"
    fi
  else
    info "Keeping Pi CLI"
  fi
fi

# ─── Remove Helios CLI symlinks ──────────────────────────────────────────────
for helios_path in /usr/local/bin/helios "$HOME/.local/bin/helios"; do
  if [[ -L "$helios_path" ]] || [[ -f "$helios_path" ]]; then
    rm -f "$helios_path" 2>/dev/null || sudo rm -f "$helios_path" 2>/dev/null || true
    success "Removed $helios_path"
  fi
done

# ─── 4. Remove Familiar Skills ────────────────────────────────────────────────
if [[ -d "$FAMILIAR_DIR" ]]; then
  ask "Remove ~/.familiar/ (Familiar skills)? [y/N]:"
  read -r remove_familiar
  if [[ "$remove_familiar" =~ ^[Yy]$ ]]; then
    rm -rf "$FAMILIAR_DIR"
    success "~/.familiar/ removed"
  else
    info "Keeping ~/.familiar/"
  fi
fi

# ─── 5. Docker / Memgraph Cleanup ────────────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "  Stopping Memgraph container..."
  docker stop memgraph 2>/dev/null || true
  docker rm memgraph 2>/dev/null || true
  echo "  Removed Memgraph container"
fi

# ─── 6. LaunchAgent Cleanup ───────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo ""
  echo -e "  ${BOLD}LaunchAgents${RESET}"
  for plist in com.helios.memgraph com.helios.skill-graph-daily com.helios.consolidation com.helios.improvement-lab; do
    local pfile="$HOME/Library/LaunchAgents/${plist}.plist"
    if [[ -f "$pfile" ]]; then
      launchctl bootout "gui/$(id -u)" "$pfile" 2>/dev/null || launchctl unload "$pfile" 2>/dev/null
      rm -f "$pfile"
      success "Removed $plist"
    fi
  done
fi

# ─── 7. Shell Profile Note ────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Note on API Keys:${RESET}"
echo -e "  ${DIM}API keys set in shell profiles (e.g., ~/.zshrc, ~/.bashrc) were NOT removed.${RESET}"
echo -e "  ${DIM}To remove them manually, search for ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.${RESET}"
if ls "$HOME"/.pi-agent-env.backup.* &>/dev/null; then
  echo -e "  ${DIM}Your .env was backed up — find it with: ls ~/.pi-agent-env.backup.*${RESET}"
fi

# Offer to remove the source line from shell profile
for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
  if grep -qF ".pi/agent/.env" "$profile" 2>/dev/null; then
    ask "Remove Helios .env source line from $profile? [y/N]:"
    read -r remove_source
    if [[ "$remove_source" =~ ^[Yy]$ ]]; then
      sed -i.bak '/.pi\/agent\/\.env/d' "$profile"
      sed -i.bak '/# Helios\/Pi API keys/d' "$profile"
      rm -f "${profile}.bak"
      success "Removed .env source from $profile"
    fi
  fi
done

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}${BOLD}✓ Uninstall complete${RESET}"
echo ""
echo -e "  ${DIM}To reinstall: bash ~/helios-team-installer/install.sh${RESET}"
echo ""
