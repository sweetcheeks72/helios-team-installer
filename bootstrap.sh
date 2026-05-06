#!/usr/bin/env bash
# Helios — Single command install or update
# curl -fsSL https://github.com/helios-agi/helios-team-installer/releases/latest/download/bootstrap.sh | bash

{
set -euo pipefail

RELEASE_URL="https://github.com/helios-agi/helios-team-installer/releases/latest/download"
HELIOS_PKG="$HOME/.helios-package"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

trap 'echo ""; echo -e "${RED}✗ Failed at line $LINENO.${RESET} Re-run to retry."' ERR

if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec < /dev/tty 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${CYAN}  Helios${RESET}"
echo ""

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Requires WSL. Run: wsl --install"; exit 1 ;;
esac

command -v curl &>/dev/null || { echo -e "${RED}✗${RESET} curl required. Install: apt install curl / brew install curl"; exit 1; }

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in aarch64|arm64) ARCH="arm64" ;; x86_64) ARCH="x64" ;; esac
PLATFORM="${OS}-${ARCH}"

# Check disk space (need ~500MB for download + extraction)
if command -v df &>/dev/null; then
  free_mb=$(df -Pm "$HOME" 2>/dev/null | awk 'NR>1 {print $4; exit}')
  if [[ -n "$free_mb" ]] && [[ "$free_mb" -lt 500 ]]; then
    echo -e "${RED}✗${RESET} Insufficient disk space (${free_mb}MB free, need 500MB)"
    exit 1
  fi
fi

TARBALL="helios-latest-${PLATFORM}.tar.gz"

echo -e "  ${DIM}Downloading helios for ${PLATFORM}...${RESET}"
tmp="$HOME/.helios-download.tar.gz"
rm -f "$tmp"

if ! curl -fSL --retry 3 --max-time 600 --progress-bar -o "$tmp" "$RELEASE_URL/$TARBALL" 2>/dev/null; then
  echo -e "${YELLOW}⚠${RESET}  Platform-specific package not found: ${PLATFORM}"
  echo -e "  ${DIM}Trying universal package...${RESET}"
  TARBALL="helios-latest.tar.gz"
  if ! curl -fSL --retry 3 --max-time 600 --progress-bar -o "$tmp" "$RELEASE_URL/$TARBALL" 2>/dev/null; then
    echo -e "${RED}✗${RESET} Download failed. Check network and retry."
    echo -e "  ${DIM}URL: $RELEASE_URL/$TARBALL${RESET}"
    rm -f "$tmp"
    exit 1
  fi
fi

# Validate download isn't empty or an error page
file_size=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
if [[ "$file_size" -lt 1048576 ]]; then
  echo -e "${RED}✗${RESET} Downloaded file too small (${file_size} bytes) — likely an error"
  rm -f "$tmp"
  exit 1
fi

echo -e "  ${DIM}Extracting...${RESET}"
rm -rf "$HELIOS_PKG"
mkdir -p "$HELIOS_PKG"
if ! tar -xzf "$tmp" -C "$HELIOS_PKG" --strip-components=1 2>/dev/null; then
  echo -e "${RED}✗${RESET} Extraction failed — file may be corrupt. Delete and retry:"
  echo -e "  ${DIM}rm -f $tmp && re-run this command${RESET}"
  rm -f "$tmp"
  exit 1
fi
rm -f "$tmp"

# Verify extraction produced expected structure
if [[ ! -f "$HELIOS_PKG/installer/install.sh" ]]; then
  echo -e "${RED}✗${RESET} Package structure invalid — installer/install.sh not found"
  rm -rf "$HELIOS_PKG"
  exit 1
fi

echo -e "  ${GREEN}✓${RESET} Package ready"
echo ""

exec bash "$HELIOS_PKG/installer/install.sh" --local-package "$HELIOS_PKG" "$@"
}
