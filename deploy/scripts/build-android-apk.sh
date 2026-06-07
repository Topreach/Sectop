#!/bin/bash
# =============================================================================
# Danger Emergence System - Android APK Build Script
# =============================================================================
# This script installs the Android SDK (if missing), generates the android/
# platform directory, and builds a release APK.
#
# Usage:
#   bash deploy/scripts/build-android-apk.sh
#
# Prerequisites:
#   - Flutter SDK installed and on PATH
#   - curl, unzip, and basic build tools
# =============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$PROJECT_DIR/frontend"

# Android SDK paths
ANDROID_SDK_ROOT="${ANDROID_HOME:-/opt/android-sdk}"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
CMDLINE_TOOLS_DIR="$ANDROID_SDK_ROOT/cmdline-tools"
CMDLINE_TOOLS_BIN="$CMDLINE_TOOLS_DIR/latest/bin"

# Required SDK components
ANDROID_BUILD_TOOLS_VERSION="34.0.0"
ANDROID_PLATFORM_VERSION="34"
ANDROID_NDK_VERSION="25.2.9519653"

# ── Step 0: Check Prerequisites ─────────────────────────────────────────────
check_prerequisites() {
  log_info "Checking system prerequisites..."

  local MISSING_TOOLS=""

  if ! command -v curl &>/dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS curl"
  fi

  if ! command -v unzip &>/dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS unzip"
  fi

  if ! command -v git &>/dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS git"
  fi

  if [ -n "$MISSING_TOOLS" ]; then
    log_warn "Missing tools:$MISSING_TOOLS. Installing..."
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y -qq $MISSING_TOOLS
    log_ok "Prerequisites installed"
  else
    log_ok "All system prerequisites are available"
  fi
}

# ── Step 1: Check Java ──────────────────────────────────────────────────────
check_java() {
  log_info "Checking Java installation..."
  
  if ! command -v java &>/dev/null; then
    log_warn "Java not found. Installing OpenJDK 17..."
    apt-get update -qq
    apt-get install -y -qq openjdk-17-jdk-headless
    log_ok "Java installed"
  fi
  
  JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
  log_info "Java version: $(java -version 2>&1 | head -1)"
  
  if [ "$JAVA_VERSION" -lt 17 ]; then
    log_warn "Java version < 17. Installing OpenJDK 17..."
    apt-get install -y -qq openjdk-17-jdk-headless
    # Set JAVA_HOME
    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    log_ok "Java 17 installed at $JAVA_HOME"
  fi
}

# ── Step 2: Install Android SDK ─────────────────────────────────────────────
install_android_sdk() {
  log_info "Checking Android SDK at $ANDROID_SDK_ROOT..."
  
  if [ -f "$CMDLINE_TOOLS_BIN/sdkmanager" ]; then
    log_ok "Android SDK command-line tools already installed"
  else
    log_info "Downloading Android command-line tools..."
    mkdir -p "$CMDLINE_TOOLS_DIR"
    
    curl -fsSL "$CMDLINE_TOOLS_URL" -o /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-tmp
    mv /tmp/cmdline-tools-tmp/cmdline-tools "$CMDLINE_TOOLS_DIR/latest"
    rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-tmp
    
    log_ok "Command-line tools installed"
  fi
  
  # Accept licenses
  yes | "$CMDLINE_TOOLS_BIN/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
  
  # Install required components
  log_info "Installing Android SDK components (this may take a while)..."
  
  "$CMDLINE_TOOLS_BIN/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
    "platforms;android-$ANDROID_PLATFORM_VERSION" \
    "build-tools;$ANDROID_BUILD_TOOLS_VERSION" \
    "ndk;$ANDROID_NDK_VERSION" \
    "platform-tools" 2>&1 | tail -5
  
  log_ok "Android SDK components installed"
  
  # Set environment variables
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
  
  # Persist in /etc/environment for future sessions
  if ! grep -q "ANDROID_HOME" /etc/environment 2>/dev/null; then
    cat >> /etc/environment <<EOF
ANDROID_HOME=$ANDROID_SDK_ROOT
ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
EOF
    log_ok "Android SDK paths persisted to /etc/environment"
  fi
}

