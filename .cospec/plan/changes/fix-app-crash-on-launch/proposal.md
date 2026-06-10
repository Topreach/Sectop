# Change: Fix app crash on launch (white screen / immediate close)

## Rationale
The APK builds successfully (63MB, universal, release-signed) but crashes immediately on launch with a white screen then closes. On the emulator, Android shows "server package cannot be found" error. Investigation reveals 3 critical bugs that together cause the crash.

## Root Cause Analysis

### Bug 1: `_createFallback` missing `HardwareTriggerService` (CRITICAL - crash path)
**File**: `frontend/lib/main.dart:90-100`

`_createFallback<T>()` has 8 type checks but `safeInit` is called for **9 services**. If any service constructor throws synchronously, the catch block calls `_createFallback<HardwareTriggerService>()` which hits line 99 and throws `StateError('No fallback constructor for HardwareTriggerService')`. This `StateError` is **inside the catch block** of `safeInit` — there is no try-catch around the `_createFallback` call. This error propagates up through the Provider's `create` callback during `runApp()`, breaking the `MultiProvider` and causing a white screen.

While `HardwareTriggerService` constructor is unlikely to throw, the code is fragile — adding any new service to the Provider list without updating `_createFallback` will cause a crash.

### Bug 2: Signature check ALWAYS fails on release builds (HIGH - false compromise)
**File**: `frontend/lib/modules/security/services/app_integrity.dart:623-627`

`_getExpectedSignatureHash()` returns the hardcoded string `'expected_signature_hash'`. On a release build, `_getAndroidSignatureHash()` calls the MethodChannel `getSignatureHash` which returns the **real SHA-256 hash** of the APK signing certificate. These will NEVER match, causing the signature check to ALWAYS return `passed: false, severity: critical`.

This sets `_isCompromised = true` permanently, which:
- Shows a "Security Compromise Detected" banner
- Triggers incident response (key zeroization, cache clearing)
- Makes the app non-functional from a security standpoint

### Bug 3: Aggressive security checks cause false-positive compromise (HIGH)
**File**: `frontend/lib/modules/security/services/security_config.dart:171-183`

All security checks are enabled by default:
- `requireSSLPinning = true` (line 171)
- `detectDebugger = true` (line 177)
- `detectEmulator = true` (line 180)
- `detectRootedDevice = true` (line 183)
- `enableAutoIncidentResponse = true` (line 244)

On a real device, `_checkRootStatus()` checks for root binaries at paths like `/sbin/su`, `/system/bin/su`, etc. While these are wrapped in try-catch, the `_checkRepackage()` method (line 496-536) catches exceptions and returns `passed: false, severity: error`. Combined with the always-failing signature check, the app is permanently in "compromised" state.

## Changes
- **Fix 1**: Add `HardwareTriggerService` to `_createFallback` in `main.dart` — make the fallback generic using `Object` and runtime type checking to prevent future omissions
- **Fix 2**: Fix `_getExpectedSignatureHash()` in `app_integrity.dart` — skip the signature hash comparison when the expected hash is the placeholder (i.e., not yet configured), or embed the real expected hash
- **Fix 3**: Disable `enableAutoIncidentResponse` in `security_config.dart` to prevent false-positive incident response from making the app non-functional
- **Fix 4**: Disable `detectEmulator` and `detectRootedDevice` in `security_config.dart` to prevent false-positive compromise detection on legitimate devices

## Impact
- **Affected Specifications**: App initialization, Security subsystem
- **Affected Code**:
  - `frontend/lib/main.dart`: `_createFallback<T>()` method (lines 90-100) — add HardwareTriggerService fallback
  - `frontend/lib/modules/security/services/app_integrity.dart`: `_getExpectedSignatureHash()` (lines 623-627) — fix placeholder hash comparison
  - `frontend/lib/modules/security/services/security_config.dart`: Security check flags (lines 171-244) — disable aggressive checks that cause false positives
