#!/usr/bin/env bash
# =============================================================================
# build-release.sh — Package helios-agent into a distributable tarball
# =============================================================================
#
# Usage:
#   ./build-release.sh [VERSION]
#
# Examples:
#   ./build-release.sh 1.2.0        # explicit version
#   ./build-release.sh              # reads version from ~/helios-package/package.json
#
# Output (in ~/helios-team-installer/dist/):
#   helios-agent-v{VERSION}.tar.gz
#   helios-agent-v{VERSION}.tar.gz.sha256
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${HOME}/.pi/agent"
PACKAGE_JSON="${HOME}/helios-package/package.json"
DIST_DIR="${SCRIPT_DIR}/dist"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------

if [[ $# -ge 1 && -n "$1" ]]; then
  VERSION="$1"
  echo "📌 Using provided version: ${VERSION}"
else
  # Read version from package.json
  if [[ ! -f "${PACKAGE_JSON}" ]]; then
    echo "❌ No version argument provided and ${PACKAGE_JSON} not found."
    echo "   Usage: ./build-release.sh <VERSION>"
    exit 1
  fi
  # Extract version field — works without jq
  VERSION="$(grep '"version"' "${PACKAGE_JSON}" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  if [[ -z "${VERSION}" ]]; then
    echo "❌ Could not parse version from ${PACKAGE_JSON}"
    exit 1
  fi
  echo "📌 Read version from package.json: ${VERSION}"
fi

# ---------------------------------------------------------------------------
# Validate version format (semver-ish: X.Y.Z or X.Y.Z-suffix)
# ---------------------------------------------------------------------------

if ! echo "${VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$'; then
  echo "❌ Invalid version format: '${VERSION}'"
  echo "   Expected semver format, e.g. 1.2.3 or 1.2.3-beta.1"
  exit 1
fi

echo "✅ Version validated: ${VERSION}"

# ---------------------------------------------------------------------------
# Detect build platform and architecture
# ---------------------------------------------------------------------------

BUILD_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
BUILD_ARCH="$(uname -m)"

# Normalize arch names
case "${BUILD_ARCH}" in
  aarch64) BUILD_ARCH="arm64" ;;
  x86_64)  BUILD_ARCH="x64" ;;
esac

echo "✅ Build platform: ${BUILD_OS}-${BUILD_ARCH}"

# ---------------------------------------------------------------------------
# Validate source directory
# ---------------------------------------------------------------------------

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "❌ Source directory not found: ${SOURCE_DIR}"
  echo "   Make sure helios-agent is installed at ~/.pi/agent/"
  exit 1
fi

echo "✅ Source directory found: ${SOURCE_DIR}"

# ---------------------------------------------------------------------------
# Warn if source has uncommitted changes
# ---------------------------------------------------------------------------

if [[ -d "${SOURCE_DIR}/.git" ]]; then
  local_changes=$(git -C "${SOURCE_DIR}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$local_changes" -gt "0" ]]; then
    echo ""
    echo "⚠️  WARNING: ${SOURCE_DIR} has ${local_changes} uncommitted change(s)"
    echo "   These WILL be included in the release tarball."
    echo ""
    read -p "   Continue anyway? [y/N] " -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Aborted. Commit or stash changes first."
      exit 1
    fi
    echo ""
  else
    echo "✅ Source directory is clean (no uncommitted changes)"
  fi
fi

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------

mkdir -p "${DIST_DIR}"
echo "✅ Output directory ready: ${DIST_DIR}"

# ---------------------------------------------------------------------------
# Set output filenames
# ---------------------------------------------------------------------------

TARBALL_NAME="helios-agent-v${VERSION}-${BUILD_OS}-${BUILD_ARCH}.tar.gz"
CHECKSUM_NAME="helios-agent-v${VERSION}-${BUILD_OS}-${BUILD_ARCH}.tar.gz.sha256"
TARBALL_PATH="${DIST_DIR}/${TARBALL_NAME}"
CHECKSUM_PATH="${DIST_DIR}/${CHECKSUM_NAME}"

