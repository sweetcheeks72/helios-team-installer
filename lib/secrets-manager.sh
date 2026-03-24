#!/usr/bin/env bash
# =============================================================================
# Helios Secrets Manager
# =============================================================================
# Secure storage for API keys and credentials.
# Uses macOS Keychain (security) when available, falls back to encrypted file.
#
# Usage:
#   source lib/secrets-manager.sh
#   secrets_store "ANTHROPIC_API_KEY" "sk-ant-..."
#   secrets_retrieve "ANTHROPIC_API_KEY"
#   secrets_delete "ANTHROPIC_API_KEY"
#   secrets_list
# =============================================================================

SECRETS_SERVICE="com.familiar.helios"

# ─── Detect available backend ─────────────────────────────────────────────────
_secrets_backend() {
  if [[ "$(uname -s)" == "Darwin" ]] && command -v security &>/dev/null; then
    echo "keychain"
  elif command -v secret-tool &>/dev/null; then
    echo "secret-tool"
  else
    echo "file"
  fi
}

# ─── Store a secret ──────────────────────────────────────────────────────────
# secrets_store <key> <value>
secrets_store() {
  local key="$1" value="$2"
  if [[ -z "$key" ]] || [[ -z "$value" ]]; then
    echo "Usage: secrets_store <key> <value>" >&2
    return 1
  fi

  local backend
  backend="$(_secrets_backend)"

  case "$backend" in
    keychain)
      # Delete existing entry first (security errors on duplicate)
      security delete-generic-password -s "$SECRETS_SERVICE" -a "$key" 2>/dev/null || true
      security add-generic-password -s "$SECRETS_SERVICE" -a "$key" -w "$value" -U 2>/dev/null
      ;;
    secret-tool)
      echo -n "$value" | secret-tool store --label="Helios: $key" service "$SECRETS_SERVICE" key "$key" 2>/dev/null
      ;;
    file)
      _secrets_file_store "$key" "$value"
      ;;
  esac
}

# ─── Retrieve a secret ───────────────────────────────────────────────────────
# secrets_retrieve <key>
# Prints the value to stdout. Returns 1 if not found.
secrets_retrieve() {
  local key="$1"
  if [[ -z "$key" ]]; then
    echo "Usage: secrets_retrieve <key>" >&2
    return 1
  fi

  local backend
  backend="$(_secrets_backend)"

  case "$backend" in
    keychain)
      security find-generic-password -s "$SECRETS_SERVICE" -a "$key" -w 2>/dev/null
      ;;
    secret-tool)
      secret-tool lookup service "$SECRETS_SERVICE" key "$key" 2>/dev/null
      ;;
    file)
      _secrets_file_retrieve "$key"
      ;;
  esac
}

# ─── Delete a secret ─────────────────────────────────────────────────────────
# secrets_delete <key>
secrets_delete() {
  local key="$1"
  if [[ -z "$key" ]]; then
    echo "Usage: secrets_delete <key>" >&2
    return 1
  fi

  local backend
  backend="$(_secrets_backend)"

  case "$backend" in
    keychain)
      security delete-generic-password -s "$SECRETS_SERVICE" -a "$key" 2>/dev/null
      ;;
    secret-tool)
      secret-tool clear service "$SECRETS_SERVICE" key "$key" 2>/dev/null
      ;;
    file)
      _secrets_file_delete "$key"
      ;;
  esac
}

# ─── List stored keys ────────────────────────────────────────────────────────
secrets_list() {
  local backend
  backend="$(_secrets_backend)"

  case "$backend" in
    keychain)
      security dump-keychain 2>/dev/null | grep -A4 "\"svce\"<blob>=\"$SECRETS_SERVICE\"" | grep '"acct"' | sed 's/.*="//;s/"//'
      ;;
    secret-tool)
      secret-tool search --all service "$SECRETS_SERVICE" 2>/dev/null | grep "^attribute.key" | awk '{print $3}'
      ;;
    file)
      _secrets_file_list
      ;;
  esac
}

