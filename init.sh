#!/bin/bash
# DeepSWE v1.1 Perfect Score — Environment Setup
# This repo is self-contained. No dependencies needed to verify checksums.
# Docker is required only for full re-verification (verify.sh --all).

set -euo pipefail

echo "=== DeepSWE v1.1 Perfect Score — Setup ==="

# Check for required tools
echo "Checking tools..."

if command -v git >/dev/null 2>&1; then
  echo "  git: $(git --version)"
else
  echo "  git: MISSING (required)"
fi

if command -v shasum >/dev/null 2>&1; then
  echo "  shasum: available"
else
  echo "  shasum: MISSING (required for checksum verification)"
fi

if command -v python3 >/dev/null 2>&1; then
  echo "  python3: $(python3 --version)"
else
  echo "  python3: MISSING (required for manifest parsing)"
fi

if command -v docker >/dev/null 2>&1; then
  echo "  docker: $(docker --version)"
else
  echo "  docker: not found (only needed for full re-verification)"
fi

# Verify checksums
echo ""
echo "=== Verifying checksums ==="
if shasum -a 256 -c --quiet publish/deepswe-v1.1/checksums.sha256 2>/dev/null; then
  echo "All checksums verified."
else
  echo "WARNING: Checksum verification failed. Check publish/deepswe-v1.1/checksums.sha256"
fi

echo ""
echo "=== Setup complete ==="
echo "To verify a single task:    ./publish/deepswe-v1.1/verify.sh <task-id>"
echo "To verify all tasks:        ./publish/deepswe-v1.1/verify.sh --all"
echo "To verify checksums only:   ./publish/deepswe-v1.1/verify.sh --check"