# ---------------------------------------------------------------------------
# Create a clean temporary staging directory
# ---------------------------------------------------------------------------

TMPDIR="$(mktemp -d)"
STAGE_DIR="${TMPDIR}/helios-agent-v${VERSION}"
export STAGE_DIR
mkdir -p "${STAGE_DIR}"

echo "📂 Staging directory: ${STAGE_DIR}"

# Clean up temp dir on exit (success or failure)
trap 'echo "🧹 Cleaning up temp dir: ${TMPDIR}"; rm -rf "${TMPDIR}"' EXIT

# ---------------------------------------------------------------------------
# Copy helios-agent contents (with exclusions)
# ---------------------------------------------------------------------------

echo ""
echo "📋 Copying helios-agent from ${SOURCE_DIR} ..."
echo "   Excluding: .git/, node_modules/ (reinstalled fresh in staging), .env, auth.json, settings.json,"
echo "              .venv/, __pycache__/, .pytest_cache/, coding-matrix-data.json,"
echo "              governance/events.jsonl, governance/inline-enforce.jsonl,"
echo "              sessions/, .helios/, .backup.*, *.log, *.disabled,"
echo "              run-history.jsonl, mcp-cache.json, user artifacts"

rsync -a \
  --exclude='*.sock' \
  --exclude='run/' \
  --exclude='.git/' \
  --exclude='node_modules/' \
  --exclude='.venv/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.pytest_cache/' \
  --exclude='coding-matrix-data.json' \
  --exclude='research/' \
  --exclude='artifacts/' \
  --exclude='tests/' \
  --exclude='specs/' \
  --exclude='plans/' \
  --exclude='patches/' \
  --exclude='reports/' \
  --exclude='website/' \
  --exclude='analysis/' \
  --exclude='brainv2/' \
  --exclude='MERGE_GUIDANCE*.md' \
  --exclude='ORCHESTRATOR_MERGE_HANDOFF.md' \
  --exclude='coordination-log-*.md' \
  --exclude='*.backup-*' \
  --exclude='bin/fd' \
  --exclude='*.mp4' \
  --exclude='banner.png' \
  --exclude='skills/skill-graph/scripts/archive/' \
  --exclude='governance/hema-events.jsonl' \
  --exclude='governance/self-reviews.jsonl' \
  --exclude='governance/meta-policies.jsonl' \
  --exclude='governance/loop-runs.jsonl' \
  --exclude='governance/strategy-priors.json' \
  --exclude='governance/hpi-baseline-*.json' \
  --exclude='governance/critic-reports/' \
  --exclude='governance/preflight-enforcer-state.json' \
  --exclude='format-preferences/signals.jsonl' \
  --exclude='format-preferences/format-priors.json' \
  --exclude='~//' \
  --exclude='~/' \
  --exclude='MERGE_SUMMARY_FOR_ORCHESTRATOR.md' \
  --exclude='TASK-*-complete.md' \
  --exclude='vitest.config.*' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='*.env' \
  --exclude='auth.json' \
  --exclude='run-history.jsonl' \
  --exclude='mcp-cache.json' \
  --exclude='provider-health-history.jsonl' \
  --exclude='skill-graph-dlq.jsonl' \
  --exclude='pi-messenger.json' \
  --exclude='session-review.md' \
  --exclude='context.md' \
  --exclude='settings.json' \
  --exclude='DELEGATION_FAILURE_ANALYSIS.md' \
  --exclude='.helios/' \
  --exclude='*.disabled' \
  --exclude='governance/events.jsonl' \
  --exclude='governance/inline-enforce.jsonl' \
  --exclude='sessions/' \
  --exclude='.backup.*/' \
  --exclude='*.log' \
  --exclude='git/' \
  --exclude='packages/' \
  --exclude='backups/' \
  --exclude='.archive/' \
  --exclude='.lab/' \
  --exclude='messenger/' \
  --exclude='webui/' \
  --exclude='eval/' \
  --exclude='dist/' \
  --exclude='*.tar.gz' \
  --exclude='.planning/' \
  --exclude='.DS_Store' \
  --exclude='memgraph-data/' \
  --exclude='subagent-mesh/' \
  --exclude='logs/' \
  --exclude='recaps/' \
  --exclude='memory/' \
  --exclude='tmp/' \
  "${SOURCE_DIR}/" \
  "${STAGE_DIR}/"