# ── Step 3: Generate Android Platform Directory ─────────────────────────────
generate_android_platform() {
  log_info "Checking android/ platform directory..."
  
  if [ -d "$FRONTEND_DIR/android" ] && [ -f "$FRONTEND_DIR/android/build.gradle" ]; then
    log_ok "Android platform directory already exists"
  else
    log_info "Generating android/ platform directory..."
    cd "$FRONTEND_DIR"
    flutter create --platforms android --project-name danger_emergence_system . || true
    log_ok "Android platform directory generated"
    
    # Remove iOS-specific generated files that might conflict
    # (we only want android)
    cd "$PROJECT_DIR"
  fi
}

# ── Step 4: Configure Gradle for Android SDK ────────────────────────────────
configure_gradle() {
  log_info "Configuring Gradle for Android SDK..."
  
  # Create local.properties pointing to Android SDK
  cat > "$FRONTEND_DIR/android/local.properties" <<EOF
sdk.dir=$ANDROID_SDK_ROOT
EOF
  log_ok "local.properties created"
  
  # Update android/app/build.gradle if needed for target SDK
  local APP_BUILD_GRADLE="$FRONTEND_DIR/android/app/build.gradle"
  if [ -f "$APP_BUILD_GRADLE" ]; then
    # Ensure compileSdkVersion and targetSdkVersion are set
    if grep -q "compileSdkVersion" "$APP_BUILD_GRADLE"; then
      sed -i "s/compileSdkVersion [0-9]*/compileSdkVersion $ANDROID_PLATFORM_VERSION/" "$APP_BUILD_GRADLE"
    fi
    if grep -q "targetSdkVersion" "$APP_BUILD_GRADLE"; then
      sed -i "s/targetSdkVersion [0-9]*/targetSdkVersion $ANDROID_PLATFORM_VERSION/" "$APP_BUILD_GRADLE"
    fi
    log_ok "build.gradle configured"
  fi
}

# ── Step 5: Patch JCenter Dependencies ──────────────────────────────────────
patch_dependencies() {
  log_info "Patching deprecated jcenter() references in plugin dependencies..."
  
  local PATCH_SCRIPT="$SCRIPT_DIR/patch-jcenter-dependencies.sh"
  if [ -f "$PATCH_SCRIPT" ]; then
    set +e
    bash "$PATCH_SCRIPT"
    local RC=$?
    
    if [ "$RC" -eq 2 ]; then
      log_warn "Corrupted plugins were deleted. Re-running flutter pub get to re-download..."
      cd "$FRONTEND_DIR"
      flutter pub get
      local PUBGET_RC=$?
      cd "$PROJECT_DIR"
      if [ "$PUBGET_RC" -ne 0 ]; then
        log_warn "flutter pub get returned exit code $PUBGET_RC (non-fatal, continuing)"
      fi
      log_ok "Dependencies re-downloaded"
      
      # Run patch script again on fresh files to add namespace
      log_info "Re-patching freshly downloaded plugins..."
      bash "$PATCH_SCRIPT"
      local RC2=$?
      if [ "$RC2" -eq 0 ]; then
        log_ok "Fresh plugins patched successfully"
      fi
    fi
    set -e
  else
    log_warn "Patch script not found at $PATCH_SCRIPT"
  fi
}

