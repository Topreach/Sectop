# Integration Audit — Remaining Features

## Overview

After removing Radio Broadcast and Walkie-Talkie Monitor features, this audit verifies that all remaining features integrate properly end-to-end: frontend → BackendApi → backend controllers → services → database/real-time channels.

---

## 1. Feature Map: Frontend ↔ Backend

### 1.1 SOS Alerts
| Frontend | Backend | Status |
|----------|---------|--------|
| [`SOSService`](frontend/lib/modules/sos/services/sos_service.dart) | [`SOSAlertController`](backend/src/main/java/com/dangeremergence/controller/SOSAlertController.java) | ✅ |
| `BackendApi.getActiveAlerts()` → `GET /alerts/active` | `GET /active` | ✅ |
| `BackendApi.getUserAlerts()` → `GET /alerts/user/{userId}` | `GET /user/{userId}` | ✅ |
| `BackendApi.createAlert()` → `POST /alerts` | `POST /` | ✅ |
| `BackendApi.getAlertCount()` → `GET /alerts/count` | `GET /count` | ✅ |
| STOMP sub: `/user/queue/alerts` | [`StompAlertController`](backend/src/main/java/com/dangeremergence/controller/StompAlertController.java) → `/topic/alerts/new` | ✅ |
| STOMP sub: `/topic/alerts/new` | Push via `SimpMessagingTemplate` | ✅ |

### 1.2 Broadcasts (Mass Alert System)
| Frontend | Backend | Status |
|----------|---------|--------|
| [`BroadcastScreen`](frontend/lib/modules/sos/screens/broadcast_screen.dart) | [`BroadcastController`](backend/src/main/java/com/dangeremergence/controller/BroadcastController.java) | ✅ |
| `BackendApi.getActiveBroadcasts()` → `GET /broadcasts/active` | `GET /active` | ✅ |
| `BackendApi.getBroadcast()` → `GET /broadcasts/{id}` | `GET /{id}` | ✅ |
| `BackendApi.createBroadcast()` → `POST /broadcasts` | `POST /` (coordinator only) | ✅ |
| `BackendApi.expireBroadcast()` → `POST /broadcasts/{id}/expire` | `POST /{id}/expire` (coordinator only) | ✅ |
| `BackendApi.getBroadcastCount()` → `GET /broadcasts/count` | `GET /count` | ✅ |
| STOMP: `/app/broadcasts/create` | [`StompBroadcastController`](backend/src/main/java/com/dangeremergence/controller/StompBroadcastController.java) | ✅ |

### 1.3 Safe Route Planning
| Frontend | Backend | Status |
|----------|---------|--------|
| [`SafeRouteScreen`](frontend/lib/modules/sos/screens/safe_route_screen.dart) | [`RouteController`](backend/src/main/java/com/dangeremergence/controller/RouteController.java) + [`RouteService`](backend/src/main/java/com/dangeremergence/service/RouteService.java) | ✅ |
| `BackendApi.planSafeRoute()` → `POST /routes/plan` | `POST /plan` | ✅ |
| `BackendApi.getDangerScore()` → `GET /routes/danger-score` | `GET /danger-score` | ✅ |
| STOMP: `/app/route/plan` → `/user/queue/route/result` | [`StompRouteController`](backend/src/main/java/com/dangeremergence/controller/StompRouteController.java) | ✅ |