# ---------------------------------------------------------------------------
# Replace user-specific governance files with clean templates
# ---------------------------------------------------------------------------
if [[ -d "${STAGE_DIR}/governance" ]]; then
  echo "🔄 Writing clean governance templates..."
  cat > "${STAGE_DIR}/governance/credibility.json" << 'GOVTPL'
{}
GOVTPL
  cat > "${STAGE_DIR}/governance/specialization-registry.json" << 'GOVTPL'
{
  "taskTypes": {},
  "lastUpdated": null
}
GOVTPL
  echo "✅ Governance templates written (credibility.json, specialization-registry.json)"
fi

echo "✅ Copy complete"

# ---------------------------------------------------------------------------
# Post-copy cleanup: remove dev-only files not suitable for distribution
# ---------------------------------------------------------------------------

echo "🧹 Post-copy cleanup ..."

# hema-dispatch/ is a test/barrel sub-package, not a Pi extension.
# Pi auto-discovers directories in extensions/ and fails on this one.
# The real extension hema-dispatch.ts depends on local Memgraph infra — exclude both.
rm -rf "${STAGE_DIR}/extensions/hema-dispatch/"
rm -f "${STAGE_DIR}/extensions/hema-dispatch.ts"
rm -rf "${STAGE_DIR}/extensions/hema-dispatch-lib/"
rm -f "${STAGE_DIR}/extensions/warm-loop.ts"
rm -f "${STAGE_DIR}/extensions/session-mesh-bus.ts"
rm -f "${STAGE_DIR}/extensions/mesh-topology.ts"
rm -rf "${STAGE_DIR}/extensions/format-preference/"

# Remove test files and backups from extensions
find "${STAGE_DIR}/extensions" -name "*.test.ts" -delete 2>/dev/null || true
find "${STAGE_DIR}/extensions" -name "*.bak" -delete 2>/dev/null || true

echo "✅ Cleanup complete"

# ---------------------------------------------------------------------------
# Generate release manifest (used by auto-update for smart file merging)
# ---------------------------------------------------------------------------

echo ""
echo "📋 Generating release manifest..."
(
  cd "${STAGE_DIR}"
  find . -maxdepth 2 -not -path './.git/*' | sed 's|^\./||' | sort
) > "${STAGE_DIR}/.release-manifest.txt"
echo "✅ Release manifest: $(wc -l < "${STAGE_DIR}/.release-manifest.txt" | tr -d ' ') entries"

# ---------------------------------------------------------------------------
# Bundle git packages (so fresh installs get everything in one download)
# ---------------------------------------------------------------------------

echo ""
echo "📦 Bundling git packages ..."

BUNDLE_GIT_DIR="${STAGE_DIR}/git/github.com/helios-agi"
mkdir -p "${BUNDLE_GIT_DIR}"

PACKAGES=(
  pi-subagents
  pi-messenger
  pi-coordination
  pi-model-switch
  pi-powerline-footer
  pi-prompt-template-model
  pi-review-loop
  pi-rewind-hook
  pi-web-access
  pi-interactive-shell
  pi-design-deck
  visual-explainer
  surf-cli
  pi-foreground-chains
  skills-hook
  pi-interview-tool
  pi-annotate
  pi-skill-palette
  pi-boomerang
  helios-searxng
)

