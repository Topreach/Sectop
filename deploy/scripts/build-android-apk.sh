#!/bin/bash
# =============================================================================
# Danger Emergence System - Android APK Build Script
# =============================================================================
# Builds a release APK for the Danger Emergence mobile app.
# The frontend is a thin client that communicates with the backend via REST API.
#
# Usage:
#   ./deploy/scripts/build-android-apk.sh
#
# Environment variables:
#   MAPBOX_ACCESS_TOKEN  - (optional) Mapbox token for map tiles
#   ANDROID_HOME         - (optional) Android SDK path (default: /opt/android-sdk)
# =============================================================================
# Intentionally avoid 'set -euo pipefail' because find|while-read pipelines
# and find -exec sed commands can trigger false failures with pipefail.
# Instead, we handle errors explicitly with '|| true' where needed.
set -u

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$PROJECT_DIR/frontend"
ANDROID_SDK_ROOT="${ANDROID_HOME:-/opt/android-sdk}"
BUILD_DIR="$FRONTEND_DIR/build/app/outputs/flutter-apk"
OUTPUT_APK="$PROJECT_DIR/danger-emergence.apk"

# ── Loggers ──────────────────────────────────────────────────────────────────
log_info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

# ── Step 1: Plugin Compatibility Patching ────────────────────────────────────
patch_plugins() {
  log_info "Patching plugin compatibility for AGP 8+ and v2 embedding..."

  # Determine pub cache directory (may be empty on some systems)
  local PUB_CACHE_DIR
  if [ -n "${PUB_CACHE:-}" ]; then
    PUB_CACHE_DIR="$PUB_CACHE"
  else
    PUB_CACHE_DIR="/root/.pub-cache"
  fi

  # Fix missing 'namespace' in plugin build.gradle files (required for AGP 8+)
  # Use temp file to avoid pipefail issues with 'set -u'
  local GRADLE_LIST="/tmp/sectop_gradle_files_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" 2>/dev/null > "$GRADLE_LIST" || true
  while read -r gradle_file; do
    [ -z "$gradle_file" ] && continue
    if grep -q "apply plugin: 'com.android.library'" "$gradle_file" 2>/dev/null; then
      if ! grep -q "namespace" "$gradle_file" 2>/dev/null; then
        local manifest_dir
        manifest_dir="$(dirname "$gradle_file")/src/main/AndroidManifest.xml"
        if [ -f "$manifest_dir" ]; then
          local pkg_name
          pkg_name=$(grep "package=" "$manifest_dir" | sed -e 's/.*package="//' -e 's/".*//')
          if [ -n "$pkg_name" ]; then
            sed -i "/android {/a \    namespace \"$pkg_name\"" "$gradle_file"
            log_info "  Added namespace '$pkg_name' to $(basename "$(dirname "$gradle_file")")"
          fi
        fi
      fi
    fi
  done < "$GRADLE_LIST"
  rm -f "$GRADLE_LIST"

  # Fix plugins with safeExtGet() that returns null in Gradle 8.x
  # Some plugins (e.g. background_fetch) define safeExtGet as a local method in
  # the android block's ext, but in Gradle 8.x this method isn't found when
  # called from compileSdkVersion. We replace safeExtGet() calls with direct
  # fallback values.
  #
  # IMPORTANT: Order of sed operations matters here. We must fix any lines
  # corrupted by PREVIOUS sed runs FIRST, before doing the safeExtGet replacement.
  # Otherwise "compileSdk 34safeExtGet(...)" -> safeExtGet replaced -> "compileSdk 3434"
  #
  # NOTE: PUB_CACHE_DIR is already set above (see namespace patching section).

  # STEP 1: Fix ALL corrupted lines across ALL plugins (from previous [0-9]* sed bug)
  # The old sed pattern 's/compileSdk [0-9]*/compileSdk 34/g' matched zero digits
  # when the next token was non-numeric, producing lines like:
  #   "compileSdk 34safeExtGet('compileSdkVersion', 36)"  (background_fetch)
  #   "compileSdk 34= 36 // flutter.compileSdkVersion"     (sqflite_android)
  # We fix these by removing the corrupted suffix after the intended value.
  log_info "Fixing any plugin build.gradle files corrupted by previous sed runs..."
  local CORRUPTED_LIST="/tmp/sectop_corrupted_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" 2>/dev/null > "$CORRUPTED_LIST" || true
  while read -r gradle_file; do
    [ -z "$gradle_file" ] && continue
    # Fix: "compileSdk 34safeExtGet(...)" -> "compileSdk 34"
    sed -i 's/\(compileSdk \)[0-9][0-9]*safeExtGet([^)]*)/\134/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdkVersion 34safeExtGet(...)" -> "compileSdkVersion 34"
    sed -i 's/\(compileSdkVersion \)[0-9][0-9]*safeExtGet([^)]*)/\134/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdk 34= 36 // ..." -> "compileSdk 34"
    sed -i 's/\(compileSdk \)[0-9][0-9]*= [0-9][0-9]*.*/\134/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdkVersion 34= 36 // ..." -> "compileSdkVersion 34"
    sed -i 's/\(compileSdkVersion \)[0-9][0-9]*= [0-9][0-9]*.*/\134/g' "$gradle_file" 2>/dev/null || true
  done < "$CORRUPTED_LIST"
  rm -f "$CORRUPTED_LIST"

  # STEP 2: Replace safeExtGet() calls with direct values in ALL plugins
  # Use wildcard for fallback value since different versions may use different defaults
  log_info "Replacing safeExtGet() calls with direct values..."
  local SAFEEXT_LIST="/tmp/sectop_safeext_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" 2>/dev/null > "$SAFEEXT_LIST" || true
  while read -r gradle_file; do
    [ -z "$gradle_file" ] && continue
    if grep -q "safeExtGet" "$gradle_file" 2>/dev/null; then
      sed -i 's/safeExtGet("compileSdkVersion", [0-9]*)/34/g' "$gradle_file" 2>/dev/null || true
      sed -i "s/safeExtGet('compileSdkVersion', [0-9]*)/34/g" "$gradle_file" 2>/dev/null || true
      sed -i 's/safeExtGet("minSdkVersion", [0-9]*)/21/g' "$gradle_file" 2>/dev/null || true
      sed -i "s/safeExtGet('minSdkVersion', [0-9]*)/21/g" "$gradle_file" 2>/dev/null || true
      sed -i 's/safeExtGet("targetSdkVersion", [0-9]*)/34/g' "$gradle_file" 2>/dev/null || true
      sed -i "s/safeExtGet('targetSdkVersion', [0-9]*)/34/g" "$gradle_file" 2>/dev/null || true
    fi
  done < "$SAFEEXT_LIST"
  rm -f "$SAFEEXT_LIST"

  # Bump all plugins to SDK 34
  # NOTE: Use [0-9][0-9]* (one or more digits) instead of [0-9]* (zero or more)
  # to avoid matching non-numeric tokens like 'safeExtGet' after 'compileSdk '
  log_info "Bumping plugin SDK versions to 34..."
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" -exec sed -i 's/compileSdkVersion [0-9][0-9]*/compileSdkVersion 34/g' {} + 2>/dev/null || true
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" -exec sed -i 's/targetSdkVersion [0-9][0-9]*/targetSdkVersion 34/g' {} + 2>/dev/null || true
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" -exec sed -i 's/compileSdk [0-9][0-9]*/compileSdk 34/g' {} + 2>/dev/null || true

  # Fix Android v1 embedding → v2 embedding for all plugins
  # Flutter 3.16+ requires all plugins to use the v2 Android embedding.
  # The v1 embedding uses io.flutter.app.FlutterActivity (deprecated).
  # We patch plugin AndroidManifest.xml files to add the v2 registration.
  log_info "Migrating plugins from v1 to v2 Android embedding..."
  local MANIFEST_LIST="/tmp/sectop_manifests_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "AndroidManifest.xml" 2>/dev/null > "$MANIFEST_LIST" || true
  while read -r manifest; do
    [ -z "$manifest" ] && continue
    # Check if this manifest uses v1 embedding (has old FlutterActivity/FlutterApplication references)
    if grep -q "android:name=\"io.flutter.app." "$manifest" 2>/dev/null; then
      log_info "  Patching v1 embedding in: $(basename "$(dirname "$(dirname "$manifest")")")"
      # Replace v1 FlutterActivity with v2 FlutterActivity
      sed -i 's|io\.flutter\.app\.FlutterActivity|io.flutter.embedding.android.FlutterActivity|g' "$manifest"
      sed -i 's|io\.flutter\.app\.FlutterApplication|io.flutter.embedding.android.FlutterApplication|g' "$manifest"
      # Add FlutterActivity to manifest if not present
      if ! grep -q "io.flutter.embedding.android.FlutterActivity" "$manifest" 2>/dev/null; then
        sed -i '/<\/application>/i \        <activity android:name="io.flutter.embedding.android.FlutterActivity" android:exported="false"/>' "$manifest"
      fi
    fi
  done < "$MANIFEST_LIST"
  rm -f "$MANIFEST_LIST"

  # Also patch any plugin build.gradle that references the old v1 embedding
  local GRADLE_LIST2="/tmp/sectop_gradle2_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" 2>/dev/null > "$GRADLE_LIST2" || true
  while read -r gradle_file; do
    [ -z "$gradle_file" ] && continue
    if grep -q "io.flutter.app" "$gradle_file" 2>/dev/null; then
      log_info "  Patching v1 embedding references in: $(basename "$(dirname "$gradle_file")")"
      sed -i 's|io\.flutter\.app\.FlutterActivity|io.flutter.embedding.android.FlutterActivity|g' "$gradle_file"
      sed -i 's|io\.flutter\.app\.FlutterApplication|io.flutter.embedding.android.FlutterApplication|g' "$gradle_file"
    fi
  done < "$GRADLE_LIST2"
  rm -f "$GRADLE_LIST2"

  # Patch Flutter SDK's Gradle plugin to skip v1 embedding check
  # Flutter 3.16+ checks for v1 embedding and fails the build.
  # We disable this check by patching the Flutter Gradle plugin.
  local FLUTTER_SDK
  # Try multiple possible Flutter SDK locations
  if [ -d "/root/snap/flutter/common/flutter" ]; then
    FLUTTER_SDK="/root/snap/flutter/common/flutter"
  elif [ -d "/snap/flutter/common/flutter" ]; then
    FLUTTER_SDK="/snap/flutter/common/flutter"
  else
    FLUTTER_SDK="$(dirname "$(dirname "$(which flutter 2>/dev/null || echo '')")" 2>/dev/null)"
  fi

  # Try to find the Gradle plugin source file
  local FLUTTER_GRADLE_PLUGIN
  FLUTTER_GRADLE_PLUGIN=$(find "$FLUTTER_SDK" -path "*/flutter_tools/gradle/src/main/groovy/flutter.groovy" 2>/dev/null | head -1)

  if [ -n "$FLUTTER_GRADLE_PLUGIN" ] && [ -f "$FLUTTER_GRADLE_PLUGIN" ]; then
    log_info "Patching Flutter Gradle plugin at: $FLUTTER_GRADLE_PLUGIN"
    # Comment out the v1 embedding check by wrapping it in a conditional that always skips
    sed -i 's|if (pluginManifestV1Embedding)|if (false \&\& pluginManifestV1Embedding)|g' "$FLUTTER_GRADLE_PLUGIN" 2>/dev/null || true
    log_ok "Flutter Gradle plugin patched"
  else
    log_warn "Could not find Flutter Gradle plugin source at $FLUTTER_SDK"
    log_warn "Will rely on manifest patching only"
  fi

  log_ok "Plugin patching complete"
}