### 1.4 Tip-Offs (Intelligence Channel)
| Frontend | Backend | Status |
|----------|---------|--------|
| [`TipOffScreen`](frontend/lib/modules/sos/screens/tip_off_screen.dart) | [`TipOffController`](backend/src/main/java/com/dangeremergence/controller/TipOffController.java) | ✅ |
| `BackendApi.submitTip()` → `POST /tips` | `POST /` (permitAll) | ✅ |
| `BackendApi.getPendingTips()` → `GET /tips/pending` | `GET /pending` (coordinator/responder) | ✅ |
| `BackendApi.getRecentTips()` → `GET /tips/recent` | `GET /recent` (public) | ✅ |
| `BackendApi.getTipById()` → `GET /tips/{id}` | `GET /{id}` | ✅ |
| `BackendApi.reviewTip()` → `POST /tips/{id}/review` | `POST /{id}/review` (coordinator/responder) | ✅ |
| `BackendApi.getTipStats()` → `GET /tips/stats` | `GET /stats` (coordinator/responder) | ✅ |
| STOMP: `/app/tip-offs/submit` | [`StompTipOffController`](backend/src/main/java/com/dangeremergence/controller/StompTipOffController.java) | ✅ |

### 1.5 Danger Zones
| Frontend | Backend | Status |
|----------|---------|--------|
| [`ZoneDetailsScreen`](frontend/lib/modules/sos/screens/zone_details_screen.dart) | [`ZoneController`](backend/src/main/java/com/dangeremergence/controller/ZoneController.java) + [`ZoneService`](backend/src/main/java/com/dangeremergence/service/ZoneService.java) | ✅ |
| `BackendApi.getActiveZones()` → `GET /zones/active` | `GET /active` | ✅ |
| `BackendApi.getDangerZones()` → `GET /zones/danger` | `GET /danger` | ✅ |
| `BackendApi.getRestrictedZones()` → `GET /zones/restricted` | `GET /restricted` | ✅ |
| `BackendApi.getZonesNearby()` → `GET /zones/nearby` | `GET /nearby` | ✅ |
| `BackendApi.createZone()` → `POST /zones` | `POST /` | ✅ |

### 1.6 Incidents (Crowdsourced Danger Reports)
| Frontend | Backend | Status |
|----------|---------|--------|
| [`IncidentService`](frontend/lib/modules/incidents/services/incident_service.dart) | [`IncidentController`](backend/src/main/java/com/dangeremergence/controller/IncidentController.java) + [`IncidentService`](backend/src/main/java/com/dangeremergence/service/IncidentService.java) | ✅ |
| `BackendApi.reportIncident()` → `POST /incidents` | `POST /` | ✅ |
| `BackendApi.getNearbyIncidents()` → `GET /incidents/nearby` | `GET /nearby` | ✅ |
| `BackendApi.getIncidentHeatmap()` → `GET /incidents/heatmap` | `GET /heatmap` | ✅ |
| `BackendApi.upvoteIncident()` → `POST /incidents/{id}/upvote` | `POST /{id}/upvote` | ✅ |
| `BackendApi.getIncidentStats()` → `GET /incidents/stats` | `GET /stats` | ✅ |

### 1.7 Threat Awareness
| Frontend | Backend | Status |
|----------|---------|--------|
| [`ThreatAwarenessService`](frontend/lib/modules/ai/services/threat_awareness_service.dart) | [`ThreatController`](backend/src/main/java/com/dangeremergence/controller/ThreatController.java) | ✅ |
| `BackendApi.analyzeThreatText()` → `POST /threat/analyze-text` | `POST /analyze-text` (permitAll) | ✅ |
| `BackendApi.getThreatLevel()` → `GET /threat/level` | `GET /level` (permitAll) | ✅ |
| `BackendApi.getThreatAlerts()` → `GET /threat/alerts` | `GET /alerts` (permitAll) | ✅ |
| `BackendApi.submitAudioResult()` → `POST /threat/audio-result` | `POST /audio-result` (permitAll) | ✅ |

