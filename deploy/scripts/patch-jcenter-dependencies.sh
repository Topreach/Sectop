#!/bin/bash
# =============================================================================
# Danger Emergence System - Patch JCenter Dependencies
# =============================================================================
# This script patches Flutter plugin build.gradle files that still reference
# the deprecated jcenter() repository, replacing it with mavenCentral().
#
# Usage:
#   bash deploy/scripts/patch-jcenter-dependencies.sh
# =============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Configuration ────────────────────────────────────────────────────────────
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
HOSTED_DIR="$PUB_CACHE_DIR/hosted/pub.dev"

# ── Patch Function ───────────────────────────────────────────────────────────
patch_build_gradle() {
  local BUILD_GRADLE="$1"
  
  if [ ! -f "$BUILD_GRADLE" ]; then
    return 1
  fi
  
  # Check if jcenter() is used
  if grep -q 'jcenter()' "$BUILD_GRADLE" 2>/dev/null; then
    log_warn "Found jcenter() in: $BUILD_GRADLE"
    
    # Replace jcenter() with mavenCentral()
    sed -i 's/jcenter()/mavenCentral()/g' "$BUILD_GRADLE"
    
    # Also add google() if not present (needed for AndroidX)
    if ! grep -q "google()" "$BUILD_GRADLE" 2>/dev/null; then
      sed -i '/repositories {/a\        google()' "$BUILD_GRADLE"
    fi
    
    log_ok "Patched: $BUILD_GRADLE"
    return 0
  fi
  
  return 1
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "=============================================="
  echo "  Patch JCenter Dependencies"
  echo "=============================================="
  echo ""
  
  if [ ! -d "$HOSTED_DIR" ]; then
    log_warn "Pub cache directory not found at $HOSTED_DIR"
    log_info "Skipping patch (no cached dependencies to patch)"
    return 0
  fi
  
  log_info "Scanning for build.gradle files with jcenter() references..."
  
  local PATCHED=0
  local FOUND=0
  
  while IFS= read -r -d '' BUILD_GRADLE; do
    FOUND=$((FOUND + 1))
    if patch_build_gradle "$BUILD_GRADLE"; then
      PATCHED=$((PATCHED + 1))
    fi
  done < <(find "$HOSTED_DIR" -name "build.gradle" -print0 2>/dev/null)
  
  if [ "$PATCHED" -gt 0 ]; then
    log_ok "Patched $PATCHED build.gradle file(s)"
  else
    log_info "No jcenter() references found in $FOUND build.gradle file(s)"
  fi
  
  echo ""
}

main "$@"