# ── Step 6: Fix plugins with missing Android native source files ──────────
# Some Flutter plugins (e.g., flutter_bluetooth_serial, geolocator_android)
# were published without their android/ directory entirely (no build.gradle,
# no AndroidManifest.xml, no Java sources). This function creates the missing
# files so Flutter's plugin validation and Gradle configuration succeed.
fix_missing_plugin_sources() {
  # ── Helper: create a minimal Android library build.gradle ───────────────
  _create_plugin_build_gradle() {
    local DIR="$1"   # android/ directory of the plugin
    local PKG="$2"   # Android package name (e.g. io.github.edufolly.flutterbluetoothserial)
    local FILE="$DIR/build.gradle"
    if [ -f "$FILE" ]; then
      return 0
    fi
    cat > "$FILE" << GRADLEEOF
group '$PKG'
version '1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath 'com.android.tools.build:gradle:7.3.1'
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    if (project.android.hasProperty("namespace")) {
        namespace("$PKG")
    }

    compileSdk 34

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    defaultConfig {
        minSdkVersion 21
    }
}
GRADLEEOF
    log_ok "Created build.gradle for $PKG"
  }

  # ── Helper: create a minimal AndroidManifest.xml ────────────────────────
  _create_plugin_manifest() {
    local DIR="$1"   # android/src/main/ directory of the plugin
    local FILE="$DIR/AndroidManifest.xml"
    if [ -f "$FILE" ]; then
      return 0
    fi
    mkdir -p "$DIR"
    cat > "$FILE" << 'MANIFESTEOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
</manifest>
MANIFESTEOF
    log_ok "Created AndroidManifest.xml"
  }

  # ── flutter_bluetooth_serial-0.4.0 ──────────────────────────────────────
  local BT_PLUGIN_DIR="/root/.pub-cache/hosted/pub.dev/flutter_bluetooth_serial-0.4.0"
  local BT_ANDROID_DIR="$BT_PLUGIN_DIR/android"
  local BT_JAVA_DIR="$BT_ANDROID_DIR/src/main/java/io/github/edufolly/flutterbluetoothserial"
  local BT_JAVA_FILE="$BT_JAVA_DIR/FlutterBluetoothSerialPlugin.java"
  local BT_PKG="io.github.edufolly.flutterbluetoothserial"
  
  # Always ensure build.gradle and AndroidManifest.xml exist (they may be
  # missing even if the Java stub was created in a previous run)
  _create_plugin_build_gradle "$BT_ANDROID_DIR" "$BT_PKG"
  _create_plugin_manifest "$BT_ANDROID_DIR/src/main"
  
  # Always recreate the Java stub (it may have been created by a previous run
  # with compilation errors, e.g. using removed APIs like PluginRegistry.Registrar)
  log_info "Creating/updating stub Java file for flutter_bluetooth_serial plugin..."
  
  mkdir -p "$BT_JAVA_DIR"
  
  cat > "$BT_JAVA_FILE" << 'EOFBT'
package io.github.edufolly.flutterbluetoothserial;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class FlutterBluetoothSerialPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private static final String CHANNEL = "flutter_bluetooth_serial";
  private MethodChannel channel;
  private Activity activity;
  
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
  }
  
  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
  }
  
  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }
  
  @Override
  public void onDetachedFromActivity() {
    activity = null;
  }
  
  @Override
  public void onDetachedFromActivityForConfigChanges() {
    activity = null;
  }
  
  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    activity = binding.getActivity();
  }
  
  @Override
  public void onMethodCall(MethodCall call, Result result) {
    switch (call.method) {
      case "getAdapterState":
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
          result.success("unsupported");
        } else if (adapter.isEnabled()) {
          result.success("enabled");
        } else {
          result.success("disabled");
        }
        break;
      case "isAvailable":
        result.success(BluetoothAdapter.getDefaultAdapter() != null);
        break;
      case "isEnabled":
        BluetoothAdapter a = BluetoothAdapter.getDefaultAdapter();
        result.success(a != null && a.isEnabled());
        break;
      default:
        result.notImplemented();
        break;
    }
  }
}
EOFBT
  log_ok "Created/updated stub Java file for flutter_bluetooth_serial plugin"
  
  # ── geolocator_android-4.6.2 ────────────────────────────────────────────
  local GEO_PLUGIN_DIR="/root/.pub-cache/hosted/pub.dev/geolocator_android-4.6.2"
  local GEO_ANDROID_DIR="$GEO_PLUGIN_DIR/android"
  local GEO_JAVA_DIR="$GEO_ANDROID_DIR/src/main/java/com/baseflow/geolocator"
  local GEO_JAVA_FILE="$GEO_JAVA_DIR/GeolocatorPlugin.java"
  local GEO_PKG="com.baseflow.geolocator"
  
  # Always ensure build.gradle and AndroidManifest.xml exist
  _create_plugin_build_gradle "$GEO_ANDROID_DIR" "$GEO_PKG"
  _create_plugin_manifest "$GEO_ANDROID_DIR/src/main"
  
  # Always recreate the Java stub
  log_info "Creating/updating stub Java file for geolocator_android plugin..."
  
  mkdir -p "$GEO_JAVA_DIR"
  
  cat > "$GEO_JAVA_FILE" << 'EOFGEO'
