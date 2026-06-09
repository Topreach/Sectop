# Fix JetifyTransform OOM - Increase Gradle Heap for TensorFlow Lite AAR

## Problem
After fixing the Kotlin IR lowering OOM, the build now fails with `Java heap space` during **JetifyTransform** of `tensorflow-lite-select-tf-ops-2.14.0.aar` and Flutter native JARs. The TensorFlow Lite AAR is very large (~100MB+), and the JetifyTransform needs significant heap to process it.

Additionally, the Flutter SDK's Gradle plugin **overwrites** `gradle.properties` during build (prints "Upgrading gradle.properties"), which resets our memory settings.

## Tasks

### Task 1: Increase Gradle heap to 1536m
- **Files**: `frontend/android/gradle.properties`
- **Change**: Update `org.gradle.jvmargs=-Xmx1024m` to `org.gradle.jvmargs=-Xmx1536m`
- **Rationale**: Server has 2669MB available RAM. Gradle 1536MB + Kotlin daemon 512MB = 2048MB total, leaving ~600MB for OS.

### Task 2: Re-apply gradle.properties after Flutter overwrites it
- **Files**: `deploy/scripts/build-android-apk.sh`
- **Change**: In `build_apk()`, after `flutter pub get` and before `flutter build apk`, add a step that re-writes gradle.properties with our memory settings. The Flutter Gradle plugin prints "Upgrading gradle.properties" which overwrites our file.
- **Add after line 312** (after `patch_plugins`):
```bash
  # Re-apply memory settings (Flutter Gradle plugin may have overwritten gradle.properties)
  log_info "Re-applying Gradle memory settings..."
  cat > "$FRONTEND_DIR/android/gradle.properties" << 'GRADLEPROPS'
android.useAndroidX=true
android.enableJetifier=true
org.gradle.caching=true
org.gradle.configureondemand=false
# Memory settings for low-RAM build servers
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=256m
kotlin.daemon.jvmargs=-Xmx512m
org.gradle.parallel=false
org.gradle.daemon=false
GRADLEPROPS
  log_ok "Gradle memory settings re-applied"
```
