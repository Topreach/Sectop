# Fix Remaining Code Issues (Parts 1.4 + 2-6)

## Reason
A comprehensive deep code analysis identified multiple remaining issues beyond the 7 critical bugs already fixed. These include a race condition in OfflineStorage (Part 1.4), architectural issues with singletons and missing retry logic (Part 2), performance problems with audit logs and dashboard rebuilds (Part 3), missing features like crash reporting and i18n (Part 4), code quality issues with error handling and magic strings (Part 5), and Docker deployment hardening (Part 6).

## Changes

### 1.4 Fix OfflineStorage race condition
- **File:** `frontend/lib/shared/services/offline_storage.dart` (lines 23-46)
- **Issue:** `initialize()` sets `_initialized = true` BEFORE the database is fully ready. The async gap between `getDatabasesPath()` and `openDatabase()` allows concurrent calls to proceed past the early-return guard, causing multiple database instances or operations on a null `_database`.
- **Fix:** Use a `Completer<void>` to create a proper initialization barrier. Callers that invoke `initialize()` concurrently will await the same completer. Only set `_initialized = true` after the database is fully opened.

### 2.1 Add retry logic with exponential backoff to BackendApi
- **File:** `frontend/lib/shared/services/backend_api.dart` (lines 40-86)
- **Issue:** All HTTP methods (`get`, `post`, `put`, `delete`) make a single attempt with no retry logic. Transient network failures cause immediate errors.
- **Fix:** Add a `_retryWithBackoff()` wrapper that retries up to `apiRetryCount` times with exponential backoff (1s, 2s, 4s... capped at 10s). Wrap all HTTP calls in this retry logic.

### 2.2 Add circuit breaker pattern to BackendApi
- **File:** `frontend/lib/shared/services/backend_api.dart`
- **Issue:** No circuit breaker. When the backend is down, every request still attempts a connection, wasting battery and bandwidth.
- **Fix:** Add a simple circuit breaker with three states (CLOSED, OPEN, HALF_OPEN). Track consecutive failures. After `failureThreshold` (5), open the circuit for `resetTimeout` (30s). In OPEN state, throw immediately without network call.

### 3.1 Replace audit log List with Queue/circular buffer
- **File:** `frontend/lib/modules/security/services/security_manager.dart` (lines 34, 306-338)
- **Issue:** `_auditLog` is a `List<SecurityEvent>` with `removeRange(0, ...)` for trimming. `removeRange` on a List is O(n) because all remaining elements must be shifted. With `_maxAuditLogSize = 1000`, this is wasteful.
- **Fix:** Replace `List<SecurityEvent>` with `dart:collection` `Queue<SecurityEvent>`. Use `add()` for O(1) append and `removeFirst()` for O(1) trim. The `auditLog` getter converts to unmodifiable list.

### 3.2 Optimize dashboard rebuilds with context.select
- **File:** `frontend/lib/modules/sos/screens/dashboard_screen.dart` (lines 74-76)
- **Issue:** `context.watch<SyncManager>()`, `context.watch<MeshManager>()`, and `context.watch<MapService>()` cause the entire `_DashboardHome` widget to rebuild whenever ANY property of these services changes, even if the used properties (e.g., `isOnline`, `discoveredPeers.length`, `isTracking`) haven't changed.
- **Fix:** Replace `context.watch<T>()` with `context.select<T, R>((T value) => value.<specificProperty>)` to subscribe only to the specific properties used in the build method.

### 4.1 Add crash reporting stub
- **File:** `frontend/lib/main.dart` (around line 100)
- **Issue:** No crash reporting integration. Unhandled errors are caught by `runZonedGuarded` but only logged to console.
- **Fix:** Add a crash reporting stub with a `CrashReporter` interface and a `ConsoleCrashReporter` implementation. Integrate into `runZonedGuarded` and `FlutterError.onError`. Add TODO comments for Sentry/Firebase Crashlytics integration.

### 4.2 Add localization (i18n) stub
- **File:** `frontend/lib/core/` (new file `localization.dart`)
- **Issue:** No internationalization support. All strings are hardcoded in English.
- **Fix:** Create a `AppLocalizations` class with a `Map<String, Map<String, String>>` for supported locales. Add a `translate(String key)` method. Add TODO comments for `flutter_localizations` / ARB file integration. Wrap key user-facing strings in `AppLocalizations.of(context).translate(...)` calls.

### 5.1 Add Result<T> error handling pattern
- **File:** `frontend/lib/shared/utils/` (new file `result.dart`)
- **Issue:** No consistent error handling pattern. Methods throw exceptions, return null, or use custom result classes inconsistently.
- **Fix:** Create a generic `Result<T>` class with `Success<T>` and `Failure<T>` subclasses. Add `fold<R>(R onSuccess(T), R onFailure(Exception))` method. Add TODO comments for migrating existing methods.

### 5.2 Extract magic strings to constants
- **File:** `frontend/lib/core/constants.dart`
- **Issue:** Several files use hardcoded string literals instead of named constants.
- **Fix:** Audit and add constants for: table names (`TABLE_MESSAGES`, `TABLE_SOS_ALERTS`, etc.), operation types (`OP_CREATE`, `OP_UPDATE`, `OP_DELETE`), sync statuses (`SYNC_PENDING`, `SYNC_SYNCED`, `SYNC_FAILED`), and alert statuses (`ALERT_ACTIVE`, `ALERT_RESOLVED`). Update `offline_storage.dart` to use these constants.

### 6.1 Harden Docker environment variables
- **File:** `docker-compose.yml` (lines 7-9, 62-70, 91-93)
- **Issue:** Default passwords and secrets are hardcoded in the compose file: `POSTGRES_PASSWORD: ${DB_PASSWORD:-postgres}`, `JWT_SECRET: ${JWT_SECRET:-d2Fybmkt...}`. If `.env` is missing, production runs with weak defaults.
- **Fix:** Remove all `:-default` fallback values for secrets. Make `DB_PASSWORD`, `JWT_SECRET` required without defaults. Add a validation script that checks required env vars are set before starting.

### 6.2 Add health checks for all services
- **File:** `docker-compose.yml`
- **Issue:** `mosquitto`, `backend`, `ml-service`, and `nginx` lack health checks. Docker Compose cannot determine if they are truly healthy.
- **Fix:** Add `healthcheck` blocks for each service. For mosquitto: `mosquitto_sub -t '$SYS/#' -C 1`. For backend: `curl --fail http://localhost:8080/actuator/health`. For ml-service: `curl --fail http://localhost:8000/health`. For nginx: `curl --fail http://localhost/health`.

### 6.3 Add resource limits to Docker services
- **File:** `docker-compose.yml`
- **Issue:** No resource limits (`mem_limit`, `cpus`) on any service. A memory leak in any container could starve others.
- **Fix:** Add `deploy.resources.limits` for each service: postgres (512MB), redis (256MB), mosquitto (128MB), backend (1GB), ml-service (2GB), nginx (128MB).

## Impact
- **Reliability:** Race condition eliminated; retry logic handles transient failures; circuit breaker prevents cascading failures
- **Performance:** O(1) audit log trimming; reduced widget rebuilds
- **Maintainability:** Consistent error handling; constants instead of magic strings; localization ready
- **Production readiness:** Crash reporting stub; Docker hardening with health checks and resource limits