bundled=0
# Resolve packages from helios-agi (current) → sweetcheeks72 (legacy) → nicobailon (fallback)
for pkg in "${PACKAGES[@]}"; do
  local_src=""
  for _org in helios-agi sweetcheeks72 nicobailon; do
    if [[ -d "${HOME}/.pi/agent/git/github.com/${_org}/${pkg}" ]]; then
      local_src="${HOME}/.pi/agent/git/github.com/${_org}/${pkg}"
      break
    fi
  done

  if [[ -n "$local_src" ]]; then
    rsync -a \
      --exclude='.git/' \
      --exclude='node_modules/' \
      --exclude='.venv/' \
      --exclude='__pycache__/' \
      --exclude='*.mp4' \
      --exclude='*.png' \
      --exclude='*.gif' \
      --exclude='*.webm' \
      --exclude='.pi/' \
      --exclude='.helios/' \
      --exclude='dist/' \
      --exclude='*.log' \
      "${local_src}/" \
      "${BUNDLE_GIT_DIR}/${pkg}/"
    ((bundled++)) || true
  else
    echo "  ⚠ Package not found locally: ${pkg}"
  fi
done

echo "✅ Bundled ${bundled}/${#PACKAGES[@]} packages"

# Validation: abort if 0 packages bundled
if [[ "$bundled" -eq 0 ]]; then
  echo ""
  echo "❌ ERROR: 0 packages bundled!"
  echo "   Expected git packages in ${HOME}/.pi/agent/git/github.com/{helios-agi,sweetcheeks72,nicobailon}/"
  echo "   The tarball would be incomplete. Aborting build."
  exit 1
fi

# ---------------------------------------------------------------------------
# Generate settings.json with LOCAL package paths (no git: URLs)
# ---------------------------------------------------------------------------
# Pi's package manager treats paths without a known prefix (npm:, git:, etc.)
# as local paths, resolved relative to ~/.pi/agent/. Since the tarball bundles
# packages at git/github.com/helios-agi/<pkg>, we point settings.json there.
# This means `pi update` will NOT try to git-fetch private repos.
# ---------------------------------------------------------------------------

echo ""
echo "🔧 Generating settings.json with local package paths..."

python3 << 'PYEOF'
import json, sys, os, re

source_settings = os.path.expanduser("~/.pi/agent/settings.json")
if not os.path.exists(source_settings):
    print("  ❌ No source settings.json found at ~/.pi/agent/settings.json")
    print("     Cannot generate tarball settings. Aborting build.")
    sys.exit(1)

with open(source_settings) as f:
    settings = json.load(f)

# Match any org variant: helios-agi, sweetcheeks72, nicobailon
ORG_PATTERN = re.compile(r"^git[:/]github\.com/(helios-agi|sweetcheeks72|nicobailon)/")
TARGET_ORG = "helios-agi"  # canonical org in shipped tarball

def normalize_to_local(path_or_src):
    """Convert any org variant to local tarball path under helios-agi."""
    m = ORG_PATTERN.match(path_or_src)
    if m:
        # Normalize: git:github.com/ANY_ORG/pkg → git/github.com/helios-agi/pkg
        #            git/github.com/ANY_ORG/pkg  → git/github.com/helios-agi/pkg
        normalized = ORG_PATTERN.sub(f"git/github.com/{TARGET_ORG}/", path_or_src)
        return normalized, True
    return path_or_src, False

new_packages = []
converted = 0
for pkg in settings.get("packages", []):
    if isinstance(pkg, dict):
        src = pkg.get("source", "")
        new_src, did_convert = normalize_to_local(src)
        if did_convert:
            new_pkg = dict(pkg)
            new_pkg["source"] = new_src
            new_packages.append(new_pkg)
            converted += 1
        else:
            new_packages.append(pkg)
    elif isinstance(pkg, str):
        new_pkg, did_convert = normalize_to_local(pkg)
        new_packages.append(new_pkg)
        if did_convert:
            converted += 1
    else:
        new_packages.append(pkg)

