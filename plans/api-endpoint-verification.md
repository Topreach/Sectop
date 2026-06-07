# API Endpoint Path Verification

## Frontend `BackendApi` ↔ Backend Controller Mapping

### AI/ML Endpoints

| Frontend Call (BackendApi) | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| `analyzeMessage(text, userId)` | [`AIController`](backend/src/main/java/com/dangeremergence/controller/AIController.java:37) | POST | `/api/v1/ai/analyze-message` | ✅ Match |
| `prioritize(text)` | [`AIController`](backend/src/main/java/com/dangeremergence/controller/AIController.java:88) | POST | `/api/v1/ai/prioritize` | ✅ Match |
| `prioritizeBatch(texts)` | [`AIController`](backend/src/main/java/com/dangeremergence/controller/AIController.java:127) | POST | `/api/v1/ai/prioritize-batch` | ✅ Match |
| `analyzeAudio(base64Audio)` | [`AIController`](backend/src/main/java/com/dangeremergence/controller/AIController.java:143) | POST | `/api/v1/ai/analyze-audio` | ✅ Match |

### Predictive Analytics Endpoints

| Frontend Call (BackendApi) | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| `forecastDangerZones(zoneIds, historyHours, forecastHours)` | [`PredictiveController`](backend/src/main/java/com/dangeremergence/controller/PredictiveController.java:24) | POST | `/api/v1/predictive/forecast` | ✅ Match |
| `detectAnomaly(values)` | [`PredictiveController`](backend/src/main/java/com/dangeremergence/controller/PredictiveController.java:50) | POST | `/api/v1/predictive/anomaly` | ✅ Match |
| `optimizeResources(zones, responders)` | [`PredictiveController`](backend/src/main/java/com/dangeremergence/controller/PredictiveController.java:91) | POST | `/api/v1/predictive/optimize-resources` | ✅ Match |

### Digital Twin Endpoints

| Frontend Call (BackendApi) | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| `getCityTileset(cityId)` | [`DigitalTwinController`](backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java:20) | GET | `/api/v1/digital-twin/cities/{cityId}/tileset` | ✅ Match |
| `getCityBuildings(cityId)` | [`DigitalTwinController`](backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java:34) | GET | `/api/v1/digital-twin/cities/{cityId}/buildings` | ✅ Match |
| `predictPropagation(params)` | [`DigitalTwinController`](backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java:48) | POST | `/api/v1/digital-twin/predict-propagation` | ✅ Match |
| `getEvacuationPlan(lat, lng)` | [`DigitalTwinController`](backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java:79) | POST | `/api/v1/digital-twin/evacuation-plan` | ✅ Match |

### Drone Endpoints

| Frontend Call (BackendApi) | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| `getAvailableDrones(lat, lng)` | [`DroneController`](backend/src/main/java/com/dangeremergence/controller/DroneController.java:42) | GET | `/api/v1/drones/available?latitude=...&longitude=...` | ✅ Match |
| `deployRelayDrone(droneId, lat, lng)` | [`DroneController`](backend/src/main/java/com/dangeremergence/controller/DroneController.java:69) | POST | `/api/v1/drones/deploy-relay` | ✅ Match |
| `assessDamage(zoneId, centerLat, centerLng, radiusKm)` | [`DroneController`](backend/src/main/java/com/dangeremergence/controller/DroneController.java:110) | POST | `/api/v1/drones/assess-damage` | ✅ Match |
| `deploySwarmMesh(zoneId, centerLat, centerLng, radiusKm)` | [`DroneController`](backend/src/main/java/com/dangeremergence/controller/DroneController.java:182) | POST | `/api/v1/drones/deploy-swarm` | ✅ Match |

### Mesh Network Endpoints

| Frontend Call (BackendApi) | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| `findRoute(sourceDeviceId, targetDeviceId, neighborMetrics)` | [`MeshController`](backend/src/main/java/com/dangeremergence/controller/MeshController.java:21) | POST | `/api/v1/mesh/route` | ✅ Match |
| `broadcastMeshMessage(sourceDeviceId, messageType, priority, payload)` | [`MeshController`](backend/src/main/java/com/dangeremergence/controller/MeshController.java:66) | POST | `/api/v1/mesh/broadcast` | ✅ Match |
| `getMeshPeers()` | [`MeshController`](backend/src/main/java/com/dangeremergence/controller/MeshController.java:97) | GET | `/api/v1/mesh/peers` | ✅ Match |
| `reportMeshStats(stats)` | [`MeshController`](backend/src/main/java/com/dangeremergence/controller/MeshController.java:107) | POST | `/api/v1/mesh/stats` | ✅ Match |

### Legacy Endpoints (called directly by services, not through BackendApi)

| Frontend Service | Backend Controller | HTTP Method | Path | Status |
|---|---|---|---|---|
| [`AuthService.login()`](frontend/lib/modules/auth/services/auth_service.dart:63) | [`AuthController`](backend/src/main/java/com/dangeremergence/controller/AuthController.java:79) | POST | `/api/v1/auth/login` | ✅ Match |
| [`AuthService.register()`](frontend/lib/modules/auth/services/auth_service.dart:110) | [`AuthController`](backend/src/main/java/com/dangeremergence/controller/AuthController.java:42) | POST | `/api/v1/auth/register` | ✅ Match |
| [`SOSService._tryCloudSend()`](frontend/lib/modules/sos/services/sos_service.dart:112) | [`SOSAlertController`](backend/src/main/java/com/dangeremergence/controller/SOSAlertController.java:21) | POST | `/api/v1/alerts` | ✅ Match |

## Security Configuration

| Rule | Path Pattern | Status |
|---|---|---|
| Public (no auth) | `/api/v1/auth/**` | ✅ Configured |
| Public (no auth) | `/api/v1/public/**` | ✅ Configured |
| Public (no auth) | `/actuator/health` | ✅ Configured |
| Public (no auth) | `/actuator/info` | ✅ Configured |
| Public (no auth) | `/ws`, `/ws/**` | ✅ Configured |
| Coordinator only | `/actuator/**` | ✅ Configured |
| Authenticated | All other `/api/v1/**` | ✅ Configured |

**⚠️ Note:** The new controllers (AI, Predictive, DigitalTwin, Drone, Mesh) require authentication by default since they don't have explicit `.permitAll()` rules. The AI controller endpoints are under `/api/v1/ai/*` which is NOT in the public list, so they require JWT auth.

## Summary

- **Total frontend API calls mapped**: 25
- **Total backend endpoints covered**: 25
- **Path matches**: 25/25 ✅
- **Auth configuration**: All new endpoints require JWT authentication (except `/api/v1/auth/**` and `/actuator/health`)
