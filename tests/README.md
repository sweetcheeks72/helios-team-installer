# Helios Installer Tests

## Quick Start
```bash
# Run all tests locally
./tests/run-all.sh

# Run specific suite
bats tests/unit_tests.bats
bats tests/architecture.bats
bats tests/prerequisites_arch.bats
bats tests/memgraph_arch.bats
bats tests/installer_integration.bats
bats tests/edge_cases.bats
```

## Test Suites

| Suite | What it tests | Live resources? |
|-------|---------------|----------------|
| `unit_tests.bats` | Static analysis of install.sh | No |
| `architecture.bats` | arm64/x86_64 detection | No |
| `prerequisites_arch.bats` | Binary arch verification | Yes (checks installed binaries) |
| `memgraph_arch.bats` | Memgraph container arch | Yes (Docker + Memgraph) |
| `installer_integration.bats` | Full integration | Yes (Docker, Memgraph, bolt) |
| `edge_cases.bats` | Path handling, error recovery | No |

## CI
GitHub Actions runs on:
- `macos-14` (Apple Silicon / arm64)
- `macos-13` (Intel / x86_64)
- `ubuntu-latest` (Docker E2E + multi-arch)

See `.github/workflows/installer-test.yml`.

## Architecture Matrix
| Component | Apple Silicon (arm64) | Intel (x86_64) |
|-----------|---------------------|----------------|
| Homebrew | `/opt/homebrew` | `/usr/local` |
| Docker platform | `linux/arm64` | `linux/amd64` |
| Memgraph image | `memgraph/memgraph-mage` (arm64) | `memgraph/memgraph-mage` (amd64) |
| Node.js | arm64 binary | x64 binary |
