#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${HOME}/.familiar"
DIST_DIR="${SCRIPT_DIR}/dist"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./build-familiar-release.sh <VERSION>"
  exit 1
fi

echo "📌 Building familiar runtime tarball v${VERSION}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "❌ Source not found: $SOURCE_DIR"
  exit 1
fi

mkdir -p "$DIST_DIR"

TMPDIR="$(mktemp -d)"
STAGE_DIR="$TMPDIR/familiar-v${VERSION}"
mkdir -p "$STAGE_DIR"
trap 'echo "🧹 Cleaning up: $TMPDIR"; rm -rf "$TMPDIR"' EXIT

echo "📋 Copying runtime files from ${SOURCE_DIR}..."
rsync -a \
  --exclude='.git/' \
  --exclude='node_modules/' \
  --exclude='apps/' \
  --exclude='logs/' \
  --exclude='sessions/' \
  --exclude='memory/' \
  --exclude='data/' \
  --exclude='docs/' \
  --exclude='specs/' \
  --exclude='tests/' \
  --exclude='plans/' \
  --exclude='patches/' \
  --exclude='tmp/' \
  --exclude='*.log' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='secrets.enc' \
  --exclude='helios.db-shm' \
  --exclude='helios.db-wal' \
  --exclude='server_log.txt' \
  --exclude='*.test.ts' \
  --exclude='*.test.js' \
  --exclude='vitest.config.*' \
  --exclude='review-queue/' \
  --exclude='observations/' \
  --exclude='signals/' \
  --exclude='usage/' \
  --exclude='locks/' \
  --exclude='.DS_Store' \
  "${SOURCE_DIR}/" \
  "${STAGE_DIR}/"

echo "✅ Copy complete"

# Keep skills node_modules (they're production deps needed at runtime)
echo "📦 Restoring skills node_modules..."
for skill_dir in "${SOURCE_DIR}/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  if [[ -d "${skill_dir}node_modules" ]]; then
    cp -a "${skill_dir}node_modules" "${STAGE_DIR}/skills/${skill_name}/node_modules"
  fi
done

# Restore integrations node_modules if any
for int_dir in "${SOURCE_DIR}/integrations"/*/; do
  int_name="$(basename "$int_dir")"
  if [[ -d "${int_dir}node_modules" ]]; then
    cp -a "${int_dir}node_modules" "${STAGE_DIR}/integrations/${int_name}/node_modules"
  fi
done

echo "✅ Dependencies bundled"

# Create empty dirs that extensions expect
mkdir -p "${STAGE_DIR}/index-manifests"

# Write VERSION
echo "$VERSION" > "${STAGE_DIR}/VERSION"

# Create tarball
TARBALL_NAME="familiar-v${VERSION}-runtime.tar.gz"
TARBALL_PATH="${DIST_DIR}/${TARBALL_NAME}"

echo "📦 Creating tarball: ${TARBALL_NAME}..."
(cd "$TMPDIR" && tar -czf "$TARBALL_PATH" "familiar-v${VERSION}/")

# Checksum
shasum -a 256 "$TARBALL_PATH" | awk '{print $1 "  " FILENAME}' FILENAME="$TARBALL_NAME" > "${TARBALL_PATH}.sha256"

# Latest symlinks
ln -sf "$TARBALL_NAME" "${DIST_DIR}/familiar-latest.tar.gz"
cp "${TARBALL_PATH}.sha256" "${DIST_DIR}/familiar-latest.tar.gz.sha256"

TARBALL_SIZE=$(du -h "$TARBALL_PATH" | awk '{print $1}')
echo ""
echo "============================================================"
echo "  familiar v${VERSION} — Runtime tarball built"
echo "============================================================"
echo "  📦 Tarball : ${TARBALL_PATH}"
echo "             Size: ${TARBALL_SIZE}"
echo "  🔒 Checksum: ${TARBALL_PATH}.sha256"
echo "============================================================"
