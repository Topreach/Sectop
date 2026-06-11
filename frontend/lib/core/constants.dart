/// Application-wide constants for the Danger Emergence System.
class AppConstants {
  AppConstants._();

  // Application Info
  static const String appName = 'Danger Emergence';
  static const String appVersion = '1.0.0';
  static const String packageName = 'com.dangeremergence.app';

  // Storage Keys
  static const String keyUserId = 'user_id';
  static const String keyAuthToken = 'auth_token';
  static const String keyEmergencyToken = 'emergency_token';
  static const String keyLastSync = 'last_sync_timestamp';
  static const String keyOfflineMode = 'offline_mode_enabled';
  static const String keyUserRole = 'user_role';
  static const String keyMeshEnabled = 'mesh_network_enabled';
  static const String keyPreloadedRegions = 'preloaded_map_regions';

  // Database
  static const String dbName = 'danger_emergence.db';
  static const int dbVersion = 1;

  // Communication
  static const int bluetoothScanDuration = 30; // seconds
  static const int meshBroadcastInterval = 30; // seconds
  static const int maxMeshRetries = 5;
  static const int messageExpiryHours = 48;
  static const int maxMessageSize = 1024 * 100; // 100KB

  // SOS
  static const int sosRetryInterval = 30; // seconds
  static const int sosMaxRetries = 5;
  static const int sosAutoLocationInterval = 60; // seconds
  static const List<String> sosEmergencyNumbers = ['112', '911', '999'];

  // Maps
  static const String mapsDirectory = 'offline_maps';
  static const double defaultMapZoom = 14.0;
  static const double geofenceDefaultRadius = 100.0; // meters
  static const int mapTileCacheSize = 500; // MB

  // AI/ML
  static const double distressThreshold = 0.8;
  static const int inferenceTimeout = 10000; // milliseconds

  // Sync
  static const int syncIntervalMinutes = 15;
  static const int maxOfflineMessages = 1000;
  static const int batchSyncSize = 50;

  // API
  static const String apiBaseUrl = 'https://sectop.resultscaleai.com/api';
  static const String apiVersion = 'v1';
  static const int apiTimeout = 30; // seconds
  static const int apiRetryCount = 3;

  // WebSocket / STOMP
  static const String wsBaseUrl = 'wss://sectop.resultscaleai.com/ws';

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
  static const String msgStatusDelivered = 'delivered';

  static const String defaultMavlinkUrl = 'ws://drone-hub.dangeremergence.com:5760';

  // UI
  static const double cardBorderRadius = 12.0;
  static const double buttonBorderRadius = 8.0;
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const Duration animationDuration = Duration(milliseconds: 300);

  // Danger Zone Types
  static const String zoneTypeDanger = 'danger';
  static const String zoneTypeSafe = 'safe';
  static const String zoneTypeEvacuation = 'evacuation';
  static const String zoneTypeMedical = 'medical';
  static const String zoneTypeSupply = 'supply';

  // User Roles
  static const String roleCitizen = 'citizen';
  static const String roleResponder = 'responder';
  static const String roleCoordinator = 'coordinator';

  // Message Priority
  static const int priorityLow = 0;
  static const int priorityMedium = 1;
  static const int priorityHigh = 2;
  static const int priorityCritical = 3;

  // Regulatory
  static const int loraDutyCycleEU = 1; // 1% for EU 868MHz
  static const int loraDutyCycleUS = 10; // 0.1-10% for US 915MHz
  static const int maxTransmitPower = 14; // dBm

  // World-Class: Power-Aware Inference
  static const double batteryFullThreshold = 50.0; // % - use full FP32 model
  static const double batteryMediumThreshold = 25.0; // % - use quantized INT8
  static const double batteryLowThreshold = 10.0; // % - use sparse inference
  static const double batteryCriticalThreshold = 5.0; // % - keyword spotting only
  static const int inferenceCacheSize = 100;
  static const double energyFullModel = 500.0; // mJ per inference
  static const double energyQuantized = 125.0; // mJ per inference
  static const double energySparse = 100.0; // mJ per inference
  static const double energyKeywordSpot = 5.0; // mJ per inference

  // World-Class: Adaptive Mesh Routing
  static const int ogmIntervalMs = 1000; // B.A.T.M.A.N. OGM broadcast interval
  static const int routeTimeoutMs = 30000; // Route expiry
  static const int maxMeshHops = 32;
  static const int discoveryTimeoutMs = 5000; // AODV route discovery timeout
  static const int movementHistorySize = 10; // Points for predictive routing
  static const double rssiExcellent = -50.0; // dBm
  static const double rssiGood = -60.0;
  static const double rssiFair = -70.0;
  static const double rssiWeak = -80.0;