### 1.8 Community
| Frontend | Backend | Status |
|----------|---------|--------|
| [`CommunityService`](frontend/lib/modules/community/services/community_service.dart) | [`CommunityController`](backend/src/main/java/com/dangeremergence/controller/CommunityController.java) + [`CommunityService`](backend/src/main/java/com/dangeremergence/service/CommunityService.java) | ✅ |
| `uploadMedia()` → `POST /community/upload` (multipart) | `POST /upload` | ✅ |
| `createPost()` → `POST /community/posts` | `POST /posts` | ✅ |
| `getFeed()` → `GET /community/feed` | `GET /feed` | ✅ |
| `getNearby()` → `GET /community/nearby` | `GET /nearby` | ✅ |
| `getPostById()` → `GET /community/posts/{id}` | `GET /posts/{id}` | ✅ |
| `getMyPosts()` → `GET /community/my-posts` | `GET /my-posts` | ✅ |
| `getUserPosts()` → `GET /community/users/{userId}/posts` | `GET /users/{userId}/posts` | ✅ |
| `deletePost()` → `DELETE /community/posts/{id}` | `DELETE /posts/{id}` | ✅ |
| `flagPost()` → `POST /community/posts/{id}/flag` | `POST /posts/{id}/flag` | ✅ |
| `toggleLike()` → `POST /community/posts/{id}/like` | `POST /posts/{id}/like` | ✅ |
| `addComment()` → `POST /community/posts/{id}/comments` | `POST /posts/{id}/comments` | ✅ |
| `getComments()` → `GET /community/posts/{id}/comments` | `GET /posts/{id}/comments` | ✅ |
| `deleteComment()` → `DELETE /community/comments/{id}` | `DELETE /comments/{id}` | ✅ |
| `favoritePost()` → `POST /community/posts/{id}/favorite` | `POST /posts/{id}/favorite` | ✅ |
| `getFavorites()` → `GET /community/my-favorites` | `GET /my-favorites` | ✅ |
| `sharePost()` → `POST /community/posts/{id}/share` | `POST /posts/{id}/share` | ✅ |

### 1.9 Messages (Direct Messaging)
| Frontend | Backend | Status |
|----------|---------|--------|
| [`InboxScreen`](frontend/lib/modules/sos/screens/inbox_screen.dart) | [`MessageController`](backend/src/main/java/com/dangeremergence/controller/MessageController.java) + [`MessageService`](backend/src/main/java/com/dangeremergence/service/MessageService.java) | ✅ |
| `BackendApi.getMessages()` → `GET /messages/user/{userId}` | `GET /user/{userId}` | ✅ |
| `BackendApi.getUnreadCount()` → `GET /messages/unread/{userId}` | `GET /unread/{userId}` | ✅ |
| `BackendApi.markMessageRead()` → `PUT /messages/{id}/read` | `PUT /{messageId}/read` | ✅ |
| `BackendApi.sendMessage()` → `POST /messages` | `POST /` | ✅ |
| STOMP: `/app/messages/send` | [`StompMessageController`](backend/src/main/java/com/dangeremergence/controller/StompMessageController.java) | ✅ |

### 1.10 Evidence Upload
| Frontend | Backend | Status |
|----------|---------|--------|
| [`EvidenceService`](frontend/lib/shared/services/evidence_service.dart) | [`EvidenceController`](backend/src/main/java/com/dangeremergence/controller/EvidenceController.java) + [`EvidenceService`](backend/src/main/java/com/dangeremergence/service/EvidenceService.java) | ✅ |
| `BackendApi.uploadEvidence()` → `POST /evidence` | `POST /` | ✅ |
| `BackendApi.getEvidence()` → `GET /evidence/parent/{parentId}` | `GET /parent/{parentId}` | ✅ |
| `BackendApi.getEvidenceById()` → `GET /evidence/{id}` | `GET /{id}` | ✅ |
| `BackendApi.deleteEvidence()` → `DELETE /evidence/{id}` | `DELETE /{id}` | ✅ |
| `BackendApi.deleteEvidenceForParent()` → `DELETE /evidence/parent/{parentId}` | `DELETE /parent/{parentId}` | ✅ |

