# Frontend Thin-Client Migration Design

## Overview

Transform the Danger Emergence System frontend from a heavy local-processing client into a thin client that delegates all heavy computation (ML inference, predictive analytics, digital twin simulation, drone orchestration, mesh routing) to backend services. The frontend retains: auth flow, emergency report capture, secure storage, minimal status display, map/alert visualization, and consent/permission prompts.

---

## Guiding Principles

1. **Frontend = Thin Client**: No heavy local computation. All ML, simulation, routing, and analytics happen server-side.
2. **API Wrappers Stay**: Each frontend module keeps its service class but replaces local logic with API calls.
3. **Backend Gets New Endpoints**: New Spring Boot controllers and services for each migrated capability.
4. **Offline-First Preserved**: Local SQLite storage remains for auth tokens, cached data, and pending operations.
5. **No Breaking UI Changes**: Screens remain unchanged — only the underlying services change.
6. **Fix Existing Bugs**: Correct the 4 Java files with wrong package declarations.

---

## Phase 1: Fix Backend Package Declaration Bugs

### Files to Fix

| File | Current Package | Correct Package |
|------|----------------|-----------------|
| `JwtAuthenticationFilter.java` | `main.java.com.dangeremergence.config` | `com.dangeremergence.config` |
| `EmergencyBypassAudit.java` | `main.java.com.dangeremergence.model` | `com.dangeremergence.model` |
| `EmergencyBypassService.java` | `main.java.com.dangeremergence.service` | `com.dangeremergence.service` |
| `EmergencyBypassAuditRepository.java` | `main.java.com.dangeremergence.repository` | `com.dangeremergence.repository` |

**Impact**: `SecurityConfig.java` imports `JwtAuthenticationFilter` from the wrong package. `AuthController.java` imports `EmergencyBypassService` from the wrong package. Fixing the 4 files resolves all import chain breakages.

---

## Phase 2: New Backend API Endpoints

### 2.1 AI/ML Distress Detection Endpoint

**Controller**: `backend/src/main/java/com/dangeremergence/controller/AIController.java` (NEW)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/ai/analyze-message` | Analyze text for distress signals |
| POST | `/api/v1/ai/analyze-audio` | Analyze audio for distress (accepts base64) |
| POST | `/api/v1/ai/prioritize` | Prioritize message (delegates to ML service) |
| POST | `/api/v1/ai/prioritize-batch` | Batch prioritize messages |

**Request/Response**:
```json
POST /api/v1/ai/analyze-message
{
  "text": "Help me, fire in building 3",
  "userId": "user_123"
}
→ {
  "priority": "critical",
  "confidence": 0.92,
  "label": "fire_emergency",
  "reasons": ["keyword_fire", "keyword_help", "exclamation"],
  "inferenceTimeMs": 45
}
```

**Backend Logic**: The Spring Boot controller calls the existing FastAPI ML service (`ml_service/app/main.py`) via HTTP internally. The frontend never talks to the ML service directly.

### 2.2 Predictive Analytics Endpoint

**Controller**: `backend/src/main/java/com/dangeremergence/controller/PredictiveController.java` (NEW)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/predictive/forecast` | Get danger zone forecasts |
| POST | `/api/v1/predictive/anomaly` | Detect anomalies in time series |
| POST | `/api/v1/predictive/optimize-resources` | Optimize resource deployment |

**Request/Response**:
```json
POST /api/v1/predictive/forecast
{
  "zoneIds": ["zone_1", "zone_2"],
  "historyHours": 72,
  "forecastHours": 6
}
→ {
  "forecasts": [
    {
      "zoneId": "zone_1",
      "timestamps": [...],
      "predictedValues": [...],
      "trend": "increasing",
      "hotspots": [...],
      "escalationTime": "2024-01-15T14:30:00Z"
    }
  ]
}
```

### 2.3 Digital Twin Endpoint

