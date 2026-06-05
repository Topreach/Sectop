import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'core/constants.dart';
import 'core/themes.dart';
import 'core/routes.dart';
import 'shared/services/offline_storage.dart';
import 'shared/services/sync_manager.dart';
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
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager for background tasks
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    backgroundSyncTask,
    backgroundSyncTask,
    frequency: Duration(minutes: AppConstants.syncIntervalMinutes),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const DangerEmergenceApp());
}

/// Root application widget for the Danger Emergence System.
class DangerEmergenceApp extends StatelessWidget {
  const DangerEmergenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core Services
        ChangeNotifierProvider(create: (_) => OfflineStorageService()..initialize()),
        ChangeNotifierProvider(create: (_) => SyncManager()..initialize()),
        
        // Module Services
        ChangeNotifierProvider(create: (_) => AuthService()..initialize()),
        ChangeNotifierProvider(create: (_) => SOSService()..initialize()),
        ChangeNotifierProvider(create: (_) => MeshManager()..initialize()),
        ChangeNotifierProvider(create: (_) => AdaptiveMeshRouter()..initialize()),
        ChangeNotifierProvider(create: (_) => MapService()..initialize()),
        ChangeNotifierProvider(create: (_) => DistressDetector()..loadModel()),
        ChangeNotifierProvider(create: (_) => PowerAwareInference()..initialize()),
        ChangeNotifierProvider(create: (_) => PredictiveEngine()..initialize()),
        ChangeNotifierProvider(create: (_) => DigitalTwinService()..initialize()),
        ChangeNotifierProvider(create: (_) => DroneService.instance..initialize()),
        ChangeNotifierProvider(create: (_) => SecurityManager.instance..initialize()),
        ChangeNotifierProvider(create: (_) => ObservabilityService.instance..initialize()),
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
        
        // Performance
        builder: (context, child) {
          return MediaQuery(
            // Prevent font scaling in emergency context
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
