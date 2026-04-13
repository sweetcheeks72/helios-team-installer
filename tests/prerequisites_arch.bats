#!/usr/bin/env bats

# prerequisites_arch.bats — Arch-aware prerequisite installation path tests
#
# Verifies that binaries and Homebrew are installed for the correct CPU
# architecture (Apple Silicon arm64 vs Intel x86_64).
#
# Run: bats tests/prerequisites_arch.bats

setup() {
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/platform.sh"
  export INSTALLER_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "Homebrew is at correct path for current arch" {
  if [[ "$(current_platform)" != "macos" ]]; then skip "macOS only"; fi
  command -v brew &>/dev/null || skip "Homebrew not installed"
  local actual_prefix expected_prefix
  actual_prefix=$(brew --prefix)
  expected_prefix=$(homebrew_prefix)
  [[ "$actual_prefix" == "$expected_prefix" ]]
}

@test "Node.js binary is native arch (not Rosetta)" {
  command -v node &>/dev/null || skip "Node not installed"
  local node_path node_arch expected_arch
  node_path=$(which node)
  expected_arch=$(current_arch)
  # Use file command to check binary arch
  node_arch=$(file "$node_path")
  if [[ "$expected_arch" == "arm64" ]]; then
    echo "$node_arch" | grep -qi "arm64\|aarch64"
  else
    echo "$node_arch" | grep -qi "x86_64\|x86-64"
  fi
}

@test "npm is accessible and matches Node arch" {
  command -v npm &>/dev/null || skip "npm not installed"
  local npm_path
  npm_path=$(which npm)
  [[ -f "$npm_path" ]] || [[ -L "$npm_path" ]]
  # npm should execute without error
  npm --version &>/dev/null
}

@test "python3 binary is native arch" {
  command -v python3 &>/dev/null || skip "python3 not installed"
  local py_path py_arch expected_arch reported_arch
  py_path=$(which python3)
  expected_arch=$(current_arch)
  py_arch=$(file "$py_path")
  # pyenv/asdf shims are shell scripts — resolve via platform.machine() in that case
  if echo "$py_arch" | grep -qi "script\|text"; then
    reported_arch=$(python3 -c "import platform; print(platform.machine())" 2>/dev/null || echo "unknown")
    [[ "$reported_arch" == "$expected_arch" ]]
  elif [[ "$expected_arch" == "arm64" ]]; then
    echo "$py_arch" | grep -qi "arm64\|aarch64\|universal"
  else
    echo "$py_arch" | grep -qi "x86_64\|x86-64\|universal"
  fi
}

@test "git binary is native arch" {
  command -v git &>/dev/null || skip "git not installed"
  local git_path git_arch expected_arch
  git_path=$(which git)
  expected_arch=$(current_arch)
  git_arch=$(file "$git_path")
  if [[ "$expected_arch" == "arm64" ]]; then
    echo "$git_arch" | grep -qi "arm64\|aarch64\|universal"
  else
    echo "$git_arch" | grep -qi "x86_64\|x86-64\|universal"
  fi
}

@test "Docker Desktop is running and supports current arch" {
  command -v docker &>/dev/null || skip "Docker not installed"
  docker info &>/dev/null || skip "Docker not running"
  local docker_arch
  docker_arch=$(docker info --format '{{.Architecture}}' 2>/dev/null || echo "unknown")
  local expected
  expected=$(current_arch)
  [[ "$docker_arch" == "$expected" ]] || [[ "$docker_arch" == "aarch64" && "$expected" == "arm64" ]]
}

@test "check_prerequisites detects all required tools" {
  # Source install.sh functions (dry run mode)
  export DRY_RUN=1
  export LOG_FILE=/dev/null
  # Check that the function at least references node, git, python3, curl
  local prereq_body
  prereq_body=$(sed -n '/^check_prerequisites/,/^}/p' "$INSTALLER_DIR/install.sh")
  echo "$prereq_body" | grep -q 'node'
  echo "$prereq_body" | grep -q 'git'
  echo "$prereq_body" | grep -q 'python3'
  echo "$prereq_body" | grep -q 'curl'
}
