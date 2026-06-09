## Implementation

- [x] 1.4 Fix OfflineStorage race condition
     【Target Object】`frontend/lib/shared/services/offline_storage.dart` (lines 23-46)
     【Purpose】`initialize()` sets `_initialized = true` BEFORE the database is fully ready. The async gap between `getDatabasesPath()` and `openDatabase()` allows concurrent calls to proceed past the early-return guard, causing multiple database instances or operations on a null `_database`.
     【Method】Add a `Completer<void>` field `_initCompleter`. In `initialize()`: if `_initialized` return; if completer exists await it; otherwise create completer, do init work, complete it, then set `_initialized = true`. All CRUD methods should await `_initCompleter.future` before accessing `_database`.
     【Dependencies】None
     【Content】
        - Add field: `Completer<void>? _initCompleter;`
        - Modify `initialize()`:
          ```dart
          Future<void> initialize() async {
            if (_initialized) return;
            if (_initCompleter != null) return _initCompleter!.future;
            _initCompleter = Completer<void>();
            if (!kIsWeb) {
              try {
                final dbPath = await getDatabasesPath();
                final path = join(dbPath, AppConstants.dbName);
                _database = await openDatabase(
                  path,
                  version: AppConstants.dbVersion,
                  onCreate: _createTables,
                  onUpgrade: _upgradeTables,
                );
              } catch (e, stack) {
                debugPrint('OfflineStorageService: DB init failed (non-fatal): $e\n$stack');
                _database = null;
              }
            }
            _initialized = true;
            _initCompleter!.complete();
          }
          ```
        - Add await guard at start of `insert`, `update`, `delete`, `query`, `getById`, `upsert`:
          ```dart
          if (!_initialized) await _initCompleter?.future;
          ```

- [x] 2.1 Add retry logic with exponential backoff to BackendApi
     【Target Object】`frontend/lib/shared/services/backend_api.dart` (lines 40-86)
     【Purpose】All HTTP methods make a single attempt with no retry logic. Transient network failures cause immediate errors.
     【Method】Add a `_retryWithBackoff<T>(Future<T> Function() request)` wrapper that retries up to `apiRetryCount` times with exponential backoff (1s, 2s, 4s... capped at 10s). Wrap all HTTP calls (`get`, `post`, `put`, `delete`) in this retry logic.
     【Dependencies】None
     【Content】
        - Add import: `import 'dart:math';`
        - Add method:
          ```dart
          Future<T> _retryWithBackoff<T>(Future<T> Function() request) async {
            int attempt = 0;
            while (true) {
              try {
                return await request();
              } catch (e) {
                attempt++;
                if (attempt >= AppConstants.apiRetryCount) rethrow;
                final delay = Duration(seconds: min(pow(2, attempt).toInt(), 10));
                debugPrint('BackendApi: Retry $attempt/$apiRetryCount after $delay: $e');
                await Future.delayed(delay);
              }
            }
          }
          ```
        - Wrap each HTTP method body in `_retryWithBackoff(() async { ... })`

- [x] 2.2 Add circuit breaker pattern to BackendApi
     【Target Object】`frontend/lib/shared/services/backend_api.dart`
     【Purpose】No circuit breaker. When the backend is down, every request still attempts a connection, wasting battery and bandwidth.
     【Method】Add a simple circuit breaker with three states (CLOSED, OPEN, HALF_OPEN). Track consecutive failures. After `failureThreshold` (5), open the circuit for `resetTimeout` (30s). In OPEN state, throw immediately without network call.
     【Dependencies】2.1 (retry logic)
     【Content】
        - Add enum:
          ```dart
          enum CircuitState { closed, open, halfOpen }
          ```
        - Add fields:
          ```dart
          CircuitState _circuitState = CircuitState.closed;
          int _consecutiveFailures = 0;
          static const int _failureThreshold = 5;
          static const Duration _resetTimeout = Duration(seconds: 30);
          DateTime? _lastFailureTime;
          ```
        - Add method:
          ```dart
          Future<T> _executeWithCircuitBreaker<T>(Future<T> Function() request) async {
            if (_circuitState == CircuitState.open) {
              if (DateTime.now().difference(_lastFailureTime!) > _resetTimeout) {
                _circuitState = CircuitState.halfOpen;
              } else {
                throw ApiException(503, 'Circuit breaker open');
              }
            }
            try {
              final result = await _retryWithBackoff(request);
              _consecutiveFailures = 0;
              _circuitState = CircuitState.closed;
              return result;
            } catch (e) {
              _consecutiveFailures++;
              _lastFailureTime = DateTime.now();
              if (_consecutiveFailures >= _failureThreshold) {
                _circuitState = CircuitState.open;
              }
              rethrow;
            }
          }
          ```
        - Wrap each HTTP method body in `_executeWithCircuitBreaker(() async { ... })`

