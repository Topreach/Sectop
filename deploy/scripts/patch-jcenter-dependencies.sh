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
  
  # ── Check if the file is corrupted by previous bad patches ───────────────
  # A corrupted file will have "namespace" appearing many times (on every line)
  local NAMESPACE_COUNT
  NAMESPACE_COUNT=$(grep -c "namespace " "$BUILD_GRADLE" 2>/dev/null || echo 0)
  
  if [ "$NAMESPACE_COUNT" -gt 3 ]; then
    log_warn "File appears corrupted (namespace on $NAMESPACE_COUNT lines): $BUILD_GRADLE"
    log_info "Deleting corrupted plugin directory so it can be re-downloaded fresh..."
    rm -rf "$DIR"
    return 2
  fi
  
  # ── Find the buildscript { } end line ────────────────────────────────────
  # Count braces inside buildscript to find where it closes
  local BUILDSCRIPT_END_LINE
  BUILDSCRIPT_END_LINE=$(awk '
    /buildscript \{/ { bs=1 }
    bs==1 && /\{/ { brace_count++ }
    bs==1 && /\}/ { brace_count--; if (brace_count == 0) { print NR; exit } }
  ' "$BUILD_GRADLE")
  
  if [ -z "$BUILDSCRIPT_END_LINE" ]; then
    BUILDSCRIPT_END_LINE=0
  fi
  
  # ── Check if namespace already exists in the correct location ────────────
  # "Correct" means: the namespace line appears AFTER buildscript ends
  local NAMESPACE_LINE
  NAMESPACE_LINE=$(awk -v bs_end="$BUILDSCRIPT_END_LINE" '
    NR > bs_end && /namespace / { print NR; exit }
  ' "$BUILD_GRADLE")
  
  if [ -n "$NAMESPACE_LINE" ]; then
    # Namespace already exists in the correct location — skip
    return 1
  fi
  
  # ── Remove any misplaced namespace lines (e.g. inside buildscript) ───────
  # This handles the case where a previous broken run inserted it in the wrong spot
  local TEMP_FILE
  TEMP_FILE=$(mktemp)
  grep -v "namespace " "$BUILD_GRADLE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$BUILD_GRADLE"
  
  # ── Find the android { } block (after buildscript ends) ──────────────────
  local ANDROID_BLOCK_LINE
  ANDROID_BLOCK_LINE=$(awk -v bs_end="$BUILDSCRIPT_END_LINE" '
    NR > bs_end && /^android \{/ { print NR; exit }
    NR > bs_end && /^android$/ { print NR; exit }
  ' "$BUILD_GRADLE")
  
  if [ -z "$ANDROID_BLOCK_LINE" ]; then
    log_warn "Cannot find android block after buildscript in: $BUILD_GRADLE"
    return 1
  fi
  
  # ── Insert namespace right after the android { line ──────────────────────
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
  local CORRUPTED=0
  
  while IFS= read -r -d '' BUILD_GRADLE; do
    patch_namespace "$BUILD_GRADLE"
    local RC=$?
    if [ "$RC" -eq 0 ]; then
      PATCHED_NS=$((PATCHED_NS + 1))
    elif [ "$RC" -eq 2 ]; then
      CORRUPTED=$((CORRUPTED + 1))
    fi
  done < <(find "$HOSTED_DIR" -name "build.gradle" -print0 2>/dev/null)
  
  if [ "$PATCHED_NS" -gt 0 ]; then
    log_ok "Added namespace to $PATCHED_NS build.gradle file(s)"
  fi
  if [ "$CORRUPTED" -gt 0 ]; then
    log_warn "Deleted $CORRUPTED corrupted plugin(s) — they will be re-downloaded during build"
  fi
  if [ "$PATCHED_NS" -eq 0 ] && [ "$CORRUPTED" -eq 0 ]; then
    log_info "No library modules missing namespace found"
  fi
  
  echo ""
  
  # Return 2 if any corrupted files were deleted (caller should re-run pub get)
  if [ "$CORRUPTED" -gt 0 ]; then
    return 2
  fi
}

main "$@"