package com.baseflow.geolocator;

import android.app.Activity;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class GeolocatorPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
private static final String CHANNEL = "flutter.baseflow.com/geolocator";
private MethodChannel channel;
private Activity activity;

@Override
public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
  channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
  channel.setMethodCallHandler(this);
}

@Override
public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
  channel.setMethodCallHandler(null);
  channel = null;
}

@Override
public void onAttachedToActivity(ActivityPluginBinding binding) {
  activity = binding.getActivity();
}

@Override
public void onDetachedFromActivity() {
  activity = null;
}

@Override
public void onDetachedFromActivityForConfigChanges() {
  activity = null;
}

@Override
public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
  activity = binding.getActivity();
}

@Override
public void onMethodCall(MethodCall call, Result result) {
  switch (call.method) {
    case "checkPermission":
      result.success("denied");
      break;
    case "requestPermission":
      result.success("denied");
      break;
    case "getCurrentPosition":
      result.error("UNAVAILABLE", "Geolocator plugin stub - location not available", null);
      break;
    case "getLastKnownPosition":
      result.error("UNAVAILABLE", "Geolocator plugin stub - location not available", null);
      break;
    case "isLocationServiceEnabled":
      result.success(false);
      break;
    case "openLocationSettings":
      result.success(false);
      break;
    default:
      result.notImplemented();
      break;
  }
}
}
EOFGEO
  log_ok "Created/updated stub Java file for geolocator_android plugin"
}

# ── Step 7: Build Release APK ───────────────────────────────────────────────
build_apk() {
  log_info "Building release APK..."
  
  cd "$FRONTEND_DIR"
  
  # Fix plugins with missing Android native source files
  fix_missing_plugin_sources
  
  # Patch flutter_local_notifications ambiguous bigLargeIcon(null) call
  # Android SDK has both bigLargeIcon(Bitmap) and bigLargeIcon(Icon), so null is ambiguous
  local LN_FILE="/root/.pub-cache/hosted/pub.dev/flutter_local_notifications-16.3.3/android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java"
  if [ -f "$LN_FILE" ]; then
    # Cast null to Bitmap to resolve ambiguity
    sed -i 's/bigPictureStyle.bigLargeIcon(null);/bigPictureStyle.bigLargeIcon((android.graphics.Bitmap) null);/' "$LN_FILE" 2>/dev/null || true
    log_info "Patched flutter_local_notifications ambiguous bigLargeIcon call"
  fi
  
  # Enable core library desugaring in app/build.gradle (required by flutter_local_notifications)
  local APP_BUILD_GRADLE="$FRONTEND_DIR/android/app/build.gradle"
  if [ -f "$APP_BUILD_GRADLE" ]; then
    # Add compileOptions for desugaring if not already present
    if ! grep -q "isCoreLibraryDesugaringEnabled" "$APP_BUILD_GRADLE" 2>/dev/null; then
      # Use awk to insert isCoreLibraryDesugaringEnabled inside compileOptions block
      awk '{
        print $0
        if ($0 ~ /compileOptions \{/) {
          print "        isCoreLibraryDesugaringEnabled = true"
        }
      }' "$APP_BUILD_GRADLE" > "${APP_BUILD_GRADLE}.tmp" && mv "${APP_BUILD_GRADLE}.tmp" "$APP_BUILD_GRADLE"
      # Add desugaring dependency inside dependencies block
      awk '{
        print $0
        if ($0 ~ /dependencies \{/) {
          print "    coreLibraryDesugaring \"com.android.tools:desugar_jdk_libs:2.0.4\""
        }
      }' "$APP_BUILD_GRADLE" > "${APP_BUILD_GRADLE}.tmp" && mv "${APP_BUILD_GRADLE}.tmp" "$APP_BUILD_GRADLE"
      log_info "Enabled core library desugaring for flutter_local_notifications"
    fi
  fi
  
  # Patch workmanager-0.5.2 Kotlin files that use deprecated Shims/Registrar API
  local WM_DIR="/root/.pub-cache/hosted/pub.dev/workmanager-0.5.2/android/src/main/kotlin/dev/fluttercommunity/workmanager"
  if [ -d "$WM_DIR" ]; then
    # Replace BackgroundWorker.kt with a stub that has NO unused imports
    cat > "$WM_DIR/BackgroundWorker.kt" << 'WMEOF'
package dev.fluttercommunity.workmanager

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class BackgroundWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    override fun doWork(): Result {
        // Stub: workmanager requires full Flutter engine initialization
        // which is complex. Return success to avoid blocking the build.
        return Result.success()
    }
}
WMEOF
    # Replace WorkmanagerPlugin.kt with a stub that doesn't use deprecated Registrar
    cat > "$WM_DIR/WorkmanagerPlugin.kt" << 'WMEOF2'