**Controller**: `backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java` (NEW)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/digital-twin/cities/{cityId}/tileset` | Get city tileset config |
| GET | `/api/v1/digital-twin/cities/{cityId}/buildings` | Get building metadata |
| POST | `/api/v1/digital-twin/predict-propagation` | Run hazard propagation simulation |
| POST | `/api/v1/digital-twin/evacuation-plan` | Get evacuation plan for location |

**Request/Response**:
```json
POST /api/v1/digital-twin/predict-propagation
{
  "cityId": "city_1",
  "hazardType": "fire",
  "originLat": 40.7128,
  "originLng": -74.0060,
  "windSpeed": 15,
  "windDirection": 45
}
→ {
  "propagationCells": [
    {"lat": 40.7128, "lng": -74.0060, "arrivalTime": 0, "intensity": 1.0},
    {"lat": 40.7130, "lng": -74.0058, "arrivalTime": 300, "intensity": 0.8}
  ],
  "buildingsAtRisk": [...],
  "evacuationPlan": {...}
}
```

### 2.4 Drone Orchestration Endpoint

**Controller**: `backend/src/main/java/com/dangeremergence/controller/DroneController.java` (NEW)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/drones/available` | Get available drones |
| POST | `/api/v1/drones/deploy-relay` | Deploy LoRa relay drone |
| POST | `/api/v1/drones/assess-damage` | Run damage assessment |
| POST | `/api/v1/drones/deploy-swarm` | Deploy mesh swarm |

**Request/Response**:
```json
POST /api/v1/drones/assess-damage
{
  "zoneId": "zone_1",
  "centerLat": 40.7128,
  "centerLng": -74.0060,
  "radiusKm": 2.0
}
→ {
  "damagedBuildings": [...],
  "fireHotspots": [...],
  "blockedRoads": [...],
  "casualties": [...],
  "assessmentComplete": true
}
```

### 2.5 Mesh Network Endpoint

**Controller**: `backend/src/main/java/com/dangeremergence/controller/MeshController.java` (NEW)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/mesh/route` | Find optimal mesh route |
| POST | `/api/v1/mesh/broadcast` | Relay message through mesh |
| GET | `/api/v1/mesh/peers` | Get known mesh peers |
| POST | `/api/v1/mesh/stats` | Report mesh statistics |

**Request/Response**:
```json
POST /api/v1/mesh/route
{
  "sourceDeviceId": "dev_abc",
  "targetDeviceId": "dev_xyz",
  "neighborMetrics": [
    {"deviceId": "dev_123", "rssi": -65, "battery": 80, "linkQuality": 0.9}
  ]
}
→ {
  "path": ["dev_abc", "dev_123", "dev_456", "dev_xyz"],
  "totalCost": 3.2,
  "estimatedHops": 3,
  "strategy": "batman_adv"
}
```

### 2.6 Observability Endpoint (Enhanced)

**Controller**: Already exists as `ObservabilityConfig.java` — add to existing or create dedicated controller.

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/observability/traces` | Receive trace spans |
| POST | `/api/v1/observability/metrics` | Receive metrics |
| POST | `/api/v1/observability/logs` | Receive logs |
| POST | `/api/v1/observability/crash-report` | Receive crash reports |

---

## Phase 3: New Frontend Shared Service — `backend_api.dart`

**File**: `frontend/lib/shared/services/backend_api.dart` (NEW)

A centralized HTTP client that all frontend services use to communicate with the backend. Replaces direct `http.get/post` calls scattered across services.

### Design