# ─── Migrate plaintext .secrets to secure storage ─────────────────────────────
# secrets_migrate <secrets_file>
secrets_migrate() {
  local secrets_file="${1:-$HOME/.pi/agent/.secrets}"
  if [[ ! -f "$secrets_file" ]]; then
    return 0
  fi

  local migrated=0
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ -z "$key" ]] || [[ "$key" =~ ^# ]] && continue
    # Strip leading/trailing whitespace
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | xargs)"
    if [[ -n "$key" ]] && [[ -n "$value" ]]; then
      secrets_store "$key" "$value"
      (( migrated++ ))
    fi
  done < "$secrets_file"

  if (( migrated > 0 )); then
    # Rename the plaintext file so it's no longer used
    mv "$secrets_file" "${secrets_file}.migrated.$(date +%s)"
    echo "Migrated $migrated secret(s) to $(_secrets_backend) backend"
  fi
}

# ─── File-based fallback (encrypted with machine-specific key) ────────────────

_secrets_file_path() {
  echo "$HOME/.pi/agent/.secrets.enc"
}

_secrets_machine_key() {
  # Derive a machine-specific key from hostname + user + kernel
  local raw
  raw="$(hostname 2>/dev/null)$(whoami)$(uname -r 2>/dev/null)"
  if command -v shasum &>/dev/null; then
    echo "$raw" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum &>/dev/null; then
    echo "$raw" | sha256sum | awk '{print $1}'
  else
    # Last resort: use raw string (not secure, but functional)
    echo "$raw"
  fi
}

_secrets_file_store() {
  local key="$1" value="$2"
  local file
  file="$(_secrets_file_path)"
  local tmpfile="${file}.tmp"
  local machine_key
  machine_key="$(_secrets_machine_key)"

  # Read existing entries (skip the one we're updating)
  local entries=""
  if [[ -f "$file" ]] && command -v openssl &>/dev/null; then
    entries="$(openssl enc -aes-256-cbc -d -a -pass "pass:${machine_key}" -pbkdf2 -in "$file" 2>/dev/null || true)"
  fi

  # Filter out existing entry for this key, add new one
  {
    echo "$entries" | grep -v "^${key}=" 2>/dev/null || true
    echo "${key}=${value}"
  } | grep -v '^$' | openssl enc -aes-256-cbc -a -salt -pass "pass:${machine_key}" -pbkdf2 -out "$tmpfile" 2>/dev/null

  mv "$tmpfile" "$file"
  chmod 600 "$file"
}

_secrets_file_retrieve() {
  local key="$1"
  local file
  file="$(_secrets_file_path)"
  local machine_key
  machine_key="$(_secrets_machine_key)"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  local entries
  entries="$(openssl enc -aes-256-cbc -d -a -pass "pass:${machine_key}" -pbkdf2 -in "$file" 2>/dev/null)" || return 1
  echo "$entries" | grep "^${key}=" | head -1 | cut -d'=' -f2-
}

_secrets_file_delete() {
  local key="$1"
  local file
  file="$(_secrets_file_path)"
  local machine_key
  machine_key="$(_secrets_machine_key)"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local entries
  entries="$(openssl enc -aes-256-cbc -d -a -pass "pass:${machine_key}" -pbkdf2 -in "$file" 2>/dev/null)" || return 1

  local filtered
  filtered="$(echo "$entries" | grep -v "^${key}=" || true)"

  if [[ -n "$filtered" ]]; then
    echo "$filtered" | openssl enc -aes-256-cbc -a -salt -pass "pass:${machine_key}" -pbkdf2 -out "$file" 2>/dev/null
  else
    rm -f "$file"
  fi
}

_secrets_file_list() {
  local file
  file="$(_secrets_file_path)"
  local machine_key
  machine_key="$(_secrets_machine_key)"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local entries
  entries="$(openssl enc -aes-256-cbc -d -a -pass "pass:${machine_key}" -pbkdf2 -in "$file" 2>/dev/null)" || return 1
  echo "$entries" | cut -d'=' -f1 | grep -v '^$'
}
