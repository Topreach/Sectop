## Implementation
- [x] 1.1 Verify and confirm Gradle wrapper distribution URL is correct
     【Target Object】`frontend/android/gradle/wrapper/gradle-wrapper.properties`
     【Purpose】Ensure the Gradle distribution URL points to the correct official Gradle 8.14 release on services.gradle.org, preventing the build from attempting to download a non-existent version
     【Method】Verify the `distributionUrl` property value in the properties file
     【Dependencies】None
     【Content】
        - Read the `distributionUrl` property from the file
        - Confirm it is set to `https\://services.gradle.org/distributions/gradle-8.14-all.zip`
        - If the URL is incorrect (e.g., points to github.com or a different version), update it to the correct value above
        - Note: The root cause of the build failure is the Flutter Gradle plugin (included via `frontend/android/settings.gradle` line 10: `includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`) which overrides the distribution URL. This task ensures the wrapper file itself has the correct baseline URL so that when the Flutter plugin override is removed or fixed in the future, the wrapper provides the correct fallback.

- [x] 1.2 Update build script comments and remove unnecessary cache clearing
     【Target Object】`deploy/scripts/build-android-apk.sh` (lines 211-216)
     【Purpose】Remove the Gradle cache clearing steps that force re-download of Gradle on every build (wasting bandwidth and time), and update stale comments referencing Gradle 8.17 to reflect the correct version 8.14
     【Method】Modify lines 211-216 in the `build_apk` function or equivalent build section
     【Dependencies】None
     【Content】
        - Locate the comment block around lines 211-213 that references "Gradle 8.17" and "Flutter 3.44.1"
        - Update the comment text to reference "Gradle 8.14" instead of "Gradle 8.17"
        - Remove lines 214-216 which contain the `rm -rf ~/.gradle/caches/` and `rm -rf ~/.gradle/wrapper/dists/` commands
        - Keep the `log_info "Cleaning Gradle caches..."` line if it exists, or remove it along with the rm commands
        - Boundary case: If the file structure differs from expected (e.g., lines shifted due to prior edits), search for the exact patterns `rm -rf ~/.gradle/caches/` and `rm -rf ~/.gradle/wrapper/dists/` to locate the correct lines
        - Error handling: Use `2>/dev/null || true` pattern (already present) to silently handle non-existent directories; no additional error handling needed

- [x] 1.3 Add Gradle pre-caching and wrapper URL restoration to build script
     【Target Object】`deploy/scripts/build-android-apk.sh` (build_apk function)
     【Purpose】Work around the Flutter SDK Gradle plugin that overrides gradle-wrapper.properties with an incorrect distribution URL during build. Pre-cache Gradle 8.14 so the wrapper finds it cached even if the URL is wrong, and restore the correct URL before/after the Flutter build.
     【Method】Add pre-caching logic and sed-based URL restoration in the build_apk function
     【Dependencies】Task 1.2 (removed cache clearing)
     【Content】
        - Add pre-caching of Gradle 8.14 distribution before `flutter build apk`:
          - Check if `~/.gradle/wrapper/dists/gradle-8.14-all` exists
          - If not, download from `https://services.gradle.org/distributions/gradle-8.14-all.zip` using curl or wget
          - Unzip into the Gradle wrapper cache directory
        - Fix wrapper URL before `flutter build apk` (in case Flutter already overwrote it)
        - Fix wrapper URL after `flutter build apk` (in case Flutter overwrote it during build)
        - Use `2>/dev/null || true` pattern for error resilience