```dart
class BackendApi {
  static final BackendApi _instance = BackendApi._();
  factory BackendApi() => _instance;
  BackendApi._();

  final String _baseUrl = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
  final Duration _timeout = Duration(seconds: AppConstants.apiTimeout);

  // Auth headers
  Future<Map<String, String>> _headers() async {
    final token = await OfflineStorageService().getSensitiveSetting(AppConstants.keyAuthToken);
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Generic methods
  Future<T> get<T>(String path, {T Function(dynamic)? parser}) async { ... }
  Future<T> post<T>(String path, {Map<String, dynamic>? body, T Function(dynamic)? parser}) async { ... }
  Future<T> put<T>(String path, {Map<String, dynamic>? body, T Function(dynamic)? parser}) async { ... }
  Future<void> delete(String path) async { ... }

  // Domain-specific methods
  // AI
  Future<DistressResult> analyzeMessage(String text) async { ... }
  Future<AudioAnalysisResult> analyzeAudio(String base64Audio) async { ... }

  // Predictive
  Future<PredictionResult> forecastDangerZones(List<String> zoneIds) async { ... }
  Future<ResourcePlan> optimizeResources(List<ZoneInfo> zones, List<ResponderInfo> responders) async { ... }

  // Digital Twin
  Future<CityTilesetConfig> getCityTileset(String cityId) async { ... }
  Future<PropagationResult> predictPropagation(String cityId, Map<String, dynamic> params) async { ... }
  Future<EvacuationPlan> getEvacuationPlan(double lat, double lng) async { ... }

  // Drones
  Future<List<DroneInfo>> getAvailableDrones(double lat, double lng) async { ... }
  Future<DamageAssessment> assessDamage(String zoneId, double lat, double lng, double radius) async { ... }
  Future<SwarmMesh> deploySwarmMesh(String zoneId, double lat, double lng, double radius) async { ... }

  // Mesh
  Future<RouteResult> findRoute(String sourceId, String targetId, List<NeighborMetric> neighbors) async { ... }
  Future<List<MeshPeer>> getMeshPeers() async { ... }

  // Observability
  Future<void> sendTraces(List<TraceSpan> spans) async { ... }
  Future<void> sendMetrics(List<MetricPoint> metrics) async { ... }
  Future<void> sendLogs(List<LogEvent> logs) async { ... }
  Future<void> sendCrashReport(Map<String, dynamic> report) async { ... }
}
```

---

## Phase 4: Simplify Frontend Services

### 4.1 `main.dart` — Simplify Provider Tree

**Current**: 14 services initialized with `safeInit()` + WorkManager + `runZonedGuarded`

**After**:
```dart
// Services that stay (thin wrappers):
// - OfflineStorageService (local SQLite for auth/cache)
// - AuthService (login/logout/token management)
// - SOSService (alert creation, API call)
// - MapService (offline map tiles, zone display)
// - SecurityManager (certificate pinning, integrity check)
// - BackendApi (NEW - centralized HTTP client)
// - SyncManager (simplified - foreground-only)
// - ObservabilityService (simplified - crash reporting only)

// Services REMOVED from initialization:
// - MeshManager (now calls BackendApi)
// - AdaptiveMeshRouter (removed entirely)
// - DistressDetector (now calls BackendApi)
// - PowerAwareInference (removed entirely)
// - PredictiveEngine (now calls BackendApi)
// - DigitalTwinService (now calls BackendApi)
// - DroneService (now calls BackendApi)
```

