# Disable Jetifier to Eliminate JetifyTransform OOM

## Problem
The build still fails with `Java heap space` during JetifyTransform of Flutter native JARs (x86_64_release, armeabi_v7a_release, arm64_v8a_release). The Flutter SDK's Gradle plugin overwrites `gradle.properties` during the build (prints "Upgrading gradle.properties"), resetting our memory settings.

## Root Cause
`android.enableJetifier=true` triggers JetifyTransform, which unpacks, scans, and repacks every dependency JAR/AAR to convert Android Support Library references to AndroidX. This is extremely memory-intensive for large JARs like Flutter's native libraries and TensorFlow Lite.

## Solution
Disable Jetifier. All dependencies already use AndroidX directly:
- kotlin-stdlib (Kotlin, not Android Support)
- core-ktx (AndroidX)
- appcompat (AndroidX)
- multidex (AndroidX)
- desugar_jdk_libs (not Android Support)
- security-crypto (AndroidX)
- biometric (AndroidX)
- play-services-location (Google Play Services)
- work-runtime-ktx (AndroidX)
- tensorflow-lite (not Android Support)

## Tasks

### Task 1: Disable Jetifier in gradle.properties
- **File**: `frontend/android/gradle.properties`
- **Change**: `android.enableJetifier=true` → `android.enableJetifier=false`

### Task 2: Update build script re-apply step
- **File**: `deploy/scripts/build-android-apk.sh`
- **Change**: In the heredoc that re-writes gradle.properties (lines 317-326), change `android.enableJetifier=true` to `android.enableJetifier=false`
