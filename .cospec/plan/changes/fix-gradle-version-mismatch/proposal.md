# Change: Fix Gradle version mismatch causing APK build failure

## Rationale
The Android APK build fails because Gradle is trying to download version 8.17.0 from an incorrect URL (`github.com/gradle/gradle-distributions/releases/download/v8.17.0/gradle-8.17-all.zip`), which does not exist. The `gradle-wrapper.properties` specifies Gradle 8.14, but the Flutter SDK's Gradle plugin (included via `settings.gradle`) overrides this to a non-existent 8.17.0 on the wrong host.

## Root Cause
The Flutter SDK's Gradle plugin (from the snap-installed Flutter SDK at `/root/snap/flutter/common/flutter`) overrides the Gradle wrapper distribution URL during `flutter build apk` to point to `https://github.com/gradle/gradle-distributions/releases/download/v8.17.0/gradle-8.17-all.zip` — a version that does not exist on that host. The correct URL should be `https://services.gradle.org/distributions/gradle-8.14-all.zip`.

The build output confirms this: "Upgrading build.gradle" and "Upgrading gradle.properties" messages appear during `flutter build apk`, showing Flutter overwrites the wrapper configuration.

## Changes
1. **`frontend/android/gradle/wrapper/gradle-wrapper.properties`**: Verify the `distributionUrl` is set to the correct Gradle 8.14 URL (already correct).
2. **`deploy/scripts/build-android-apk.sh`**: 
   - Remove the cache-clearing `rm -rf ~/.gradle/caches/` and `rm -rf ~/.gradle/wrapper/dists/` commands that force re-download
   - Add pre-caching of Gradle 8.14 distribution so the wrapper finds it cached even if Flutter overrides the URL
   - Add wrapper URL fix before and after `flutter build apk` to ensure the correct URL is used
   - Update stale comments referencing Gradle 8.17

## Impact
- **Affected Specifications**: Android APK Build
- **Affected Code**:
  - `frontend/android/gradle/wrapper/gradle-wrapper.properties`: Verify correct URL (no change needed)
  - `deploy/scripts/build-android-apk.sh`: Add Gradle pre-caching and wrapper URL restoration