- [x] 3.1 Replace audit log List with Queue
     【Target Object】`frontend/lib/modules/security/services/security_manager.dart` (lines 34, 306-338)
     【Purpose】`_auditLog` is a `List<SecurityEvent>` with `removeRange(0, ...)` for trimming. `removeRange` on a List is O(n). With `_maxAuditLogSize = 1000`, this is wasteful.
     【Method】Replace `List<SecurityEvent>` with `dart:collection` `Queue<SecurityEvent>`. Use `add()` for O(1) append and `removeFirst()` for O(1) trim.
     【Dependencies】None
     【Content】
        - Add import: `import 'dart:collection';`
        - Change field: `final Queue<SecurityEvent> _auditLog = Queue<SecurityEvent>();`
        - Change `_logEvent` trim logic:
          ```dart
          _auditLog.add(event);
          while (_auditLog.length > _maxAuditLogSize) {
            _auditLog.removeFirst();
          }
          ```
        - Change getter:
          ```dart
          List<SecurityEvent> get auditLog => List.unmodifiable(_auditLog.toList());
          ```

- [x] 3.2 Optimize dashboard rebuilds with context.select
     【Target Object】`frontend/lib/modules/sos/screens/dashboard_screen.dart` (lines 74-76)
     【Purpose】`context.watch<SyncManager>()`, `context.watch<MeshManager>()`, and `context.watch<MapService>()` cause the entire `_DashboardHome` widget to rebuild whenever ANY property changes.
     【Method】Replace `context.watch<T>()` with `context.select<T, R>((T value) => value.<specificProperty>)` to subscribe only to specific properties.
     【Dependencies】None
     【Content】
        - Replace:
          ```dart
          final syncManager = context.watch<SyncManager>();
          final meshManager = context.watch<MeshManager>();
          final mapService = context.watch<MapService>();
          ```
        - With:
          ```dart
          final isOnline = context.select<SyncManager, bool>((s) => s.isOnline);
          final peerCount = context.select<MeshManager, int>((m) => m.discoveredPeers.length);
          final isTracking = context.select<MapService, bool>((m) => m.isTracking);
          ```
        - Update all references: `syncManager.isOnline` → `isOnline`, `meshManager.discoveredPeers.length` → `peerCount`, `mapService.isTracking` → `isTracking`
        - For `syncManager.triggerSync()` in `onRefresh`, keep a reference via `context.read<SyncManager>().triggerSync()`

- [x] 4.1 Add crash reporting stub
     【Target Object】`frontend/lib/main.dart` (around line 100) + new file `frontend/lib/shared/services/crash_reporter.dart`
     【Purpose】No crash reporting integration. Unhandled errors are caught by `runZonedGuarded` but only logged to console.
     【Method】Create a `CrashReporter` abstract class and `ConsoleCrashReporter` implementation. Integrate into `runZonedGuarded` and `FlutterError.onError`.
     【Dependencies】None
     【Content】
        - New file `frontend/lib/shared/services/crash_reporter.dart`:
          ```dart
          import 'package:flutter/foundation.dart';

          /// Abstract crash reporter interface.
          /// Replace ConsoleCrashReporter with SentryCrashReporter or FirebaseCrashlyticsReporter in production.
          abstract class CrashReporter {
            void recordError(dynamic exception, StackTrace stack, {String? context});
            void recordFlutterError(FlutterErrorDetails details);
          }

          /// Console-based crash reporter for development.
          class ConsoleCrashReporter implements CrashReporter {
            @override
            void recordError(dynamic exception, StackTrace stack, {String? context}) {
              debugPrint('══════════════════════════════════════════════════');
              debugPrint('⚠️ CRASH: $context');
              debugPrint('Exception: $exception');
              debugPrint('Stack: $stack');
              debugPrint('══════════════════════════════════════════════════');
              // TODO: Send to Sentry / Firebase Crashlytics:
              //   await Sentry.captureException(exception, stackTrace: stack);
            }

            @override
            void recordFlutterError(FlutterErrorDetails details) {
              debugPrint('══════════════════════════════════════════════════');
              debugPrint('⚠️ FLUTTER ERROR: ${details.exception}');
              debugPrint('Stack: ${details.stack}');
              debugPrint('══════════════════════════════════════════════════');
              // TODO: Send to Sentry / Firebase Crashlytics:
              //   await Sentry.captureException(details.exception, stackTrace: details.stack);
            }
          }
          ```
        - In `main.dart`, add import and integrate:
          ```dart
          import 'shared/services/crash_reporter.dart';
          
          final CrashReporter crashReporter = ConsoleCrashReporter();
          
          void main() async {
            FlutterError.onError = (details) {
              crashReporter.recordFlutterError(details);
            };
            runZonedGuarded(() async {
              // ... existing code ...
            }, (error, stack) {
              crashReporter.recordError(error, stack, context: 'runZonedGuarded');
            });
          }
          ```