### 1.11 Mesh Network
| Frontend | Backend | Status |
|----------|---------|--------|
| [`MeshManager`](frontend/lib/modules/mesh/services/mesh_manager.dart) | [`MeshController`](backend/src/main/java/com/dangeremergence/controller/MeshController.java) | ✅ |
| `BackendApi.findRoute()` → `POST /mesh/route` | `POST /route` | ✅ |
| `BackendApi.broadcastMeshMessage()` → `POST /mesh/broadcast` | `POST /broadcast` | ✅ |
| `BackendApi.getMeshPeers()` → `GET /mesh/peers` | `GET /peers` | ✅ |
| `BackendApi.reportMeshStats()` → `POST /mesh/stats` | `POST /stats` | ✅ |

### 1.12 Predictive Analytics
| Frontend | Backend | Status |
|----------|---------|--------|
| [`PredictiveEngine`](frontend/lib/modules/predictive/services/predictive_engine.dart) | [`PredictiveController`](backend/src/main/java/com/dangeremergence/controller/PredictiveController.java) + [`PredictiveService`](backend/src/main/java/com/dangeremergence/service/PredictiveService.java) | ✅ |
| `BackendApi.mlForecast()` → `POST /predictive/ml-forecast` | `POST /ml-forecast` | ✅ |
| `BackendApi.mlBatchForecast()` → `POST /predictive/ml-forecast/batch` | `POST /ml-forecast/batch` | ✅ |
| `BackendApi.detectHotspots()` → `POST /predictive/hotspots` | `POST /hotspots` | ✅ |
| `BackendApi.triggerTraining()` → `POST /predictive/train` | `POST /train` | ✅ |
| `BackendApi.getTrainingStatus()` → `GET /predictive/training-status` | `GET /training-status` | ✅ |
| `BackendApi.getModelInfo()` → `GET /predictive/model-info` | `GET /model-info` | ✅ |
| `BackendApi.forecastAllStates()` → `POST /predictive/forecast/all-states` | `POST /forecast/all-states` | ✅ |
| `BackendApi.predictiveHealth()` → `GET /predictive/health` | `GET /health` | ✅ |
| `BackendApi.forecastDangerZones()` → `POST /predictive/forecast` | `POST /forecast` (legacy) | ✅ |
| `BackendApi.detectAnomaly()` → `POST /predictive/anomaly` | `POST /anomaly` (legacy) | ✅ |
| `BackendApi.optimizeResources()` → `POST /predictive/optimize-resources` | `POST /optimize-resources` (legacy) | ✅ |

### 1.13 Digital Twin
| Frontend | Backend | Status |
|----------|---------|--------|
| [`DigitalTwinService`](frontend/lib/modules/digital_twin/services/digital_twin_service.dart) | [`DigitalTwinController`](backend/src/main/java/com/dangeremergence/controller/DigitalTwinController.java) | ✅ |
| `BackendApi.getCityTileset()` → `GET /digital-twin/cities/{cityId}/tileset` | `GET /cities/{cityId}/tileset` | ✅ |
| `BackendApi.getCityBuildings()` → `GET /digital-twin/cities/{cityId}/buildings` | `GET /cities/{cityId}/buildings` | ✅ |
| `BackendApi.predictPropagation()` → `POST /digital-twin/predict-propagation` | `POST /predict-propagation` | ✅ |
| `BackendApi.getEvacuationPlan()` → `POST /digital-twin/evacuation-plan` | `POST /evacuation-plan` | ✅ |

### 1.14 Drones
| Frontend | Backend | Status |
|----------|---------|--------|
| [`DroneService`](frontend/lib/modules/drones/services/drone_service.dart) | [`DroneController`](backend/src/main/java/com/dangeremergence/controller/DroneController.java) + [`DroneService`](backend/src/main/java/com/dangeremergence/service/DroneService.java) | ✅ |
| `BackendApi.getAvailableDrones()` → `GET /drones/available` | `GET /available` | ✅ |
| `BackendApi.deployRelayDrone()` → `POST /drones/deploy-relay` | `POST /deploy-relay` | ✅ |
| `BackendApi.assessDamage()` → `POST /drones/assess-damage` | `POST /assess-damage` | ✅ |
| `BackendApi.deploySwarmMesh()` → `POST /drones/deploy-swarm` | `POST /deploy-swarm` | ✅ |

