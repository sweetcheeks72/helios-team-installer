#!/usr/bin/env bash
# lib/platform.sh — Shared platform detection for helios installer
# Sourced by both bootstrap.sh and install.sh

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

# Install a system dependency using the appropriate package manager
# Usage: _install_dep <command> <brew_pkg> <apt_pkg>
_install_dep() {
  local cmd="$1" brew_pkg="${2:-$1}" apt_pkg="${3:-$1}"
  local platform
  platform="$(current_platform)"
  
  case "$platform" in
    macos)
      if command -v brew &>/dev/null; then
        brew install "$brew_pkg" >> "${LOG_FILE:-/dev/null}" 2>&1
      else
        echo "  Homebrew not available — install $cmd manually" >&2
        return 1
      fi
      ;;
    linux|wsl)
      if command -v apt-get &>/dev/null; then
        sudo apt-get install -y "$apt_pkg" >> "${LOG_FILE:-/dev/null}" 2>&1
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y "$apt_pkg" >> "${LOG_FILE:-/dev/null}" 2>&1
      elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm "$apt_pkg" >> "${LOG_FILE:-/dev/null}" 2>&1
      elif command -v zypper &>/dev/null; then
        sudo zypper install -y "$apt_pkg" >> "${LOG_FILE:-/dev/null}" 2>&1
      else
        echo "  No supported package manager found — install $cmd manually" >&2
        return 1
      fi
      ;;
    *)
      echo "  Unsupported platform ($platform) — install $cmd manually" >&2
      return 1
      ;;
  esac
}

# Install Node.js using the appropriate method for the current platform
_install_nodejs() {
  local platform
  platform="$(current_platform)"
  
  case "$platform" in
    macos)
      brew install node >> "${LOG_FILE:-/dev/null}" 2>&1
      ;;
    linux|wsl)
      if command -v apt-get &>/dev/null && command -v curl &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | sudo bash - >> "${LOG_FILE:-/dev/null}" 2>&1
        sudo apt-get install -y nodejs >> "${LOG_FILE:-/dev/null}" 2>&1
      elif command -v dnf &>/dev/null; then
        sudo dnf module enable nodejs:22 -y 2>/dev/null || true
        sudo dnf install -y nodejs npm >> "${LOG_FILE:-/dev/null}" 2>&1
      elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm nodejs npm >> "${LOG_FILE:-/dev/null}" 2>&1
      else
        echo "  No supported package manager for Node.js — install manually: https://nodejs.org" >&2
        return 1
      fi
      ;;
    *)
      echo "  Unsupported platform — install Node.js manually: https://nodejs.org" >&2
      return 1
      ;;
  esac
}