- [x] 4.2 Add localization (i18n) stub
     【Target Object】New file `frontend/lib/core/localization.dart`
     【Purpose】No internationalization support. All strings are hardcoded in English.
     【Method】Create an `AppLocalizations` class with a `Map<String, Map<String, String>>` for supported locales. Add a `translate(String key)` method. Add TODO comments for `flutter_localizations` integration.
     【Dependencies】None
     【Content】
        - New file `frontend/lib/core/localization.dart`:
          ```dart
          import 'package:flutter/material.dart';

          /// Simple localization stub.
          /// TODO: Replace with flutter_localizations + ARB files for production:
          ///   - Add flutter_localizations to pubspec.yaml
          ///   - Generate .arb files in lib/l10n/
          ///   - Use AppLocalizations.of(context)!.translate('key')
          class AppLocalizations {
            final Locale locale;
            AppLocalizations(this.locale);

            static AppLocalizations of(BuildContext context) {
              return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
            }

            static const LocalizationsDelegate<AppLocalizations> delegate =
                _AppLocalizationsDelegate();

            static const Map<String, Map<String, String>> _localizedStrings = {
              'en': {
                'app_name': 'Danger Emergence',
                'send_sos': 'SEND SOS',
                'tap_emergency': 'Tap for emergency alert',
                'quick_actions': 'Quick Actions',
                'safe_zones': 'Safe Zones',
                'mesh_network': 'Mesh Network',
                'messages': 'Messages',
                'first_aid': 'First Aid',
                'system_status': 'System Status',
                'cloud_connection': 'Cloud Connection',
                'connected': 'Connected',
                'offline': 'Offline',
                'location_tracking': 'Location Tracking',
                'active': 'Active',
                'inactive': 'Inactive',
                'sync_status': 'Sync Status',
                'sos_active': 'SOS Active',
                'cancel': 'Cancel',
                'ok': 'OK',
                'error': 'Error',
                'loading': 'Loading...',
                'retry': 'Retry',
              },
            };

            String translate(String key) {
              return _localizedStrings[locale.languageCode]?[key] ?? key;
            }
          }

          class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
            const _AppLocalizationsDelegate();
            @override
            bool isSupported(Locale locale) => ['en'].contains(locale.languageCode);
            @override
            Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);
            @override
            bool shouldReload(_AppLocalizationsDelegate old) => false;
          }
          ```

- [x] 5.1 Add Result<T> error handling pattern
     【Target Object】New file `frontend/lib/shared/utils/result.dart`
     【Purpose】No consistent error handling pattern. Methods throw exceptions, return null, or use custom result classes inconsistently.
     【Method】Create a generic `Result<T>` class with `Success<T>` and `Failure<T>` subclasses. Add `fold<R>` method.
     【Dependencies】None
     【Content】
        - New file `frontend/lib/shared/utils/result.dart`:
          ```dart
          /// A generic Result type for consistent error handling.
          /// TODO: Migrate existing methods to return Result<T> instead of throwing or returning null.
          sealed class Result<T> {
            const Result();
            R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure);
          }

          final class Success<T> extends Result<T> {
            final T value;
            const Success(this.value);
            @override
            R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure) =>
                onSuccess(value);
          }

          final class Failure<T> extends Result<T> {
            final Exception error;
            const Failure(this.error);
            @override
            R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure) =>
                onFailure(error);
          }
          ```