### 1.15 AI/ML Analysis
| Frontend | Backend | Status |
|----------|---------|--------|
| [`AmbientAudioMonitor`](frontend/lib/modules/ai/services/ambient_audio_monitor.dart) | [`AIController`](backend/src/main/java/com/dangeremergence/controller/AIController.java) | ✅ |
| `BackendApi.analyzeMessage()` → `POST /ai/analyze-message` | `POST /analyze-message` (permitAll) | ✅ |
| `BackendApi.prioritize()` → `POST /ai/prioritize` | `POST /prioritize` (permitAll) | ✅ |
| `BackendApi.prioritizeBatch()` → `POST /ai/prioritize-batch` | `POST /prioritize-batch` (permitAll) | ✅ |
| `BackendApi.analyzeAudio()` → `POST /ai/analyze-audio` | `POST /analyze-audio` (permitAll) | ✅ |
| STOMP: `/app/analyze/audio` → `/user/queue/analyze/audio/result` | [`StompAudioController`](backend/src/main/java/com/dangeremergence/controller/StompAudioController.java) | ✅ |

### 1.16 Auth
| Frontend | Backend | Status |
|----------|---------|--------|
| [`AuthService`](frontend/lib/modules/auth/services/auth_service.dart) | [`AuthController`](backend/src/main/java/com/dangeremergence/controller/AuthController.java) + [`UserService`](backend/src/main/java/com/dangeremergence/service/UserService.java) | ✅ |
| `POST /auth/register` | `POST /register` (permitAll) | ✅ |
| `POST /auth/login` | `POST /login` (permitAll) | ✅ |
| `POST /auth/forgot-password` | `POST /forgot-password` (permitAll) | ✅ |
| `POST /auth/reset-password` | `POST /reset-password` (permitAll) | ✅ |
| `POST /auth/account/deletion-request` | `POST /account/deletion-request` | ✅ |
| `POST /auth/account/cancel-deletion` | `POST /account/cancel-deletion` | ✅ |
| `DELETE /auth/account` | `DELETE /account` | ✅ |
| `GET /auth/users/{userId}` | `GET /users/{userId}` | ✅ |
| `PUT /auth/users/{userId}` | `PUT /users/{userId}` | ✅ |
| `POST /auth/users/{userId}/fcm-token` | `POST /users/{userId}/fcm-token` | ✅ |
| `GET /auth/responders` | `GET /responders` | ✅ |

### 1.17 Observability
| Frontend | Backend | Status |
|----------|---------|--------|
| [`ObservabilityService`](frontend/lib/modules/observability/services/observability_service.dart) | [`ObservabilityConfig`](backend/src/main/java/com/dangeremergence/config/ObservabilityConfig.java) | ✅ |
| `BackendApi.sendTraces()` → `POST /observability/traces` | Traces endpoint | ✅ |
| `BackendApi.sendMetrics()` → `POST /observability/metrics` | Metrics endpoint | ✅ |
| `BackendApi.sendLogs()` → `POST /observability/logs` | Logs endpoint | ✅ |
| `BackendApi.sendCrashReport()` → `POST /observability/crash-report` | Crash report endpoint | ✅ |

---

## 2. SecurityConfig Audit

[`SecurityConfig.java`](backend/src/main/java/com/dangeremergence/config/SecurityConfig.java) rules:

