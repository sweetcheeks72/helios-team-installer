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
# Validate source directory
# ---------------------------------------------------------------------------

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "❌ Source directory not found: ${SOURCE_DIR}"
  echo "   Make sure helios-agent is installed at ~/.pi/agent/"
  exit 1
fi

echo "✅ Source directory found: ${SOURCE_DIR}"

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------

mkdir -p "${DIST_DIR}"
echo "✅ Output directory ready: ${DIST_DIR}"

# ---------------------------------------------------------------------------
# Set output filenames
# ---------------------------------------------------------------------------

TARBALL_NAME="helios-agent-v${VERSION}.tar.gz"
CHECKSUM_NAME="helios-agent-v${VERSION}.tar.gz.sha256"
TARBALL_PATH="${DIST_DIR}/${TARBALL_NAME}"
CHECKSUM_PATH="${DIST_DIR}/${CHECKSUM_NAME}"

# ---------------------------------------------------------------------------
# Create a clean temporary staging directory
# ---------------------------------------------------------------------------

TMPDIR="$(mktemp -d)"
STAGE_DIR="${TMPDIR}/helios-agent-v${VERSION}"
mkdir -p "${STAGE_DIR}"

echo "📂 Staging directory: ${STAGE_DIR}"

# Clean up temp dir on exit (success or failure)
trap 'echo "🧹 Cleaning up temp dir: ${TMPDIR}"; rm -rf "${TMPDIR}"' EXIT

# ---------------------------------------------------------------------------
# Copy helios-agent contents (with exclusions)
# ---------------------------------------------------------------------------

echo ""
echo "📋 Copying helios-agent from ${SOURCE_DIR} ..."
echo "   Excluding: .git/, node_modules/, .env files, governance/events.jsonl,"
echo "              sessions/, .backup.* dirs, *.log files"

rsync -a \
  --exclude='.git/' \
  --exclude='node_modules/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='*.env' \
  --exclude='governance/events.jsonl' \
  --exclude='governance/' \
  --exclude='sessions/' \
  --exclude='.backup.*/' \
  --exclude='*.log' \
  --exclude='git/' \
  --exclude='backups/' \
  --exclude='.archive/' \
  --exclude='.lab/' \
  --exclude='messenger/' \
  --exclude='webui/' \
  --exclude='eval/' \
  --exclude='dist/' \
  --exclude='*.tar.gz' \
  --exclude='.planning/' \
  "${SOURCE_DIR}/" \
  "${STAGE_DIR}/"

echo "✅ Copy complete"

# ---------------------------------------------------------------------------
# Write VERSION file
# ---------------------------------------------------------------------------

echo "${VERSION}" > "${STAGE_DIR}/VERSION"
echo "✅ VERSION file written: ${VERSION}"

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
# Create latest symlink for installer compatibility
cp "${TARBALL_PATH}" "${DIST_DIR}/helios-agent-latest.tar.gz"
cp "${CHECKSUM_PATH}" "${DIST_DIR}/helios-agent-latest.tar.gz.sha256"
echo "  📎 Latest   : ${DIST_DIR}/helios-agent-latest.tar.gz"
echo ""
echo "============================================================"