# ── Step 2: Build APK ────────────────────────────────────────────────────────
build_apk() {
  log_info "Building release APK..."
  cd "$FRONTEND_DIR"

  # Get dependencies
  flutter pub get

  # Patch plugins for compatibility
  patch_plugins

  # Clean previous build artifacts (delete directly instead of using ./gradlew clean
  # to avoid triggering Gradle daemon issues)
  log_info "Cleaning previous build artifacts..."
  rm -rf "$FRONTEND_DIR/build/" "$FRONTEND_DIR/android/.gradle/" "$FRONTEND_DIR/android/app/build/" 2>/dev/null || true

  # Delete Gradle caches to ensure a clean state for the new Gradle version.
  # Gradle 8.14 embeds Kotlin 2.0.x which is required by Flutter 3.44.1's
  # kotlin-dsl plugin. Old caches from Gradle 8.14 (Kotlin 2.0.21) are incompatible.

  # Build release APK (no tree-shake icons to ensure all Material icons are included)
  # Use --no-android-gradle-daemon to avoid daemon memory issues on low-RAM servers
  # First build may take longer due to Gradle download + dependency resolution
  # --android-skip-build-dependency-validation: Bypass Flutter's Kotlin version check.
  flutter build apk --release --no-tree-shake-icons --android-skip-build-dependency-validation

  # Verify and copy output
  if [ -f "$BUILD_DIR/app-release.apk" ]; then
    local size
    size=$(du -h "$BUILD_DIR/app-release.apk" | cut -f1)
    log_ok "APK built successfully! Size: $size"
    cp "$BUILD_DIR/app-release.apk" "$OUTPUT_APK"
    log_ok "APK copied to: $OUTPUT_APK"
  else
    log_error "Build failed - APK not found at $BUILD_DIR/app-release.apk"
    exit 1
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  log_info "=== Danger Emergence Android APK Build ==="
  log_info "Project: $PROJECT_DIR"
  log_info "Android SDK: $ANDROID_SDK_ROOT"
  echo ""

  build_apk

  log_ok "=== Build Complete ==="
  log_info "Install the APK on your device:"
  log_info "  adb install $OUTPUT_APK"
}

main "$@"
