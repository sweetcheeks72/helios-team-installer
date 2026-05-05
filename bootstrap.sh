#!/usr/bin/env bash
# Helios — Single command install or update
# curl -fsSL https://github.com/helios-agi/helios-team-installer/releases/latest/download/bootstrap.sh | bash

{
set -euo pipefail

RELEASE_URL="https://github.com/helios-agi/helios-team-installer/releases/latest/download"
HELIOS_PKG="$HOME/.helios-package"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
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

command -v curl &>/dev/null || { echo -e "${RED}✗${RESET} curl required"; exit 1; }

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in aarch64|arm64) ARCH="arm64" ;; x86_64) ARCH="x64" ;; esac

TARBALL="helios-latest-${OS}-${ARCH}.tar.gz"

echo -e "  ${DIM}Downloading (${OS}-${ARCH})...${RESET}"
tmp="$(mktemp)"
if ! curl -fSL --retry 3 --max-time 600 --progress-bar -o "$tmp" "$RELEASE_URL/$TARBALL"; then
  echo -e "${RED}✗${RESET} Download failed: $RELEASE_URL/$TARBALL"
  rm -f "$tmp"
  exit 1
fi

echo -e "  ${DIM}Extracting...${RESET}"
rm -rf "$HELIOS_PKG"
mkdir -p "$HELIOS_PKG"
tar -xzf "$tmp" -C "$HELIOS_PKG" --strip-components=1
rm -f "$tmp"

echo -e "  ${GREEN}✓${RESET} Package ready"
echo ""

exec bash "$HELIOS_PKG/installer/install.sh" --local-package "$HELIOS_PKG" "$@"
}
