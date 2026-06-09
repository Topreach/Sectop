# Change: Fix Gradle version mismatch causing APK build failure

## Rationale
The Android APK build fails because Gradle is trying to download version 8.17.0 from an incorrect URL (`github.com/gradle/gradle-distributions/releases/download/v8.17.0/gradle-8.17-all.zip`), which does not exist. The `gradle-wrapper.properties` specifies Gradle 8.14, but the Flutter SDK's Gradle plugin (included via `settings.gradle`) overrides this to a non-existent 8.17.0 on the wrong host.

## Root Cause
The `settings.gradle` at `frontend/android/settings.gradle` line 10 includes the Flutter Gradle plugin:
```groovy
includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
```
This Flutter Gradle plugin (from Flutter SDK) overrides the Gradle wrapper distribution URL to point to `https://github.com/gradle/gradle-distributions/releases/download/v8.17.0/gradle-8.17-all.zip` — a version that does not exist on that host. The correct URL should be `https://services.gradle.org/distributions/gradle-8.14-all.zip` (or whatever version the Flutter SDK actually requires).

## Changes
1. **`frontend/android/gradle/wrapper/gradle-wrapper.properties`**: Update `distributionUrl` to match the actual Gradle version required by the Flutter SDK (8.14) and ensure it points to the correct official Gradle distribution URL (`services.gradle.org`).
2. **`deploy/scripts/build-android-apk.sh`**: Update the comment on line 213 that references "Gradle 8.17" to reflect the correct version (8.14), and remove the cache-clearing steps (lines 214-216) that force re-download of Gradle on every build, since the wrapper URL is now correct.

## Impact
- **Affected Specifications**: Android APK Build
- **Affected Code**:
  - `frontend/android/gradle/wrapper/gradle-wrapper.properties`: Fix distribution URL to correct Gradle 8.14
  - `deploy/scripts/build-android-apk.sh`: Update stale comments and remove unnecessary cache clearing