**New Provider Tree** (8 providers instead of 14):
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => OfflineStorageService()),
    ChangeNotifierProvider(create: (_) => AuthService()),
    ChangeNotifierProvider(create: (_) => SOSService()),
    ChangeNotifierProvider(create: (_) => MapService()),
    ChangeNotifierProvider(create: (_) => SecurityManager.instance),
    ChangeNotifierProvider(create: (_) => ServiceHealthNotifier()),
    ChangeNotifierProvider(create: (_) => SyncManager()),
    ChangeNotifierProvider(create: (_) => ObservabilityService()),
  ],
  child: const DangerEmergenceApp(),
)
```

### 4.2 `sync_manager.dart` — Simplify to Foreground-Only

**Current**: 347 lines — periodic Timer sync, connectivity listener, three-state model, pull/push from multiple endpoints.

**After**: ~80 lines — foreground-only sync triggered by user action or app resume. Remove periodic timer. Keep the three-state model for offline queue but simplify.

**Changes**:
- Remove `Timer`-based periodic sync
- Remove `connectivity_plus` listener (rely on call-time error handling)
- Keep `_pullFromCloud()` and `_pushToCloud()` but simplify
- Add `syncNow()` method called from UI or app lifecycle
- Keep offline queue (pending → synced transition)

### 4.3 `observability_service.dart` — Simplify to Crash Reporting Only

**Current**: 565 lines — trace spans, metrics buffer, log buffer, adaptive sampling, periodic flush.

**After**: ~120 lines — lightweight crash reporting and minimal error logging only.

**Changes**:
- Remove trace span collection and buffering
- Remove metrics collection
- Remove adaptive sampling logic
- Remove periodic flush timer
- Keep `reportCrash()` — sends crash reports to `/telemetry/crash`
- Keep minimal `logError()` for critical errors only
- Remove `TraceSpan`, `MetricPoint`, `MetricType` data classes (or move to backend)

### 4.4 `distress_detector.dart` — Convert to API Wrapper

**Current**: 389 lines — TFLite MethodChannel bridge, rule-based fallback, audio analysis.

**After**: ~80 lines — thin API wrapper that calls `BackendApi.analyzeMessage()`.

**Changes**:
- Remove `MethodChannel` TFLite bridge calls
- Remove `_ruleBasedAnalysis()` keyword scoring
- Remove `analyzeAudio()` (moved to backend)
- Remove `loadModel()` (no local model needed)
- Keep `DistressResult` data class (for UI compatibility)
- `analyzeMessage()` now calls `BackendApi().analyzeMessage(text)`
- Add `isAvailable` getter that checks connectivity

### 4.5 `power_aware_inference.dart` — REMOVE Entirely

**Current**: 597 lines — 4-tier battery-aware model selection, LRU cache, energy tracking.

**Rationale**: All inference is now server-side. Battery-aware selection is irrelevant. Remove entirely.

**Impact**: Remove from `main.dart` provider tree. Remove any imports.

### 4.6 `model_bundle.dart` — REMOVE Entirely

**Current**: 224 lines — model download, cache, SHA-256 verification.

**Rationale**: No local models needed. All inference is server-side. Remove entirely.

### 4.7 `text_tokenizer.dart` — REMOVE Entirely

**Current**: 305 lines — BPE tokenization, emergency vocabulary.

**Rationale**: Tokenization happens server-side. Remove entirely.

### 4.8 `predictive_engine.dart` — Convert to API Wrapper

**Current**: 549 lines — Prophet-style decomposition, LSTM anomaly detection, Hungarian algorithm.

**After**: ~100 lines — thin API wrapper that calls `BackendApi`.

**Changes**:
- Remove `MethodChannel` LSTM bridge calls
- Remove time series decomposition logic
- Remove anomaly detection (z-score calculation)
- Remove Hungarian algorithm implementation
- Keep data classes (`PredictionResult`, `Hotspot`, `ResourcePlan`, etc.) for UI
- `forecastDangerZones()` → calls `BackendApi().forecastDangerZones()`
- `optimizeResourceDeployment()` → calls `BackendApi().optimizeResources()`
- Remove periodic 5-min forecasting timer

### 4.9 `digital_twin_service.dart` — Convert to API Wrapper

**Current**: 524 lines — SimulationEngine, AROverlayService, GPU fluid dynamics, hazard propagation.

**After**: ~100 lines — thin API wrapper that calls `BackendApi`.

**Changes**:
- Remove `SimulationEngine` dependency
- Remove GPU-accelerated fluid dynamics logic
- Remove hazard propagation simulation
- Remove evacuation planning algorithm
- Keep data classes (`CityTilesetConfig`, `BuildingData`, `EvacuationPlan`)
- `loadCity()` → calls `BackendApi().getCityTileset()` + `BackendApi().getBuildings()`
- `predictPropagation()` → calls `BackendApi().predictPropagation()`
- `getEvacuationPlan()` → calls `BackendApi().getEvacuationPlan()`

### 4.10 `simulation_engine.dart` — REMOVE Entirely

**Current**: GPU-accelerated fluid dynamics simulation engine.

**Rationale**: Simulation runs server-side. Remove entirely.

### 4.11 `drone_service.dart` — Convert to API Wrapper

**Current**: 518 lines — MAVLink integration, lawnmower patterns, LoRa relay deployment, swarm mesh.

**After**: ~100 lines — thin API wrapper that calls `BackendApi`.

**Changes**:
- Remove `MAVLinkService` dependency
- Remove lawnmower pattern generation
- Remove LoRa relay deployment logic
- Remove damage assessment simulation
- Remove swarm mesh networking logic
- Keep data classes (`DroneInfo`, `DamageAssessment`, `SwarmMesh`, etc.)
- `getAvailableDrones()` → calls `BackendApi().getAvailableDrones()`
- `deployRelayDrone()` → calls `BackendApi().deployRelay()`
- `assessDamage()` → calls `BackendApi().assessDamage()`
- `deploySwarmMesh()` → calls `BackendApi().deploySwarmMesh()`

### 4.12 `mavlink_service.dart` — REMOVE Entirely

**Current**: MAVLink protocol implementation for drone communication.

**Rationale**: Drone orchestration runs server-side. Remove entirely.

### 4.13 `mesh_manager.dart` — Convert to API Wrapper

**Current**: 758 lines — three-layer Bluetooth/WiFi Direct/LoRa, E2E encryption, message queuing.

**After**: ~150 lines — thin wrapper that calls `BackendApi` for routing, keeps local device-to-device Bluetooth for last-hop delivery.

**Changes**:
- Remove `AdaptiveMeshRouter` dependency
- Remove B.A.T.M.A.N. OGM broadcasting
- Remove AODV route discovery
- Remove E2E encryption (moved to backend or kept minimal)
- Remove LoRa serial bridge logic
- Keep local Bluetooth peer discovery (device-to-device only)
- `broadcastMessage()` → stores locally, calls `BackendApi().broadcast()` if online
- `findRoute()` → calls `BackendApi().findRoute()`
- Keep `MeshPeer`, `MeshMessage` data classes
- Remove `ConnectionType.lora` (handled server-side)

### 4.14 `adaptive_mesh_router.dart` — REMOVE Entirely

**Current**: 554 lines — B.A.T.M.A.N. + AODV hybrid routing protocol.

**Rationale**: Mesh routing computation runs server-side. Remove entirely.

---

## Phase 5: Files to Delete

| File | Size | Reason |
|------|------|--------|
| `frontend/lib/modules/ai/services/power_aware_inference.dart` | 597 lines | All inference server-side |
| `frontend/lib/modules/ai/services/model_bundle.dart` | 224 lines | No local models needed |
| `frontend/lib/modules/ai/services/text_tokenizer.dart` | 305 lines | Tokenization server-side |
| `frontend/lib/modules/digital_twin/services/simulation_engine.dart` | ~300 lines | Simulation server-side |
| `frontend/lib/modules/drones/services/mavlink_service.dart` | ~200 lines | Drone orchestration server-side |
| `frontend/lib/modules/mesh/services/adaptive_mesh_router.dart` | 554 lines | Routing computation server-side |

---

## Phase 6: Implementation Order

### Step 1: Fix Backend Package Declarations
Fix 4 Java files with wrong `main.java.com.dangeremergence.*` packages.

### Step 2: Create New Backend Controllers
Create 5 new controllers: `AIController`, `PredictiveController`, `DigitalTwinController`, `DroneController`, `MeshController`.

### Step 3: Create `backend_api.dart`
Create the centralized HTTP client in `frontend/lib/shared/services/backend_api.dart`.

### Step 4: Simplify `main.dart`
Reduce provider tree from 14 to 8 services. Remove WorkManager background sync.

### Step 5: Simplify `sync_manager.dart`
Remove periodic timer, keep foreground-only sync.

### Step 6: Simplify `observability_service.dart`
Remove tracing/metrics/logging buffers, keep crash reporting only.

### Step 7: Convert AI Modules
- `distress_detector.dart` → API wrapper
- Delete `power_aware_inference.dart`, `model_bundle.dart`, `text_tokenizer.dart`

### Step 8: Convert `predictive_engine.dart`
→ API wrapper, remove local computation.

### Step 9: Convert Digital Twin Modules
- `digital_twin_service.dart` → API wrapper
- Delete `simulation_engine.dart`

### Step 10: Convert Drone Modules
- `drone_service.dart` → API wrapper
- Delete `mavlink_service.dart`

### Step 11: Convert Mesh Modules
- `mesh_manager.dart` → API wrapper (keep local Bluetooth)
- Delete `adaptive_mesh_router.dart`

### Step 12: Update Tests
Update any unit tests to mock `BackendApi` instead of local computation.

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Backend API not ready | Frontend services degrade gracefully — show cached data, queue operations |
| Network latency for ML inference | BackendApi has configurable timeout; UI shows loading states |
| Breaking UI changes | All data classes preserved; only service implementation changes |
| Offline functionality lost | Local SQLite + sync queue preserved; mesh last-hop Bluetooth kept |
| Backend package fix breaks imports | Fix all 4 files simultaneously; verify compilation |

---

## Data Class Preservation

All frontend data classes remain unchanged to avoid UI breakage:

| Module | Data Classes | Status |
|--------|-------------|--------|
| AI | `DistressResult`, `AudioAnalysisResult` | Keep |
| Predictive | `PredictionResult`, `Hotspot`, `ResourcePlan`, `Assignment`, `ZoneInfo`, `ResponderInfo` | Keep |
| Digital Twin | `CityTilesetConfig`, `BuildingData`, `EvacuationPlan` | Keep |
| Drones | `DroneInfo`, `DamageAssessment`, `DamagedBuilding`, `FireHotspot`, `BlockedRoad`, `Casualty`, `SwarmMesh` | Keep |
| Mesh | `MeshPeer`, `MeshMessage`, `MeshStats` | Keep |
| Observability | `TraceSpan`, `MetricPoint`, `LogEvent` | Move to backend or remove |

---

## Backend Service Architecture (New)

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Frontend   │────▶│  Spring Boot API  │────▶│  FastAPI ML      │
│  (Flutter)  │     │  (Backend)        │     │  Service         │
└─────────────┘     └──────────────────┘     └─────────────────┘
                           │
                           ├──▶ AIController ──▶ FastAPI (internal)
                           ├──▶ PredictiveController ──▶ Local computation
                           ├──▶ DigitalTwinController ──▶ Local computation
                           ├──▶ DroneController ──▶ MAVLink (server-side)
                           ├──▶ MeshController ──▶ Route computation
                           ├──▶ ObservabilityController ──▶ Storage/Analytics
                           ├──▶ AuthController (existing)
                           ├──▶ MessageController (existing)
                           ├──▶ SOSAlertController (existing)
                           └──▶ ZoneController (existing)
```

The Spring Boot backend becomes the single point of contact for the frontend. The ML service is called internally by the backend, not directly by the frontend.

---

## Summary of Changes

| Category | Files Modified | Files Created | Files Deleted |
|----------|---------------|---------------|---------------|
| Backend | 4 (package fix) | 5 (new controllers) | 0 |
| Frontend Services | 8 | 1 (backend_api.dart) | 6 |
| Frontend Entry | 1 (main.dart) | 0 | 0 |
| **Total** | **13** | **6** | **6** |

**Net change**: +6 files created, -6 files deleted, 13 files modified.
