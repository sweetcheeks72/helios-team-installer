#!/usr/bin/env bash
# e2e_esm_audit.sh — Find unprotected require() on ESM-only @helios-agent/* packages
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use agent dir or tarball extraction
AGENT_DIR="${1:-$HOME/.pi/agent}"

echo "=== ESM Audit: require('@helios-agent/...') ==="
echo "Scanning: $AGENT_DIR"
echo ""

FOUND=0
PROTECTED=0
UNPROTECTED=0

# Find all require('@helios-agent/...') calls
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  line_num=$(echo "$match" | cut -d: -f2)
  content=$(echo "$match" | cut -d: -f3-)
  ((FOUND++))
  
  # Check if this line or the 5 lines before it have a try {
  start=$((line_num - 5))
  [[ $start -lt 1 ]] && start=1
  context=$(sed -n "${start},${line_num}p" "$file" 2>/dev/null)
  
  if echo "$context" | grep -q 'try\s*{\|try{\|__requireHeliosPkg'; then
    ((PROTECTED++))
  else
    ((UNPROTECTED++))
    echo "  ✗ UNPROTECTED: $file:$line_num"
    echo "    $content"
  fi
done < <(grep -rn "require.*['\"]@helios-agent/" "$AGENT_DIR/extensions/" "$AGENT_DIR/git/github.com/" 2>/dev/null | grep -v node_modules | grep -v '.backup' | grep -v '.git/' || true)

echo ""
echo "═══════════════════════════════════════"
echo "Total require() calls: $FOUND"
echo "Protected (try-catch): $PROTECTED"
echo "Unprotected: $UNPROTECTED"
echo "═══════════════════════════════════════"

if [[ $UNPROTECTED -gt 0 ]]; then
  echo "✗ FAIL: $UNPROTECTED unprotected require() calls found"
  exit 1
else
  echo "✓ PASS: All require() calls are protected"
  exit 0
fi
