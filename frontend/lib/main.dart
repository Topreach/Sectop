import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'shared/widgets/responsive_layout.dart';
import 'shared/widgets/degraded_mode_banner.dart';
import 'modules/auth/services/auth_service.dart';
import 'modules/sos/services/sos_service.dart';
import 'modules/mesh/services/mesh_manager.dart';
import 'modules/mesh/services/adaptive_mesh_router.dart';
import 'modules/maps/services/map_service.dart';
import 'modules/ai/services/distress_detector.dart';
import 'modules/ai/services/power_aware_inference.dart';
import 'modules/predictive/services/predictive_engine.dart';
import 'modules/digital_twin/services/digital_twin_service.dart';
import 'modules/drones/services/drone_service.dart';
import 'modules/security/services/security_manager.dart';
import 'modules/observability/services/observability_service.dart';

/// Global service health monitor — tracks which services are degraded.
final ServiceHealthNotifier serviceHealth = ServiceHealthNotifier();

/// Helper that wraps a service creation + initialization call in a try-catch.
/// If the initializer throws synchronously (before the first `await` in the
/// Future), the error is caught here so the Provider's `create` callback never
/// throws — preventing the entire widget tree from collapsing.
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
    return instance;
  } catch (e, stack) {
    debugPrint('══════════════════════════════════════════════════');
    debugPrint('⚠️ safeInit caught error for $T: $e');
    debugPrint('Stack: $stack');
    debugPrint('══════════════════════════════════════════════════');
    // Report degraded status to the health monitor
    serviceHealth.markDegraded(T, 'Initialization failed: $e');
    // Return a default instance so the Provider tree doesn't collapse.
    // The service will be in a degraded state but the app continues to run.
    return _createFallback<T>();
  }
}

/// Creates a fallback instance for a service type when initialization fails.
/// Uses the type's default constructor if available.
T _createFallback<T>() {
  // For ChangeNotifier subtypes, create a default instance
  if (T == AuthService) return AuthService() as T;
  if (T == SOSService) return SOSService() as T;
  if (T == DroneService) return DroneService.instance as T;
  if (T == SecurityManager) return SecurityManager.instance as T;
  if (T == ObservabilityService) return ObservabilityService.instance as T;
  if (T == DigitalTwinService) return DigitalTwinService() as T;
  // For plain Provider services, try default constructor
  if (T == OfflineStorageService) return OfflineStorageService() as T;
  if (T == SyncManager) return SyncManager() as T;
  if (T == MeshManager) return MeshManager() as T;
  if (T == AdaptiveMeshRouter) return AdaptiveMeshRouter() as T;
  if (T == MapService) return MapService() as T;
  if (T == DistressDetector) return DistressDetector() as T;
  if (T == PowerAwareInference) return PowerAwareInference() as T;
  if (T == PredictiveEngine) return PredictiveEngine() as T;
  throw StateError('No fallback constructor for $T');
}

// Background task for periodic sync
const String backgroundSyncTask = 'backgroundSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case backgroundSyncTask:
        final syncManager = SyncManager();
        await syncManager.triggerSync();
        break;
    }
    return Future.value(true);
  });
}

void main() async {
  // Capture all unhandled errors globally so they don't crash the app silently.
  runZonedGuarded(() async {
    FlutterError.onError = (details) {
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🚨 FlutterError caught: ${details.exception}');
      debugPrint('Stack: ${details.stack}');
      debugPrint('══════════════════════════════════════════════════');
      // Report to health monitor so the UI can show degraded mode
      serviceHealth.markDegraded(
        FlutterError,
        'Flutter framework error: ${details.exception}',
      );
    };

    WidgetsFlutterBinding.ensureInitialized();

    // Initialize WorkManager for background tasks (mobile only)
    if (!kIsWeb) {
      try {
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
        await Workmanager().registerPeriodicTask(
          backgroundSyncTask,
          backgroundSyncTask,
          frequency: Duration(minutes: AppConstants.syncIntervalMinutes),
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
        );
      } catch (e, stack) {
        debugPrint('WorkManager init error (non-fatal): $e\n$stack');
        serviceHealth.markDegraded(
          Workmanager,
          'Background sync unavailable: $e',
        );
      }
    }

    // Set system UI overlay style (orientation is not locked to support tablets/desktop)
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
    debugPrint('══════════════════════════════════════════════════');
    // Show critical error overlay for unrecoverable async errors
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

        // Module Services
        ChangeNotifierProvider(create: (_) => safeInit(() => AuthService()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => SOSService()..initialize())),
        Provider(create: (_) => safeInit(() => MeshManager()..initialize())),
        Provider(create: (_) => safeInit(() => AdaptiveMeshRouter()..initialize())),
        Provider(create: (_) => safeInit(() => MapService()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => DistressDetector()..loadModel())),
        Provider(create: (_) => safeInit(() => PowerAwareInference()..initialize())),
        Provider(create: (_) => safeInit(() => PredictiveEngine()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => DigitalTwinService()..initialize())),
        ChangeNotifierProvider(create: (_) => safeInit(() => DroneService.instance..initialize())),
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
            // Prevent font scaling in emergency context
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: ResponsiveWrapper(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show degraded mode banner at the top when services fail
                  const DegradedModeBanner(),
                  // Main app content fills remaining space
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
