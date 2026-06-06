#!/bin/bash
# =============================================================================
# Danger Emergence System - Patch Plugin Dependencies for AGP 8+
# =============================================================================
# This script patches Flutter plugin build.gradle files that:
# 1. Still reference the deprecated jcenter() repository → mavenCentral()
# 2. Are missing the required 'namespace' property for AGP 8+
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

# ── Patch jcenter() → mavenCentral() ────────────────────────────────────────
patch_jcenter() {
  local BUILD_GRADLE="$1"
  
  if [ ! -f "$BUILD_GRADLE" ]; then
    return 1
  fi
  
  if grep -q 'jcenter()' "$BUILD_GRADLE" 2>/dev/null; then
    log_warn "Found jcenter() in: $BUILD_GRADLE"
    sed -i 's/jcenter()/mavenCentral()/g' "$BUILD_GRADLE"
    if ! grep -q "google()" "$BUILD_GRADLE" 2>/dev/null; then
      sed -i '/repositories {/a\        google()' "$BUILD_GRADLE"
    fi
    log_ok "Patched jcenter() → mavenCentral(): $BUILD_GRADLE"
    return 0
  fi
  return 1
}

# ── Add namespace to plugin build.gradle ────────────────────────────────────
# AGP 8+ requires a 'namespace' in build.gradle for library modules.
# We extract the package from the corresponding AndroidManifest.xml
# and add it inside the android { } block (NOT inside buildscript { }).
patch_namespace() {
  local BUILD_GRADLE="$1"
  
  if [ ! -f "$BUILD_GRADLE" ]; then
    return 1
  fi
  
  # Skip if already has namespace
  if grep -q "namespace " "$BUILD_GRADLE" 2>/dev/null; then
    return 1
  fi
  
  # Only patch library modules
  if ! grep -q "com.android.library" "$BUILD_GRADLE" 2>/dev/null; then
    return 1
  fi
  
  # Find the corresponding AndroidManifest.xml
  local DIR
  DIR="$(dirname "$BUILD_GRADLE")"
  local MANIFEST="$DIR/src/main/AndroidManifest.xml"
  
  if [ ! -f "$MANIFEST" ]; then
    MANIFEST="$(dirname "$DIR")/src/main/AndroidManifest.xml"
  fi
  if [ ! -f "$MANIFEST" ]; then
    MANIFEST="$DIR/AndroidManifest.xml"
  fi
  
  if [ ! -f "$MANIFEST" ]; then
    log_warn "Cannot find AndroidManifest.xml for: $BUILD_GRADLE"
    return 1
  fi
  
  # Extract package from manifest
  local PACKAGE
  PACKAGE=$(grep -o 'package="[^"]*"' "$MANIFEST" 2>/dev/null | head -1 | sed 's/package="//;s/"//')
  
  if [ -z "$PACKAGE" ]; then
    log_warn "No package found in manifest for: $BUILD_GRADLE"
    return 1
  fi
  
  # Use awk to find the android { } block that is NOT inside buildscript { }
  # Strategy: find lines matching /^android {/ or /^android {/ after buildscript closes
  # We look for the LAST occurrence of "android {" that is at the root level
  # (not inside buildscript). A simple heuristic: find "android {" after "buildscript" block ends.
  
  # Count buildscript blocks to find where they end
  local BUILDSCRIPT_END_LINE
  BUILDSCRIPT_END_LINE=$(awk '
    /buildscript \{/ { bs=1 }
    bs==1 && /\{/ { brace_count++; if (brace_count==1) first_bs_line=NR }
    bs==1 && /\}/ { brace_count--; if (brace_count==0) { print NR; exit } }
  ' "$BUILD_GRADLE")
  
  if [ -z "$BUILDSCRIPT_END_LINE" ]; then
    BUILDSCRIPT_END_LINE=0
  fi
  
  # Now find the first "android {" after buildscript ends
  local ANDROID_BLOCK_LINE
  ANDROID_BLOCK_LINE=$(awk -v bs_end="$BUILDSCRIPT_END_LINE" '
    NR > bs_end && /^android \{/ { print NR; exit }
    NR > bs_end && /^android$/ { print NR; exit }
  ' "$BUILD_GRADLE")
  
  if [ -z "$ANDROID_BLOCK_LINE" ]; then
    log_warn "Cannot find android block after buildscript in: $BUILD_GRADLE"
    return 1
  fi
  
  # Insert namespace right after the android { line
  sed -i "${ANDROID_BLOCK_LINE}a\\    namespace '${PACKAGE}'" "$BUILD_GRADLE"
  
  log_ok "Added namespace '${PACKAGE}' to: $BUILD_GRADLE (line $ANDROID_BLOCK_LINE)"
  return 0
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "=============================================="
  echo "  Patch Plugin Dependencies"
  echo "=============================================="
  echo ""
  
  if [ ! -d "$HOSTED_DIR" ]; then
    log_warn "Pub cache directory not found at $HOSTED_DIR"
    log_info "Skipping patch (no cached dependencies to patch)"
    return 0
  fi
  
  # Step 1: Patch jcenter() references
  log_info "Scanning for jcenter() references..."
  local PATCHED_JCENTER=0
  local FOUND=0
  
  while IFS= read -r -d '' BUILD_GRADLE; do
    FOUND=$((FOUND + 1))
    if patch_jcenter "$BUILD_GRADLE"; then
      PATCHED_JCENTER=$((PATCHED_JCENTER + 1))
    fi
  done < <(find "$HOSTED_DIR" -name "build.gradle" -print0 2>/dev/null)
  
  if [ "$PATCHED_JCENTER" -gt 0 ]; then
    log_ok "Patched jcenter() in $PATCHED_JCENTER build.gradle file(s)"
  else
    log_info "No jcenter() references found in $FOUND build.gradle file(s)"
  fi
  
  # Step 2: Add namespace to library modules missing it
  echo ""
  log_info "Scanning for library modules missing namespace..."
  local PATCHED_NS=0
  
  while IFS= read -r -d '' BUILD_GRADLE; do
    if patch_namespace "$BUILD_GRADLE"; then
      PATCHED_NS=$((PATCHED_NS + 1))
    fi
  done < <(find "$HOSTED_DIR" -name "build.gradle" -print0 2>/dev/null)
  
  if [ "$PATCHED_NS" -gt 0 ]; then
    log_ok "Added namespace to $PATCHED_NS build.gradle file(s)"
  else
    log_info "No library modules missing namespace found"
  fi
  
  echo ""
}

main "$@"
