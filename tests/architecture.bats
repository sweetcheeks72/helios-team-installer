#!/usr/bin/env bats
# architecture.bats — Architecture detection tests

setup() {
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/platform.sh"
}

@test "current_arch returns arm64 or x86_64" {
  local arch
  arch=$(current_arch)
  [[ "$arch" == "arm64" ]] || [[ "$arch" == "x86_64" ]]
}

@test "current_arch matches uname -m on macOS" {
  if [[ "$(uname -s)" != "Darwin" ]]; then skip; fi
  local arch expected
  arch=$(current_arch)
  expected=$(uname -m)
  [[ "$arch" == "$expected" ]]
}

@test "is_apple_silicon returns 0 on arm64 Mac" {
  if [[ "$(uname -m)" != "arm64" ]]; then skip; fi
  is_apple_silicon
}

@test "is_apple_silicon returns 1 on x86_64" {
  if [[ "$(uname -m)" != "x86_64" ]]; then skip; fi
  ! is_apple_silicon
}

@test "homebrew_prefix returns /opt/homebrew on arm64" {
  if [[ "$(uname -m)" != "arm64" ]]; then skip; fi
  local prefix
  prefix=$(homebrew_prefix)
  [[ "$prefix" == "/opt/homebrew" ]]
}

@test "homebrew_prefix returns /usr/local on x86_64" {
  if [[ "$(uname -m)" != "x86_64" ]]; then skip; fi
  local prefix
  prefix=$(homebrew_prefix)
  [[ "$prefix" == "/usr/local" ]]
}

@test "docker_platform returns linux/arm64 on Apple Silicon" {
  if [[ "$(uname -m)" != "arm64" ]]; then skip; fi
  local plat
  plat=$(docker_platform)
  [[ "$plat" == "linux/arm64" ]]
}

@test "docker_platform returns linux/amd64 on Intel" {
  if [[ "$(uname -m)" != "x86_64" ]]; then skip; fi
  local plat
  plat=$(docker_platform)
  [[ "$plat" == "linux/amd64" ]]
}
