#!/usr/bin/env bash
# lib/preserve-files.sh — Files to preserve during helios-agent updates
# SINGLE SOURCE OF TRUTH — used by install.sh stash/restore loops
# Must also match auto-update.ts PRESERVE_FILES list in the agent repo

PRESERVE_FILES=(
  .env
  settings.json
  governance
  sessions
  .helios
  auth.json
  run-history.jsonl
  mcp.json
  dep-allowlist.json
  .secrets
  state
  models.json
  pi-messenger.json
  .update-state.json
  VERSION
)

# Stash preserve files from a directory to a backup location
# Usage: stash_preserve_files <source_dir> <backup_dir>
stash_preserve_files() {
  local src="$1" backup="$2"
  local item
  mkdir -p "$backup"
  for item in "${PRESERVE_FILES[@]}"; do
    if [[ -e "$src/$item" ]]; then
      cp -a "$src/$item" "$backup/$item"
    fi
  done
}

# Restore preserve files from backup to target directory
# Usage: restore_preserve_files <backup_dir> <target_dir>
restore_preserve_files() {
  local backup="$1" target="$2"
  local item
  for item in "${PRESERVE_FILES[@]}"; do
    if [[ -e "$backup/$item" ]]; then
      cp -a "$backup/$item" "$target/$item"
    fi
  done
}
