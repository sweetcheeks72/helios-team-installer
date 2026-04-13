#!/usr/bin/env bats

setup() {
  export INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$INSTALLER_DIR/lib/platform.sh"
}

# ── Path handling edge cases ──────────────────────────────────────────────────

@test "installer handles spaces in HOME path" {
  # The installer should quote all path variables
  local unquoted_paths
  unquoted_paths=$(grep -n '\$HOME/' "$INSTALLER_DIR/install.sh" | grep -v '"\$HOME' | grep -v '#' | head -5)
  [[ -z "$unquoted_paths" ]] || {
    echo "Unquoted \$HOME paths found:"
    echo "$unquoted_paths"
    false
  }
}

@test "installer handles spaces in PI_AGENT_DIR path" {
  local unquoted
  unquoted=$(grep -n '\$PI_AGENT_DIR/' "$INSTALLER_DIR/install.sh" | grep -v '"\$PI_AGENT_DIR' | grep -v "'\$PI_AGENT_DIR" | grep -v '#' | grep -v '".*\$PI_AGENT_DIR' | head -5)
  [[ -z "$unquoted" ]] || {
    echo "Unquoted \$PI_AGENT_DIR paths found:"
    echo "$unquoted"
    false
  }
}

@test "no hardcoded /Users/ paths in installer" {
  local hardcoded
  hardcoded=$(grep -n '/Users/' "$INSTALLER_DIR/install.sh" | grep -v '#' | head -5)
  [[ -z "$hardcoded" ]] || {
    echo "Hardcoded /Users/ paths found:"
    echo "$hardcoded"
    false
  }
}

@test "no hardcoded /home/ paths in installer" {
  local hardcoded
  hardcoded=$(grep -n '/home/' "$INSTALLER_DIR/install.sh" | grep -v '#' | grep -v 'Dockerfile\|docker' | head -5)
  [[ -z "$hardcoded" ]] || {
    echo "Hardcoded /home/ paths found:"
    echo "$hardcoded"
    false
  }
}

# ── Error recovery edge cases ─────────────────────────────────────────────────

@test "cleanup function exists and is trap-registered" {
  grep -q '^cleanup()' "$INSTALLER_DIR/install.sh"
  grep -q 'trap.*cleanup' "$INSTALLER_DIR/install.sh"
}

@test "retry_with_backoff function has max retry limit" {
  local body
  body=$(sed -n '/^retry_with_backoff/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$body" | grep -qE 'max_retries|MAX_RETRIES|retry.*limit|3|5'
}

@test "all curl calls have --fail or -f flag" {
  local unsafe_curls
  unsafe_curls=$(grep -n 'curl ' "$INSTALLER_DIR/install.sh" | grep -v 'command -v curl\|_install_dep curl\|warn.*curl\|info.*curl\|echo.*curl\|#' | grep -v '\-f\|--fail' | head -5)
  [[ -z "$unsafe_curls" ]] || {
    echo "Curl calls without --fail:"
    echo "$unsafe_curls"
    false
  }
}

@test "all mkdir calls use -p flag" {
  local unsafe_mkdirs
  unsafe_mkdirs=$(grep -n 'mkdir ' "$INSTALLER_DIR/install.sh" | grep -v '\-p\|#' | head -5)
  [[ -z "$unsafe_mkdirs" ]] || {
    echo "mkdir calls without -p:"
    echo "$unsafe_mkdirs"
    false
  }
}

# ── Idempotency edge cases ────────────────────────────────────────────────────

@test "install.sh can be sourced without side effects" {
  # The installer should have a guard against running when sourced
  # (or at minimum, sourcing should not start the install)
  grep -qE 'BASH_SOURCE|main.*\$@|__name__' "$INSTALLER_DIR/install.sh" || {
    echo "No source guard found — sourcing will trigger install"
    false
  }
}

@test "all provider configs have identical extension lists" {
  local ref_exts
  ref_exts=$(python3 -c "import json; d=json.load(open('$INSTALLER_DIR/provider-configs/anthropic.json')); print(sorted(d.get('extensions',[])))") 
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    local these_exts
    these_exts=$(python3 -c "import json; d=json.load(open('$cfg')); print(sorted(d.get('extensions',[])))") 
    [[ "$ref_exts" == "$these_exts" ]] || {
      echo "Extension mismatch in $(basename $cfg)"
      echo "Expected: $ref_exts"
      echo "Got: $these_exts"
      false
    }
  done
}

@test "all provider configs have identical skill lists" {
  local ref_skills
  ref_skills=$(python3 -c "import json; d=json.load(open('$INSTALLER_DIR/provider-configs/anthropic.json')); print(sorted([s if isinstance(s,str) else s.get('name','') for s in d.get('skills',[])]))") 
  for cfg in "$INSTALLER_DIR"/provider-configs/*.json; do
    local these_skills
    these_skills=$(python3 -c "import json; d=json.load(open('$cfg')); print(sorted([s if isinstance(s,str) else s.get('name','') for s in d.get('skills',[])]))") 
    [[ "$ref_skills" == "$these_skills" ]] || {
      echo "Skill mismatch in $(basename $cfg)"
      false
    }
  done
}