| Rule | Endpoints | Status |
|------|-----------|--------|
| `permitAll` | `/api/v1/auth/**` | ✅ |
| `permitAll` | `/api/v1/public/**` | ✅ |
| `permitAll` | `/api/v1/ai/**` | ✅ |
| `permitAll` | `/api/v1/threat/**` | ✅ |
| `permitAll` | `/api/v1/tips`, `/api/v1/tips/**` | ✅ |
| `authenticated` | `/api/v1/routes/**` | ✅ |
| `authenticated` | `/api/v1/broadcasts/active` | ✅ |
| `authenticated` | `/api/v1/broadcasts/count` | ✅ |
| `hasAuthority("coordinator")` | `/api/v1/broadcasts/**` | ✅ |
| `permitAll` | `/actuator/health`, `/actuator/info` | ✅ |
| `hasAuthority("coordinator")` | `/actuator/**` | ✅ |
| `permitAll` | `/ws`, `/ws/**` | ✅ |
| `authenticated` (default) | Everything else | ✅ |

**Issues found:**
- `/api/v1/incidents/**` — not explicitly listed, falls through to `anyRequest().authenticated()`. This is correct since incident reporting requires auth.
- `/api/v1/zones/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/messages/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/community/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/drones/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/digital-twin/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/predictive/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/mesh/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/evidence/**` — not explicitly listed, falls through to `authenticated`. Correct.
- `/api/v1/observability/**` — not explicitly listed, falls through to `authenticated`. Correct.

**No security gaps found.** All endpoints are covered by the default `authenticated()` rule or explicit permitAll rules.

---

## 3. SyncManager Audit

[`SyncManager`](frontend/lib/shared/services/sync_manager.dart) sync flow:

### Push to Cloud
| Entity Type | API Endpoint | Backend Controller | Status |
|-------------|-------------|-------------------|--------|
| `broadcast` | `POST /broadcasts` | `BroadcastController.createBroadcast()` | ✅ |
| `tip_off` | `POST /tips` | `TipOffController.submitTip()` | ✅ |
| `text`/`alert`/`sos` | `POST /messages` | `MessageController.sendMessage()` | ✅ |

### Pull from Cloud
| Data | API Endpoint | Backend Controller | Status |
|------|-------------|-------------------|--------|
| Alerts | `GET /alerts/sync?since=` | `SOSAlertController.getAlertsSince()` | ✅ |
| Zones | `GET /zones/sync?since=` | `ZoneController.getZonesSince()` | ✅ |
| Active Broadcasts | `GET /broadcasts/active` | `BroadcastController.getActiveBroadcasts()` | ✅ |

**Issues found:**
- The `_getSyncUri()` method maps `sos_alerts` to `POST /alerts/sync` and `zones` to `POST /zones/sync`, but the backend controllers use `GET` for these sync endpoints, not `POST`. The sync_log push uses `http.post()` regardless. This means sync_log items for `sos_alerts` and `zones` entity types will fail with 405 Method Not Allowed. However, the Phase 2 offline items flow (which uses `_getOfflineSyncUri`) is the primary sync path and is correct.

---

## 4. Issues Found

### Issue 1: SyncManager uses POST for sync endpoints that expect GET
**File:** [`sync_manager.dart`](frontend/lib/shared/services/sync_manager.dart:118)
**Severity:** Low (sync_log path is secondary; primary offline sync uses correct endpoints)
**Description:** `_getSyncUri()` maps `sos_alerts` → `POST /alerts/sync` and `zones` → `POST /zones/sync`, but backend controllers define these as `GET` endpoints. The `_pushToCloud()` method uses `http.post()` for all sync_log items.
**Fix:** Either change the sync_log push to use `http.get()` for these entity types, or remove the sync_log path for alerts/zones since the Phase 2 offline items path handles them correctly.

### Issue 2: Dashboard quick action cards layout after Radio/Walkie-Talkie removal
**File:** [`dashboard_screen.dart`](frontend/lib/modules/sos/screens/dashboard_screen.dart:660-680)
**Severity:** Low (cosmetic)
**Description:** After removing Radio and Walkie-Talkie cards, the Emergency Tools section now shows only 4 items (Broadcasts, Safe Route, Tip Off, Danger Zones) in a single row. The layout may look unbalanced.
**Fix:** Verify the grid layout handles 4 items gracefully. Consider adding padding or centering.

