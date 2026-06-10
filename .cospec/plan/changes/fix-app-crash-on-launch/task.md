## Implementation

- [x] 1.1 Fix `_createFallback` missing `HardwareTriggerService` in main.dart
     【Target Object】`frontend/lib/main.dart:90-100` — `_createFallback<T>()` method
     【Purpose】Prevent unhandled `StateError` crash when any service constructor throws synchronously during Provider creation. Currently `_createFallback` has 8 type checks but 9 services are created via `safeInit`. If `HardwareTriggerService` (or any future service) constructor throws, the catch block calls `_createFallback<HardwareTriggerService>()` which throws `StateError('No fallback constructor for HardwareTriggerService')` — this is UNCAUGHT and crashes the widget tree.
     【Method】Refactor `_createFallback<T>()` from fragile if-else chain to a `Map<Type, Object Function()>` registry pattern. Add `HardwareTriggerService` entry to the registry. This makes the fallback generic-safe so future additions to the Provider list automatically get fallback support without manual if-else updates.
     【Dependencies】`frontend/lib/shared/services/hardware_trigger_service.dart`
     【Content】
        - Define a static `Map<Type, Object Function()>` registry (e.g., `_fallbackRegistry`) mapping each service type to its fallback factory function
        - Populate the registry with all 9 service types: `AuthService`, `SOSService`, `SecurityManager`, `ObservabilityService`, `OfflineStorageService`, `SyncManager`, `MapService`, `BackendApi`, and `HardwareTriggerService`
        - Replace the if-else chain in `_createFallback<T>()` with a registry lookup: `return _fallbackRegistry[T]!() as T;`
        - If the registry lookup returns null (type not found), throw `StateError` as a safety net
        - Verify the import for `HardwareTriggerService` is already present (line 21 of main.dart)

- [x] 1.2 Fix signature check always failing on release builds
     【Target Object】`frontend/lib/modules/security/services/app_integrity.dart:623-627` — `_getExpectedSignatureHash()` method; also `_checkSignature()` method at lines 81-136 (specifically the comparison at line 100)
     【Purpose】The `_getExpectedSignatureHash()` returns hardcoded placeholder `'expected_signature_hash'` which never matches the real SHA-256 hash from the APK signing certificate. This causes the signature check to ALWAYS return `passed: false, severity: critical` on release builds, permanently marking the app as compromised.
     【Method】Change `_getExpectedSignatureHash()` return type to `String?` (nullable) and return `null` (meaning "not configured"). Update `_checkSignature()` to treat a null expected hash as "skip the comparison" (pass). This way the signature check only runs when a real expected hash is embedded during build.
     【Dependencies】None
     【Content】
        - Change `_getExpectedSignatureHash()` return type from `String` to `String?` — return `null` instead of `'expected_signature_hash'`
        - In `_checkSignature()`, before the `if (signatureHash != expectedHash)` comparison (line 100), add a null guard: if `expectedHash == null`, skip the comparison and return `IntegrityCheck(passed: true, ...)` with details "Signature check skipped — expected hash not configured"

- [x] 1.3 Disable aggressive security checks that cause false-positive compromise
     【Target Object】`frontend/lib/modules/security/services/security_config.dart:171-244` — `SecurityConfig` class static const fields
     【Purpose】Multiple security checks are enabled by default and cause false-positive compromise detection on legitimate devices. The `enableAutoIncidentResponse` flag triggers key zeroization and cache clearing when a false compromise is detected, making the app non-functional. The `detectEmulator` and `detectRootedDevice` checks can return false positives on real devices.
     【Method】Set `enableAutoIncidentResponse = false` to prevent automatic incident response actions. Set `detectEmulator = false` and `detectRootedDevice = false` to prevent false-positive compromise flags. Keep `detectDebugger = true` and `requireSSLPinning = true` as these are less likely to produce false positives.
     【Dependencies】None
     【Content】
        - Line 180: Change `detectEmulator = true` → `detectEmulator = false`
        - Line 183: Change `detectRootedDevice = true` → `detectRootedDevice = false`
        - Line 244: Change `enableAutoIncidentResponse = true` → `enableAutoIncidentResponse = false`

- [ ] 1.4 Rebuild APK and verify fix
     【Target Object】`deploy/scripts/build-android-apk.sh` — APK build script; manual device installation
     【Purpose】Rebuild the APK with all fixes applied and verify the app launches correctly on a device
     【Method】Commit all changes, run the build script on a Linux/macOS build server (not Windows cmd.exe), then download the APK and install on a physical Android device for verification
     【Dependencies】All above fixes (1.1, 1.2, 1.3)
     【Content】
        - Commit all changes to GitHub with descriptive commit message
        - On a Linux/macOS build server, run `bash deploy/scripts/build-android-apk.sh` to produce a release-signed APK
        - Download the generated APK and install on a physical Android device
        - Verify app launches successfully and shows the splash screen without white screen or immediate close
        - Verify no "Security Compromise Detected" banner appears on first launch
