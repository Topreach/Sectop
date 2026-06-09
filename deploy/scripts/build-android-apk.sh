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

# ── Step 0: Pre-build Configuration Validation ────────────────────────────
check_config() {
  log_info "=== Pre-build Configuration Validation ==="
  local errors=0

  # 0.1 Check Flutter
  if command -v flutter &>/dev/null; then
    local flutter_version
    flutter_version=$(flutter --version 2>/dev/null | head -1)
    log_ok "Flutter: $flutter_version"
  else
    log_error "Flutter is not installed or not in PATH"
    errors=$((errors + 1))
  fi

  # 0.2 Check Android SDK
  if [ -d "$ANDROID_SDK_ROOT" ]; then
    log_ok "Android SDK: $ANDROID_SDK_ROOT"
  else
    log_warn "Android SDK not found at $ANDROID_SDK_ROOT (will try ANDROID_HOME)"
    if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
      log_ok "Android SDK: $ANDROID_HOME"
    else
      log_error "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT"
      errors=$((errors + 1))
    fi
  fi

  # 0.3 Check Java
  if command -v java &>/dev/null; then
    local java_version
    java_version=$(java -version 2>&1 | head -1)
    log_ok "Java: $java_version"
  else
    log_error "Java is not installed or not in PATH (required by Gradle)"
    errors=$((errors + 1))
  fi

  # 0.4 Check disk space (need at least 2GB free)
  local free_kb
  free_kb=$(df "$PROJECT_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
  if [ -n "$free_kb" ] && [ "$free_kb" -gt 2097152 ] 2>/dev/null; then
    local free_mb=$((free_kb / 1024))
    log_ok "Disk space: ${free_mb}MB free"
  else
    log_warn "Low disk space (may cause build failures)"
  fi

  # 0.5 Check RAM (need at least 2GB available for 1.5GB Gradle heap + OS overhead)
  if command -v free &>/dev/null; then
    local avail_mb
    avail_mb=$(free -m 2>/dev/null | grep "Mem:" | awk '{print $7}')
    if [ -n "$avail_mb" ] && [ "$avail_mb" -gt 2048 ] 2>/dev/null; then
      log_ok "Available RAM: ${avail_mb}MB"
    else
      log_warn "Low available RAM: ${avail_mb:-?}MB (Gradle allocated to 1.5GB heap)"
    fi
  fi

  # 0.5b Check swap availability
  if command -v free &>/dev/null; then
    local swap_total
    swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    if [ -n "$swap_total" ] && [ "$swap_total" -le 0 ] 2>/dev/null; then
      log_warn "No swap space available. Build may fail with OOM on low-RAM servers."
      log_warn "Consider adding swap: fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
    fi
  fi

  # 0.6 Check gradle-wrapper.properties exists
  local WRAPPER_PROPS="$FRONTEND_DIR/android/gradle/wrapper/gradle-wrapper.properties"
  if [ -f "$WRAPPER_PROPS" ]; then
    local gradle_url
    gradle_url=$(grep "distributionUrl" "$WRAPPER_PROPS" 2>/dev/null | sed 's/.*=//')
    log_ok "Gradle wrapper: $gradle_url"
  else
    log_error "gradle-wrapper.properties not found at $WRAPPER_PROPS"
    errors=$((errors + 1))
  fi

  # 0.7 Check pubspec.yaml exists
  if [ -f "$FRONTEND_DIR/pubspec.yaml" ]; then
    log_ok "Project pubspec.yaml found"
  else
    log_error "pubspec.yaml not found at $FRONTEND_DIR/pubspec.yaml"
    errors=$((errors + 1))
  fi

  echo ""
  if [ "$errors" -gt 0 ]; then
    log_error "Configuration check failed with $errors error(s)"
    exit 1
  else
    log_ok "All configuration checks passed"
    echo ""
  fi
}

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
    sed -i 's/\(compileSdk \)[0-9][0-9]*safeExtGet([^)]*)/\1 34/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdkVersion 34safeExtGet(...)" -> "compileSdkVersion 34"
    sed -i 's/\(compileSdkVersion \)[0-9][0-9]*safeExtGet([^)]*)/\1 34/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdk 34= 36 // ..." -> "compileSdk 34"
    sed -i 's/\(compileSdk \)[0-9][0-9]*= [0-9][0-9]*.*/\1 34/g' "$gradle_file" 2>/dev/null || true
    # Fix: "compileSdkVersion 34= 36 // ..." -> "compileSdkVersion 34"
    sed -i 's/\(compileSdkVersion \)[0-9][0-9]*= [0-9][0-9]*.*/\1 34/g' "$gradle_file" 2>/dev/null || true
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

  # Replace jcenter() with mavenCentral() in all plugin build.gradle files
  # Gradle 9.x removed jcenter() support entirely
  log_info "Replacing jcenter() with mavenCentral() in plugin build.gradle files..."
  local JCENTER_LIST="/tmp/sectop_jcenter_$$.txt"
  find "$PUB_CACHE_DIR/hosted/pub.dev/" -name "build.gradle" 2>/dev/null > "$JCENTER_LIST" || true
  while read -r gradle_file; do
    [ -z "$gradle_file" ] && continue
    if grep -q "jcenter()" "$gradle_file" 2>/dev/null; then
      sed -i 's/jcenter()/mavenCentral()/g' "$gradle_file" 2>/dev/null || true
      log_info "  Replaced jcenter() in: $(basename "$(dirname "$gradle_file")")"
    fi
  done < "$JCENTER_LIST"
  rm -f "$JCENTER_LIST"
  log_ok "jcenter() replacement complete"

  # Fix flutter_local_notifications ambiguous bigLargeIcon(null) call
  # Newer Android SDKs added bigLargeIcon(Icon) alongside bigLargeIcon(Bitmap),
  # making a null argument ambiguous. Cast to Bitmap to resolve.
  log_info "Patching flutter_local_notifications ambiguous bigLargeIcon call..."
  local FLN_FILE="$PUB_CACHE_DIR/hosted/pub.dev/flutter_local_notifications-16.3.3/android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java"
  if [ -f "$FLN_FILE" ]; then
    if grep -q "bigPictureStyle.bigLargeIcon(null)" "$FLN_FILE" 2>/dev/null; then
      sed -i 's/bigPictureStyle\.bigLargeIcon(null)/bigPictureStyle.bigLargeIcon((Bitmap) null)/' "$FLN_FILE"
      log_info "  Patched bigLargeIcon(null) -> bigLargeIcon((Bitmap) null)"
    else
      log_info "  bigLargeIcon(null) not found (may already be patched)"
    fi
  else
    log_warn "  flutter_local_notifications plugin file not found at $FLN_FILE"
  fi

  # Fix workmanager v1 embedding → v2 embedding using Python script
  # workmanager 0.5.2 uses the old v1 Android embedding API (ShimPluginRegistry,
  # PluginRegistrantCallback, Registrar) which has been removed in Flutter 3.16+.
  # We patch the Kotlin source files to use v2 embedding.
  log_info "Patching workmanager plugin v1→v2 embedding..."
  local WM_DIR="$PUB_CACHE_DIR/hosted/pub.dev/workmanager-0.5.2/android/src/main/kotlin/dev/fluttercommunity/workmanager"
  if [ -d "$WM_DIR" ]; then
    python3 "$SCRIPT_DIR/patch-workmanager-v2-embedding.py" "$WM_DIR"
    if [ $? -eq 0 ]; then
      log_ok "Workmanager plugin patched successfully"
    else
      log_warn "Workmanager plugin patching may have issues"
    fi
  else
    log_warn "  workmanager plugin directory not found at $WM_DIR"
  fi

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

  # Delete corrupted workmanager plugin files from pub cache so they get
  # re-downloaded fresh by flutter pub get, then patched correctly.
  local PUB_CACHE_DIR
  if [ -n "${PUB_CACHE:-}" ]; then
    PUB_CACHE_DIR="$PUB_CACHE"
  else
    PUB_CACHE_DIR="/root/.pub-cache"
  fi
  local WM_CACHE_DIR="$PUB_CACHE_DIR/hosted/pub.dev/workmanager-0.5.2"
  if [ -d "$WM_CACHE_DIR" ]; then
    log_info "Removing cached workmanager plugin for fresh download..."
    rm -rf "$WM_CACHE_DIR"
    log_ok "Workmanager cache cleared"
  fi

  # Get dependencies
  flutter pub get

  # Ensure local.properties exists with correct SDK path
  log_info "Ensuring local.properties is configured..."
  echo "sdk.dir=$ANDROID_SDK_ROOT" > "$FRONTEND_DIR/android/local.properties"
  echo "flutter.sdk=$(dirname "$(dirname "$(which flutter)")")" >> "$FRONTEND_DIR/android/local.properties"

  # Patch plugins for compatibility
  patch_plugins

  # Re-apply memory settings (Flutter Gradle plugin may have overwritten gradle.properties)
  log_info "Re-applying Gradle memory settings..."
  cat > "$FRONTEND_DIR/android/gradle.properties" << 'GRADLEPROPS'
android.useAndroidX=true
android.enableJetifier=false
org.gradle.caching=true
org.gradle.configureondemand=false
# Memory settings for low-RAM build servers
org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m
kotlin.daemon.jvmargs=-Xmx384m
org.gradle.parallel=false
org.gradle.daemon=false
GRADLEPROPS
  log_ok "Gradle memory settings re-applied"

  # Clean previous build artifacts (delete directly instead of using ./gradlew clean
  # to avoid triggering Gradle daemon issues)
  log_info "Cleaning previous build artifacts..."
  rm -rf "$FRONTEND_DIR/build/" "$FRONTEND_DIR/android/.gradle/" "$FRONTEND_DIR/android/app/build/" 2>/dev/null || true
  
  # Kill any lingering Gradle daemons that may hold cached memory from failed builds
  log_info "Stopping any running Gradle daemons..."
  pkill -9 -f "gradle" 2>/dev/null || true
  # Kill any lingering Kotlin daemons from previous failed builds
  # These may occupy the Kotlin daemon port and prevent new connections
  pkill -9 -f "kotlin-daemon" 2>/dev/null || true
  sleep 1
  
  # Only remove corrupted transform cache and Kotlin daemon port locks.
  # Do NOT clear the entire Gradle cache - that forces re-download of ALL
  # dependencies, which is extremely memory-intensive on low-RAM servers.
  log_info "Cleaning corrupted transforms and Kotlin daemon port locks..."
  rm -rf "$HOME/.gradle/caches/transforms-3/" 2>/dev/null || true
  # Remove Kotlin daemon port lock files from previous failed builds
  rm -f "$HOME/.gradle/daemon/"*"/kotlin-daemon-ports/"* 2>/dev/null || true
  rm -f "$HOME/.gradle/kotlin-daemon/"* 2>/dev/null || true

  # ── Gradle version workaround ──────────────────────────────────────────────
  # The Flutter SDK's Gradle plugin (included via settings.gradle) may override
  # gradle-wrapper.properties with an incorrect distribution URL pointing to a
  # non-existent Gradle version (e.g. 8.17.0 on github.com).
  #
  # We work around this by:
  #   1. Pre-downloading the correct Gradle 9.1.0 distribution so the wrapper
  #      finds it cached and skips the download even if the URL is wrong.
  #   2. Fixing the wrapper URL after Flutter overwrites it, so subsequent
  #      Gradle invocations use the correct URL.
  #
  # Step 1: Pre-cache Gradle 9.1.0 if not already cached
  local GRADLE_CACHE_DIR="$HOME/.gradle/wrapper/dists/gradle-9.1.0-all"
  if [ ! -d "$GRADLE_CACHE_DIR" ]; then
    log_info "Pre-caching Gradle 9.1.0 distribution..."
    mkdir -p "$GRADLE_CACHE_DIR" 2>/dev/null || true
    # Download Gradle 9.1.0 from the official distribution server
    GRADLE_URL="https://services.gradle.org/distributions/gradle-9.1.0-all.zip"
    GRADLE_ZIP="/tmp/gradle-9.1.0-all.zip"
    if command -v curl &>/dev/null; then
      curl -fsSL "$GRADLE_URL" -o "$GRADLE_ZIP" || true
    elif command -v wget &>/dev/null; then
      wget -q "$GRADLE_URL" -O "$GRADLE_ZIP" || true
    fi
    if [ -f "$GRADLE_ZIP" ] && [ -s "$GRADLE_ZIP" ]; then
      unzip -qo "$GRADLE_ZIP" -d "$GRADLE_CACHE_DIR/" 2>/dev/null || true
      rm -f "$GRADLE_ZIP"
      log_ok "Gradle 9.1.0 pre-cached successfully"
    else
      log_warn "Could not pre-download Gradle 9.1.0 (will try via wrapper)"
    fi
  else
    log_info "Gradle 9.1.0 already cached"
  fi

  # Step 2: Fix the wrapper URL (in case Flutter's Gradle plugin overwrote it)
  local WRAPPER_PROPS="$FRONTEND_DIR/android/gradle/wrapper/gradle-wrapper.properties"
  if [ -f "$WRAPPER_PROPS" ]; then
    sed -i 's|distributionUrl=.*|distributionUrl=https\\://services.gradle.org/distributions/gradle-9.1.0-all.zip|' "$WRAPPER_PROPS"
  fi

  # Build release APK (no tree-shake icons to ensure all Material icons are included)
  # Use --no-android-gradle-daemon to avoid daemon memory issues on low-RAM servers
  # First build may take longer due to Gradle download + dependency resolution
  # --android-skip-build-dependency-validation: Bypass Flutter's Kotlin version check.
  # Gradle JVM heap allocation: 1.5GB for transforming TensorFlow Lite + Flutter native libs
  # (JetifyTransform needs significant heap for large AAR/JAR conversions)
  # GC tuning: Use G1GC with aggressive collection to minimize peak heap usage
  export KOTLIN_DAEMON_JVM_OPTS="-Xmx384m"
  export GRADLE_OPTS="-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:+ParallelRefProcEnabled"
  flutter build apk --release --no-tree-shake-icons --android-skip-build-dependency-validation --no-android-gradle-daemon --no-android-lint -t lib/main.dart

  # Step 3: After Flutter build (which may have overwritten the wrapper), restore
  # the correct URL so any post-build Gradle tasks use the right version.
  if [ -f "$WRAPPER_PROPS" ]; then
    sed -i 's|distributionUrl=.*|distributionUrl=https\\://services.gradle.org/distributions/gradle-9.1.0-all.zip|' "$WRAPPER_PROPS"
  fi
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

  # Phase 0: Configuration validation (check environment before building)
  check_config

  # Phase 1: Build the APK
  build_apk

  log_ok "=== Build Complete ==="
  log_info "Install the APK on your device:"
  log_info "  adb install $OUTPUT_APK"
}

main "$@"
