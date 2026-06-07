import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'core/constants.dart';
import 'core/themes.dart';
import 'core/routes.dart';
import 'shared/services/offline_storage.dart';
import 'shared/services/sync_manager.dart';
import 'shared/services/service_health.dart';
import 'shared/services/backend_api.dart';
import 'shared/widgets/responsive_layout.dart';
import 'shared/widgets/degraded_mode_banner.dart';
import 'modules/auth/services/auth_service.dart';
import 'modules/sos/services/sos_service.dart';
import 'modules/maps/services/map_service.dart';
import 'modules/security/services/security_manager.dart';
import 'modules/observability/services/observability_service.dart';
import 'shared/services/hardware_trigger_service.dart';

/// Background task dispatcher for Workmanager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // This runs in a background isolate.
    // Initialize storage first as SyncManager depends on it.
    final storage = OfflineStorageService();
    await storage.initialize();

    final syncManager = SyncManager();
    await syncManager.initialize();

    final success = await syncManager.triggerSync();
    return Future.value(success);
  });
}

/// Global service health monitor — tracks which services are degraded.
final ServiceHealthNotifier serviceHealth = ServiceHealthNotifier();

/// Helper that wraps a service creation + initialization call in a try-catch.
/// Catches both synchronous throws AND async (Future) rejections by chaining
/// `.catchError()` on the returned Future. The Provider's `create` callback
/// never throws — preventing the entire widget tree from collapsing.
///
/// The service instance is still returned (partially initialized), so
/// `context.watch<T>()` and `Provider.of<T>()` continue to work without
/// throwing `ProviderNotFoundException`.
///
/// Also reports the failure to [ServiceHealthNotifier] so the UI can show
/// a "Degraded Mode" banner to the user.
T safeInit<T>(T Function() create) {
  try {
    final instance = create();
    serviceHealth.registerService(T);

    // If the created instance has an async initialize() method, catch
    // any Future rejections so they don't become unhandled errors.
    if (instance is dynamic && instance.initialize is Function) {
      final future = instance.initialize() as Future?;
      if (future != null) {
        future.catchError((Object e, StackTrace stack) {
          debugPrint('══════════════════════════════════════════════════');
          debugPrint('⚠️ safeInit caught async error for $T: $e');
          debugPrint('Stack: $stack');
          debugPrint('══════════════════════════════════════════════════');
          serviceHealth.markDegraded(T, 'Async init failed: $e');
        });
      }
    }

    return instance;
  } catch (e, stack) {
    debugPrint('══════════════════════════════════════════════════');
    debugPrint('⚠️ safeInit caught sync error for $T: $e');
    debugPrint('Stack: $stack');
    debugPrint('══════════════════════════════════════════════════');
    serviceHealth.markDegraded(T, 'Initialization failed: $e');
    return _createFallback<T>();
  }
}

/// Creates a fallback instance for a service type when initialization fails.
T _createFallback<T>() {
  if (T == AuthService) return AuthService() as T;
  if (T == SOSService) return SOSService() as T;
  if (T == SecurityManager) return SecurityManager.instance as T;
  if (T == ObservabilityService) return ObservabilityService.instance as T;
  if (T == OfflineStorageService) return OfflineStorageService() as T;
  if (T == SyncManager) return SyncManager() as T;
  if (T == MapService) return MapService() as T;
  if (T == BackendApi) return BackendApi() as T;
  throw StateError('No fallback constructor for $T');
}

void main() async {
  // Capture all unhandled errors globally so they don't crash the app silently.
  runZonedGuarded(() async {
    FlutterError.onError = (details) {
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🚨 FlutterError caught: ${details.exception}');
      debugPrint('Stack: ${details.stack}');
      serviceHealth.markDegraded(
        FlutterError,
        'Flutter framework error: ${details.exception}',
      );
    };

    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Workmanager for background sync (non-web only)
    if (!kIsWeb) {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
      await Workmanager().registerPeriodicTask(
        "periodic-sync-task",
        "syncTask",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    }

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    runApp(const DangerEmergenceApp());
  }, (error, stack) {
    debugPrint('══════════════════════════════════════════════════');
    debugPrint('💥 Unhandled async error: $error');
    debugPrint('Stack: $stack');
    serviceHealth.markUnavailable(
      Object,
      'Unhandled async error: $error',
    );
  });
}

/// Root application widget for the Danger Emergence System.
class DangerEmergenceApp extends StatelessWidget {
  const DangerEmergenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Service Health Monitor (must be first so others can report to it)
        ChangeNotifierProvider.value(value: serviceHealth),

        // Core Services
        Provider(create: (_) => safeInit(() => OfflineStorageService()..initialize())),
        Provider(create: (_) => safeInit(() => SyncManager()..initialize())),
        Provider(create: (_) => safeInit(() => BackendApi())),
        Provider(create: (_) => safeInit(() => HardwareTriggerService()..initialize())),

        // Module Services (thin clients — heavy logic moved to backend)
        ChangeNotifierProvider(create: (_) => safeInit(() => AuthService()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => SOSService()..initialize())),
        Provider(create: (_) => safeInit(() => MapService()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => SecurityManager.instance..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => ObservabilityService.instance..initialize())),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,

        // Theme
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,

        // Routing
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.generateRoute,

        // Localization
        locale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('fr', 'FR'),
        ],

        // Performance & Responsive Layout + Degraded Mode Banner
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: ResponsiveWrapper(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DegradedModeBanner(),
                  Expanded(child: child!),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