settings["packages"] = new_packages

# Remove user-specific fields that shouldn't ship
for key in ["mcpServers"]:
    settings.pop(key, None)

stage_dir = os.environ["STAGE_DIR"]
out_path = os.path.join(stage_dir, "settings.json")
with open(out_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"  ✅ Converted {converted} git: entries → local paths")
print(f"  ✅ settings.json written to tarball staging")
PYEOF

# ---------------------------------------------------------------------------
# Write VERSION file
# ---------------------------------------------------------------------------

echo "${VERSION}" > "${STAGE_DIR}/VERSION"
echo "✅ VERSION file written: ${VERSION}"

# ---------------------------------------------------------------------------
# Pre-tarball verification: Ensure git/ directory exists and is populated
# ---------------------------------------------------------------------------

echo ""
echo "🔍 Pre-tarball verification..."

if [[ ! -d "${STAGE_DIR}/git/github.com/helios-agi" ]]; then
  echo "❌ CRITICAL: git/ directory missing from staging!"
  echo "   Bundle step must have failed. Aborting build."
  exit 1
fi

GIT_PKG_COUNT=$(find "${STAGE_DIR}/git/github.com/helios-agi" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [[ "$GIT_PKG_COUNT" -lt 10 ]]; then
  echo "❌ CRITICAL: Only ${GIT_PKG_COUNT} packages in git/ directory (expected 15+)"
  echo "   Bundle step incomplete. Aborting build."
  exit 1
fi

echo "✅ Verification passed: ${GIT_PKG_COUNT} packages in git/github.com/helios-agi/"

if [[ -d "${STAGE_DIR}/packages" ]]; then
  echo "⚠️  WARNING: packages/ directory exists in staging (should have been excluded)"
  echo "   This suggests rsync --exclude='packages/' is not working."
  echo "   Continuing build, but please investigate."
fi

# ---------------------------------------------------------------------------
# Install production dependencies in staging (self-contained tarball)
# ---------------------------------------------------------------------------

echo ""
echo "📦 Installing production dependencies in staging directory..."
echo "   This makes the tarball self-contained — no npm install needed on target."

# Agent root dependencies (awilix, neo4j-driver, better-sqlite3, etc.)
if [[ -f "${STAGE_DIR}/package.json" ]]; then
  echo "  → Agent root: npm install --production ..."
  (cd "${STAGE_DIR}" && npm install --production --legacy-peer-deps --no-audit --no-fund 2>&1 | tail -5) || {
    echo "❌ FATAL: Agent root npm install failed. Tarball would be broken."
    exit 1
  }
  echo "  ✅ Agent root deps installed"
fi

# Git package dependencies
echo "  → Git packages with dependencies..."
pkg_deps_installed=0
for pkg_dir in "${STAGE_DIR}/git/github.com/helios-agi"/*/; do
  if [[ -f "${pkg_dir}/package.json" ]]; then
    pkg_name="$(basename "$pkg_dir")"
    dep_count=$(grep -c '"' "${pkg_dir}/package.json" 2>/dev/null || echo "0")
    if [[ "$dep_count" -gt 0 ]]; then
      (cd "$pkg_dir" && npm install --production --legacy-peer-deps --no-audit --no-fund 2>/dev/null) && {
        ((pkg_deps_installed++)) || true
      } || {
        echo "    ⚠ npm install failed for ${pkg_name} — non-fatal"
      }
    fi
  fi
done
echo "  ✅ ${pkg_deps_installed} package dependency trees installed"

# Skill-graph dependencies (has its own package.json with neo4j-driver, tree-sitter)
if [[ -f "${STAGE_DIR}/skills/skill-graph/package.json" ]]; then
  echo "  → Skill-graph deps..."
  (cd "${STAGE_DIR}/skills/skill-graph" && npm install --legacy-peer-deps --no-audit --no-fund 2>/dev/null) || {
    echo "    ⚠ Skill-graph npm install failed — non-fatal"
  }
  echo "  ✅ Skill-graph deps installed"
fi

# Governance dependencies
if [[ -f "${STAGE_DIR}/extensions/helios-governance/package.json" ]]; then
  echo "  → Governance deps..."
  (cd "${STAGE_DIR}/extensions/helios-governance" && npm install --no-audit --no-fund 2>/dev/null) || {
    echo "    ⚠ Governance npm install failed — non-fatal"
  }
  echo "  ✅ Governance deps installed"
fi

# Report node_modules size
TOTAL_NM_SIZE="$(du -sh "${STAGE_DIR}/node_modules" 2>/dev/null | cut -f1 || echo "0")"
echo ""
echo "📊 Bundled node_modules size: ${TOTAL_NM_SIZE}"

# ---------------------------------------------------------------------------
# Create tarball
# ---------------------------------------------------------------------------

echo ""
echo "📦 Creating tarball: ${TARBALL_NAME} ..."

# Create from TMPDIR so the archive root is helios-agent-vX.Y.Z/
(
  cd "${TMPDIR}"
  tar -czf "${TARBALL_PATH}" "helios-agent-v${VERSION}/"
)

echo "✅ Tarball created: ${TARBALL_PATH}"

# ---------------------------------------------------------------------------
# Generate SHA256 checksum
# ---------------------------------------------------------------------------

echo ""
echo "🔒 Generating SHA256 checksum ..."

(
  cd "${DIST_DIR}"
  if command -v sha256sum &>/dev/null; then
    sha256sum "${TARBALL_NAME}" > "${CHECKSUM_NAME}"
  elif command -v shasum &>/dev/null; then
    # macOS
    shasum -a 256 "${TARBALL_NAME}" > "${CHECKSUM_NAME}"
  else
    echo "❌ Neither sha256sum nor shasum found. Cannot generate checksum."
    exit 1
  fi
)

echo "✅ Checksum file created: ${CHECKSUM_PATH}"

# ---------------------------------------------------------------------------
# Report output
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  helios-agent v${VERSION} — Release build complete"
echo "============================================================"
echo ""

TARBALL_SIZE="$(du -sh "${TARBALL_PATH}" | cut -f1)"
CHECKSUM_SIZE="$(du -sh "${CHECKSUM_PATH}" | cut -f1)"

echo "  📦 Tarball  : ${TARBALL_PATH}"
echo "               Size: ${TARBALL_SIZE}"
echo ""
echo "  🔒 Checksum : ${CHECKSUM_PATH}"
echo "               Size: ${CHECKSUM_SIZE}"
echo ""
echo "  Checksum contents:"
cat "${CHECKSUM_PATH}" | sed 's/^/    /'
echo ""
echo "${VERSION}" > "${DIST_DIR}/VERSION"
echo "  📌 Version  : ${DIST_DIR}/VERSION"
echo ""
# Create latest copies — both universal name and arch-specific
cp "${TARBALL_PATH}" "${DIST_DIR}/helios-agent-latest.tar.gz"
cp "${TARBALL_PATH}" "${DIST_DIR}/helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz"
# Regenerate checksum for latest copies with correct relative filenames
(
  cd "${DIST_DIR}"
  if command -v sha256sum &>/dev/null; then
    sha256sum "helios-agent-latest.tar.gz" > "helios-agent-latest.tar.gz.sha256"
    sha256sum "helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz" > "helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz.sha256"
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "helios-agent-latest.tar.gz" > "helios-agent-latest.tar.gz.sha256"
    shasum -a 256 "helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz" > "helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz.sha256"
  fi
)
echo "  📎 Latest   : ${DIST_DIR}/helios-agent-latest.tar.gz"
echo "  📎 Latest (${BUILD_OS}-${BUILD_ARCH}): ${DIST_DIR}/helios-agent-latest-${BUILD_OS}-${BUILD_ARCH}.tar.gz"
echo ""
echo "============================================================"