  // World-Class: Predictive Analytics
  static const int forecastHorizonMinutes = 360; // 6-hour forecast
  static const int forecastIntervalMinutes = 5; // 5-min intervals
  static const int forecastPeriodMinutes = 1440; // 24-hour seasonal period
  static const double anomalyZScoreThreshold = 3.0;
  static const int anomalyWindowSize = 20;
  static const int hotspotMinValue = 5;
  static const int maxHotspots = 5;
  static const int resourceHistoryDays = 30;

  // World-Class: Disaster-Resistant Architecture
  static const int k8sBackendReplicas = 3;
  static const int k8sMinReplicas = 3;
  static const int k8sMaxReplicas = 20;
  static const double k8sCpuTarget = 70.0; // %
  static const double k8sMemoryTarget = 80.0; // %
  static const int k8sMinAvailable = 2; // PDB

  // World-Class: Security Hardening
  static const bool certificatePinningEnabled = true;
  static const bool fipsModeEnabled = false; // Enable for regulated environments
  static const bool raspEnabled = true; // Runtime Application Self-Protection
  static const bool rootDetectionEnabled = true;
  static const bool debuggerDetectionEnabled = true;
  static const bool emulatorDetectionEnabled = true;
  static const bool hookingDetectionEnabled = true;
  static const bool repackageDetectionEnabled = true;
  static const bool secureEnclaveEnabled = true;
  static const bool keyAttestationEnabled = true;
  static const bool keyRotationEnabled = true;
  static const int keyRotationDays = 90;
  static const int integrityCheckIntervalMinutes = 5;
  static const int maxFailedAuthAttempts = 5;
  static const int authLockoutMinutes = 15;
  static const int maxClockSkewSeconds = 300;
  static const int minimumTlsVersion = 12; // TLS 1.2
  static const bool hstsEnabled = true;
  static const int hstsMaxAge = 31536000; // 1 year
  static const bool securityAuditLogEnabled = true;
  static const bool securityTelemetryEnabled = true;
  static const bool autoIncidentResponseEnabled = true;
  static const bool zeroizeOnCompromise = true;

  // World-Class: Observability Stack
  static const bool observabilityEnabled = true;
  static const double observabilitySamplingRateProduction = 0.1; // 10% in production
  static const double observabilitySamplingRateStaging = 0.5; // 50% in staging
  static const double observabilitySamplingRateDevelopment = 1.0; // 100% in dev
  static const int observabilityFlushIntervalSeconds = 30;
  static const int observabilityMaxBufferSize = 500;
  static const int observabilityMaxExportBatchSize = 512;
  static const int observabilityMaxQueueSize = 2048;
  static const int observabilityExportTimeoutSeconds = 30;
  static const int observabilityScheduleDelaySeconds = 5;
  static const double observabilityHighErrorRateThreshold = 0.05; // 5% triggers increased sampling
  static const double observabilityLowErrorRateThreshold = 0.01; // 1% triggers decreased sampling
  static const int observabilityHighThroughputThreshold = 100; // spans/min triggers decreased sampling
  static const double observabilityBatteryLowThreshold = 0.15; // 15% battery triggers decreased sampling
  static const String observabilityOtlpEndpoint = 'http://localhost:4317';
  static const String observabilityServiceName = 'danger-emergence-frontend';
  static const String observabilityServiceVersion = '1.0.0';
  static const String observabilityEnvironment = 'production';
  static const String observabilityCrashReportEndpoint = '/api/v1/observability/crash-report';
  static const String observabilityMetricsEndpoint = '/api/v1/observability/metrics';
  static const String observabilityLogsEndpoint = '/api/v1/observability/logs';
  static const String observabilityTracesEndpoint = '/api/v1/observability/traces';
  static const int observabilitySpanTimeoutMs = 30000; // 30s span timeout
  static const int observabilityMetricTimeoutMs = 5000; // 5s metric timeout
  static const int observabilityLogTimeoutMs = 5000; // 5s log timeout
  static const int observabilityCrashTimeoutMs = 10000; // 10s crash report timeout
  static const int observabilityMaxTraceSpans = 10000; // max spans before forced flush
  static const int observabilityMaxMetricPoints = 5000; // max metric points before forced flush
  static const int observabilityMaxLogEntries = 1000; // max log entries before forced flush
  static const double observabilityAdaptiveSamplingMin = 0.01; // minimum 1% sampling
  static const double observabilityAdaptiveSamplingMax = 1.0; // maximum 100% sampling
  static const double observabilityAdaptiveSamplingStep = 0.05; // 5% adjustment step

  // Store Compliance / Support
  static const String supportEmail = 'intelligence@resultscaleai.com';
  static const String privacyPolicyUrl = 'https://sectop.resultscaleai.com/privacy';
  static const String appStoreUrl = 'https://play.google.com/store/apps/details?id=com.dangeremergence.app';
}