- [x] 5.2 Extract magic strings to constants
     【Target Object】`frontend/lib/core/constants.dart` + `frontend/lib/shared/services/offline_storage.dart`
     【Purpose】Several files use hardcoded string literals instead of named constants.
     【Method】Add constants for table names, operation types, sync statuses, and alert statuses. Update `offline_storage.dart` to use these constants.
     【Dependencies】None
     【Content】
        - Add to `constants.dart`:
          ```dart
          // Table names
          static const String tableUsers = 'users';
          static const String tableMessages = 'messages';
          static const String tableSOSAlerts = 'sos_alerts';
          static const String tableZones = 'zones';
          static const String tableMeshPeers = 'mesh_peers';
          static const String tableIncidents = 'incidents';
          static const String tableResourceCache = 'resource_cache';
          static const String tableSyncLog = 'sync_log';

          // Sync operations
          static const String opCreate = 'create';
          static const String opUpdate = 'update';
          static const String opDelete = 'delete';

          // Sync statuses
          static const String syncPending = 'pending';
          static const String syncSynced = 'synced';
          static const String syncFailed = 'failed';
          static const String syncCompleted = 'completed';

          // Alert statuses
          static const String alertActive = 'active';
          static const String alertResolved = 'resolved';
          static const String alertAcknowledged = 'acknowledged';
          static const String alertExpired = 'expired';

          // Message sync states
          static const String msgSyncOffline = 'offline';
          static const String msgSyncPending = 'pending';
          static const String msgSyncSynced = 'synced';
          ```
        - Update `offline_storage.dart` to use these constants instead of hardcoded strings like `'pending'`, `'active'`, `'create'`, `'messages'`, `'sos_alerts'`, etc.

- [x] 6.1 Harden Docker environment variables
     【Target Object】`docker-compose.yml` (lines 7-9, 62-70, 91-93)
     【Purpose】Default passwords and secrets are hardcoded. If `.env` is missing, production runs with weak defaults.
     【Method】Remove all `:-default` fallback values for secrets. Make `DB_PASSWORD`, `JWT_SECRET` required without defaults.
     【Dependencies】None
     【Content】
        - Change `POSTGRES_PASSWORD: ${DB_PASSWORD:-postgres}` to `POSTGRES_PASSWORD: ${DB_PASSWORD}` (no default)
        - Change `DB_PASSWORD: ${DB_PASSWORD:-postgres}` to `DB_PASSWORD: ${DB_PASSWORD}`
        - Change `JWT_SECRET: ${JWT_SECRET:-d2Fybmkt...}` to `JWT_SECRET: ${JWT_SECRET}`
        - Change `MODEL_NAME: ${MODEL_NAME:-facebook/bart-large-mnli}` to `MODEL_NAME: ${MODEL_NAME:-facebook/bart-large-mnli}` (keep this one as it's not a secret)
        - Add comment above each secret: `# REQUIRED: Must be set in .env file`

- [x] 6.2 Add health checks for all services
     【Target Object】`docker-compose.yml`
     【Purpose】mosquitto, backend, ml-service, and nginx lack health checks.
     【Method】Add `healthcheck` blocks for each service.
     【Dependencies】None
     【Content】
        - Add to `mosquitto`:
          ```yaml
          healthcheck:
            test: ["CMD-SHELL", "mosquitto_sub -t '$SYS/#' -C 1 --quiet 2>/dev/null || exit 1"]
            interval: 15s
            timeout: 5s
            retries: 3
            start_period: 10s
          ```
        - Add to `backend`:
          ```yaml
          healthcheck:
            test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || curl --fail http://localhost:8080/actuator/health || exit 1"]
            interval: 30s
            timeout: 10s
            retries: 3
            start_period: 60s
          ```
        - Add to `ml-service`:
          ```yaml
          healthcheck:
            test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8000/health || curl --fail http://localhost:8000/health || exit 1"]
            interval: 30s
            timeout: 10s
            retries: 3
            start_period: 120s
          ```
        - Add to `nginx`:
          ```yaml
          healthcheck:
            test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost/health || exit 1"]
            interval: 15s
            timeout: 5s
            retries: 3
            start_period: 10s
          ```

- [x] 6.3 Add resource limits to Docker services
     【Target Object】`docker-compose.yml`
     【Purpose】No resource limits on any service. A memory leak could starve others.
     【Method】Add `deploy.resources.limits` for each service.
     【Dependencies】None
     【Content】
        - Add to each service block:
          ```yaml
          deploy:
            resources:
              limits:
                cpus: '0.5'
                memory: 512M
          ```
        - Specific limits per service:
          - postgres: cpus: '1.0', memory: 512M
          - redis: cpus: '0.5', memory: 256M
          - mosquitto: cpus: '0.25', memory: 128M
          - backend: cpus: '1.0', memory: 1G
          - ml-service: cpus: '2.0', memory: 2G
          - nginx: cpus: '0.25', memory: 128M
