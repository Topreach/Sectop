# Fix Kotlin OOM During IR Lowering

## Problem
The APK build fails with `java.lang.OutOfMemoryError` during Kotlin IR lowering when compiling `integration_test` plugin's `build.gradle.kts`. The root cause is that `gradle.properties` has two conflicting `org.gradle.jvmargs` lines, with the effective value being only `-Xmx512m`, which is insufficient for Kotlin DSL script compilation.

## Tasks

### Task 1: Fix gradle.properties - Remove duplicate jvmargs, set appropriate heap
- **Files**: `frontend/android/gradle.properties`
- **Changes**:
  1. Remove the first `org.gradle.jvmargs` line (line 1: `-Xmx1536m -XX:+HeapDumpOnOutOfMemoryError -XX:MaxMetaspaceSize=256m`)
  2. Update the second `org.gradle.jvmargs` line (line 8) from `-Xmx512m -XX:MaxMetaspaceSize=256m` to `-Xmx1024m -XX:MaxMetaspaceSize=256m`
  3. Add `kotlin.daemon.jvmargs=-Xmx512m` to give the Kotlin compiler daemon its own heap allocation
  4. Keep `org.gradle.parallel=false` and `org.gradle.daemon=false` (low-RAM server)
- **Rationale**: Server has 2686MB available RAM. 1024MB for Gradle + 512MB for Kotlin daemon = 1536MB total, leaving ~1150MB for OS and other processes.
- **Status**: ✅ Completed

### Task 2: Update build script GRADLE_OPTS to match
- **Files**: `deploy/scripts/build-android-apk.sh`
- **Changes**:
  1. Update line 376: Change `GRADLE_OPTS="-Xmx1536m -XX:MaxMetaspaceSize=768m ..."` to `GRADLE_OPTS="-Xmx1024m -XX:MaxMetaspaceSize=256m -XX:+UseG1GC -XX:MaxGCPauseMillis=100"`
  2. Also add `KOTLIN_DAEMON_JVM_OPTS="-Xmx512m"` export alongside GRADLE_OPTS
- **Rationale**: The GRADLE_OPTS in the build script should match what gradle.properties sets, to avoid confusion. The Kotlin daemon JVM args need to be set as an environment variable.
- **Status**: ✅ Completed