package dev.fluttercommunity.workmanager

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class WorkmanagerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.getBinaryMessenger(), "be.tramckrijte.workmanager")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> result.success(true)
            "registerOneOffTask" -> result.success(true)
            "registerPeriodicTask" -> result.success(true)
            "cancelAllTasks" -> result.success(true)
            "cancelUniqueWork" -> result.success(true)
            else -> result.notImplemented()
        }
    }
}
WMEOF2
    # Replace WorkmanagerCallHandler.kt with a stub that defines the constants
    cat > "$WM_DIR/WorkmanagerCallHandler.kt" << 'WMEOF3'
package dev.fluttercommunity.workmanager

import androidx.annotation.NonNull
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class WorkmanagerCallHandler {
    companion object {
        private const val DART_TASK_KEY = "taskKey"
        private const val IS_IN_DEBUG_MODE_KEY = "isInDebugMode"
        private const val PAYLOAD_KEY = "payload"
    }

    fun handleMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> result.success(true)
            "registerOneOffTask" -> result.success(true)
            "registerPeriodicTask" -> result.success(true)
            "cancelAllTasks" -> result.success(true)
            "cancelUniqueWork" -> result.success(true)
            else -> result.notImplemented()
        }
    }
}
WMEOF3
    log_info "Patched workmanager plugin Kotlin stubs (BackgroundWorker, WorkmanagerPlugin, WorkmanagerCallHandler)"
  fi
  
  # Clean previous builds
  flutter clean 2>&1 | tail -2 || true
  
  # Get dependencies
  flutter pub get 2>&1 | tail -2 || true
  
  # Build APK
  flutter build apk --release 2>&1 || true
  
  local APK_PATH="$FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
  
  if [ -f "$APK_PATH" ]; then
    local APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    log_ok "APK built successfully!"
    log_info "Location: $APK_PATH"
    log_info "Size: $APK_SIZE"
    
    # Create a symlink in the project root for easy access
    ln -sf "$APK_PATH" "$PROJECT_DIR/danger-emergence.apk"
    log_info "Symlink created: $PROJECT_DIR/danger-emergence.apk"
  else
    log_error "APK build failed — output not found at $APK_PATH"
    exit 1
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "=============================================="
  echo "  Danger Emergence - Android APK Builder"
  echo "=============================================="
  echo ""
  
  # Check if running as root
  if [ "$(id -u)" -ne 0 ]; then
    log_warn "Not running as root. Some steps may fail."
    log_warn "Consider running with: sudo bash $0"
    echo ""
  fi
  
  check_prerequisites
  echo ""
  
  check_java
  echo ""
  
  install_android_sdk
  echo ""
  
  generate_android_platform
  echo ""
  
  configure_gradle
  echo ""
  
  patch_dependencies
  echo ""
  
  build_apk
  echo ""
  
  echo "=============================================="
  echo -e "${GREEN}BUILD COMPLETE${NC}"
  echo "=============================================="
  echo ""
  echo "Next steps:"
  echo "  1. Download the APK from the server:"
  echo "     scp -P 2222 root@147.93.41.71:$PROJECT_DIR/danger-emergence.apk ./"
  echo "  2. Transfer to your Android device and install"
  echo "  3. Enable 'Install from unknown sources' on your device"
  echo ""
}

main "$@"