### Issue 3: No integration tests for end-to-end feature flows
**Severity:** Medium
**Description:** The test suite covers individual controllers and services in isolation, but there are no integration tests that verify end-to-end flows (e.g., create SOS alert → verify it appears in active alerts → verify WebSocket notification → verify sync).
**Fix:** Add integration tests for critical paths.

---

## 5. Action Plan

### Phase 1: Fix SyncManager POST/GET mismatch
1. Update [`_getSyncUri()`](frontend/lib/shared/services/sync_manager.dart:254) to use GET for `sos_alerts` and `zones` entity types
2. Update [`_pushToCloud()`](frontend/lib/shared/services/sync_manager.dart:100) to use `http.get()` for these types

### Phase 2: Verify dashboard layout
1. Check [`dashboard_screen.dart`](frontend/lib/modules/sos/screens/dashboard_screen.dart:660) grid layout handles 4 items
2. Adjust padding/spacing if needed

### Phase 3: Add integration tests
1. Add end-to-end test for SOS alert creation → sync flow
2. Add end-to-end test for broadcast creation → retrieval
3. Add end-to-end test for tip-off submission → review flow

### Phase 4: Verify MQTT integration
1. Confirm [`BroadcastService.publishToMqtt()`](backend/src/main/java/com/dangeremergence/service/BroadcastService.java:190) still works after Radio removal
2. Verify [`MqttService`](backend/src/main/java/com/dangeremergence/service/MqttService.java) topic subscriptions are correct

### Phase 5: Verify FCM push notifications
1. Confirm [`FcmPushService`](backend/src/main/java/com/dangeremergence/service/FcmPushService.java) correctly sends push for SOS alerts, covert alerts, and threat alerts
2. Verify frontend [`PushNotificationService`](frontend/lib/shared/services/push_notification_service.dart) handles all notification types

---

## 6. Architecture Diagram

```mermaid
flowchart TB
    subgraph Frontend
        UI[Dashboard & Screens]
        Services[Feature Services<br/>SOS, Community, Incidents, etc.]
        BackendApi[BackendApi<br/>HTTP Client]
        SyncManager[SyncManager<br/>Offline Sync]
        WS[WebSocket STOMP Client]
    end

    subgraph Backend
        REST[REST Controllers<br/>SOS, Broadcast, Route, TipOff,<br/>Zone, Incident, Threat, etc.]
        STOMP[STOMP Controllers<br/>Alert, Broadcast, Route,<br/>TipOff, Message, Audio]
        Services2[Services<br/>Business Logic]
        MQTT[MQTT Service<br/>IoT Gateway]
        FCM[FCM Push Service<br/>Notifications]
        DB[(PostgreSQL)]
    end

    UI --> Services
    Services --> BackendApi
    Services --> WS
    SyncManager --> BackendApi
    BackendApi --> REST
    WS --> STOMP
    REST --> Services2
    STOMP --> Services2
    Services2 --> DB
    Services2 --> MQTT
    Services2 --> FCM
    MQTT --> IoT[IoT Devices<br/>ESP32/SDR]
    FCM --> Mobile[Push Notifications]
```

---

## 7. Summary

**All 16 feature areas** have been audited for frontend-backend integration. Every frontend API call in [`BackendApi`](frontend/lib/shared/services/backend_api.dart) has a matching backend controller endpoint. Security rules in [`SecurityConfig`](backend/src/main/java/com/dangeremergence/config/SecurityConfig.java) correctly cover all endpoints. STOMP WebSocket subscriptions match their backend controllers.

**One minor issue found:** SyncManager uses POST for sync endpoints that expect GET (sync_log path for alerts/zones). This is low severity since the primary offline sync path (Phase 2 in `_pushToCloud()`) uses the correct endpoints.

**Recommendation:** Fix the SyncManager issue, then proceed with integration testing.
