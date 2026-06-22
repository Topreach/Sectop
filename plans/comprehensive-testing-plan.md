# Comprehensive Testing Plan — Sectop Emergency System

## Overview

This plan covers rigorous automated testing across all four services of the Sectop system:

| Service | Language/Framework | Port | Purpose |
|---------|-------------------|------|---------|
| **Backend API** | Java / Spring Boot 3.2 | 8080 | Main REST API, auth, messaging, community, etc. |
| **SOS Service** | Java / Spring Boot 3.2 | 8081 | Dedicated SOS alert microservice |
| **Flutter Frontend** | Dart / Flutter | — | Android mobile app |
| **ML Service** | Python / FastAPI | 8000 | Predictive analytics, threat detection |

---

## 1. Backend API (`backend/`) — Java / Spring Boot

### Current State
- **Zero tests exist** — no `src/test/` directory
- Test dependencies already in `pom.xml`: `spring-boot-starter-test`, `spring-security-test`, `h2` (in-memory DB for tests)

### Required Test Structure

```
backend/src/test/java/com/dangeremergence/
  controller/
    AuthControllerTest.java
    SOSAlertControllerTest.java
    MessageControllerTest.java
    CommunityControllerTest.java
    BroadcastControllerTest.java
    ThreatControllerTest.java
    TipOffControllerTest.java
    DroneControllerTest.java
    EvidenceControllerTest.java
    IncidentControllerTest.java
    ZoneControllerTest.java
    RadioControllerTest.java
    RouteControllerTest.java
    DigitalTwinControllerTest.java
    PredictiveControllerTest.java
    PublicControllerTest.java
    MeshControllerTest.java
    AIControllerTest.java
  service/
    UserServiceTest.java
    SOSAlertServiceTest.java
    MessageServiceTest.java
    CommunityServiceTest.java
    BroadcastServiceTest.java
    CovertAlertServiceTest.java
    FcmPushServiceTest.java
    SmsGatewayServiceTest.java
    MqttServiceTest.java
    AlertPubSubServiceTest.java
    PriorityMessageQueueTest.java
    NigeriaLocationServiceTest.java
    EvidenceServiceTest.java
    IncidentServiceTest.java
    EmergencyBypassServiceTest.java
    TipOffServiceTest.java
    DroneServiceTest.java
    RadioBroadcastServiceTest.java
    RouteServiceTest.java
    ZoneServiceTest.java
    PredictionCacheServiceTest.java
    PredictiveServiceTest.java
  config/
    JwtUtilTest.java
    JwtAuthenticationFilterTest.java
    SecurityConfigTest.java
    WebSocketConfigTest.java
  repository/
    UserRepositoryTest.java
    SOSAlertRepositoryTest.java
    MessageRepositoryTest.java
    CommunityPostRepositoryTest.java
    (one per repository interface)
```

### Test Types

#### A. Unit Tests (Service Layer)
- Mock all repositories using Mockito
- Test business logic in isolation
- Cover: success paths, failure paths, edge cases, boundary conditions

**Key services to test:**

| Service | Critical Test Cases |
|---------|-------------------|
| `UserService` | Register (success, duplicate email, weak password), Authenticate (valid, invalid, locked account), Update profile, Password reset flow, Account deletion flow |
| `SOSAlertService` | Create alert (normal, covert, silent), Find nearby alerts (geo-radius query), Acknowledge alert, Resolve alert, Duplicate prevention |
| `MessageService` | Send message (online, offline), Read receipts, Delivery status, Sync mechanism, Priority queue ordering |
| `CommunityService` | Create post, Feed pagination, Nearby feed (geo-filtering), Like/Unlike, Comment CRUD, Flag inappropriate, Share, Favorite |
| `CovertAlertService` | Process covert alert, Resolve emergency contacts, Silent notification delivery |
| `FcmPushService` | Send to single token, Send to multiple tokens, Handle invalid token, Throttle handling |
| `SmsGatewayService` | Send SMS, Handle gateway timeout, Retry logic, Message formatting |
| `NigeriaLocationService` | Resolve state/LGA from coordinates, Boundary edge cases, Out-of-Nigeria coordinates |
| `EmergencyBypassService` | Create bypass session, Validate bypass token, Expiry handling |
| `BroadcastService` | Create broadcast, Publish to MQTT, Publish to WebSocket, Expire broadcast |
| `PriorityMessageQueue` | Queue ordering by priority, Concurrent enqueue/dequeue, Empty queue handling |

#### B. Integration Tests (Controller Layer)
- Use `@WebMvcTest` with mocked service layer
- Test HTTP request/response mapping, status codes, validation
- Test security: authenticated vs. unauthenticated access, role-based access

**Key controllers to test:**

| Controller | Critical Test Cases |
|------------|-------------------|
| `AuthController` | POST /register (201, 400, 409), POST /login (200, 401), POST /emergency-bypass, PUT /users/{id} (update profile + fcmToken), POST /forgot-password, POST /reset-password, DELETE /account |
| `SOSAlertController` | POST / (create alert), GET /active, GET /user/{id}, GET /nearby?lat=&lng=&radius=, POST /{id}/acknowledge, POST /{id}/resolve |
| `MessageController` | POST / (send), GET /user/{id}, GET /sync, PUT /{id}/deliver, PUT /{id}/read, GET /unread/{id} |
| `CommunityController` | POST /posts, GET /feed?page=&size=, GET /nearby, POST /{id}/like, POST /{id}/comments, DELETE /posts/{id} |
| `BroadcastController` | POST / (create), GET /active, POST /{id}/expire |
| `ThreatController` | POST /analyze, GET /threats/nearby |
| `EvidenceController` | POST /upload, GET /{alertId} |
| `IncidentController` | POST /report, GET /nearby |

#### C. Repository Tests (Data Layer)
- Use `@DataJpaTest` with H2 in-memory database
- Test custom queries: geo-spatial queries, aggregations, pagination
- Test Flyway migrations against H2

**Key repository queries to test:**

| Repository | Custom Query |
|-----------|-------------|
| `SOSAlertRepository` | `findAlertsNearby(minLat, maxLat, minLng, maxLng, status, since)` |
| `UserRepository` | `findUsersWithFcmToken()`, `findUsersInArea()` |
| `MessageRepository` | `findMessagesBetweenUsers()`, `findPendingSync()` |
| `BroadcastRepository` | `findActiveBroadcastsNearby()`, `findActiveBroadcastsInArea()` |
| `CommunityPostRepository` | `findPostsNearby()`, `findFeed()` |

#### D. End-to-End Tests
- Use `@SpringBootTest(webEnvironment = RANDOM_PORT)` with `TestRestTemplate`
- Start full application context with H2
- Test complete flows end-to-end

**Critical E2E flows:**

1. **Full SOS Flow**: Register user → Login → Create SOS alert → Nearby responder acknowledges → Alert resolved
2. **Covert SOS Flow**: Register user → Set emergency contacts → Create covert alert → Emergency contacts notified
3. **Messaging Flow**: User A sends message → User B receives → User B marks as read → Sync status
4. **Community Flow**: Create post → Like post → Comment on post → Share post → Flag post
5. **Password Reset Flow**: Request reset → Receive token → Reset password → Login with new password
6. **Account Deletion Flow**: Request deletion → Cancel deletion → Confirm deletion → Login fails

---

## 2. SOS Service (`sos-service/`) — Java / Spring Boot

### Current State
- **Zero tests exist** — no `src/test/` directory
- Test dependency `spring-boot-starter-test` already in `pom.xml`

### Required Test Structure

```
sos-service/src/test/java/com/dangeremergence/sos/
  controller/
    SOSAlertControllerTest.java
    StompAlertControllerTest.java
  service/
    SOSAlertServiceTest.java
    CovertAlertServiceTest.java
    FcmPushServiceTest.java
    SmsGatewayServiceTest.java
    AlertPubSubServiceTest.java
    NigeriaLocationServiceTest.java
  config/
    JwtUtilTest.java
    JwtAuthenticationFilterTest.java
```

### Test Types

Same structure as Backend API — unit, integration, repository, and E2E tests.

**SOS-specific critical tests:**

| Test | Description |
|------|-------------|
| Create alert with geo-location | Verify latitude/longitude stored correctly |
| Find nearby alerts | Verify geo-radius query returns correct results |
| Covert alert processing | Verify emergency contacts resolved and notified |
| FCM push on alert creation | Verify push notification sent to nearby responders |
| SMS fallback | Verify SMS sent when FCM fails |
| Duplicate alert prevention | Verify same user cannot create duplicate alert within N minutes |
| Silent/stealth mode | Verify no notification sound/vibration for silent alerts |
| WebSocket broadcast | Verify alert pushed to WebSocket topic |

---

## 3. Flutter Frontend (`frontend/`) — Dart/Flutter

### Current State
- **4 test files exist** with ~1,296 lines of tests:
  - `auth_service_test.dart` (376 lines) — AuthService login/register/logout
  - `backend_api_test.dart` (204 lines) — BackendApi URL construction
  - `backend_api_extended_test.dart` (716 lines) — BackendApi request body verification
  - `widget_test.dart` (13 lines) — Basic widget smoke test
- Test dependencies: `flutter_test`, `mockito`, `integration_test`

### What's Missing

| Area | Missing Tests |
|------|--------------|
| **Services** | `SOSService`, `PushNotificationService`, `MapService`, `MeshManager`, `SecurityManager`, `ObservabilityService`, `SyncManager`, `OfflineStorageService`, `HardwareTriggerService`, `ThreatAwarenessService`, `EncryptionService`, `CrashReporter` |
| **Screens** | All screens: `SOSScreen`, `HomeScreen`, `MapScreen`, `ChatScreen`, `CommunityScreen`, `ProfileScreen`, `SettingsScreen`, `PermissionScreen`, `SplashScreen`, `LoginScreen`, `RegisterScreen`, `EmergencyBypassScreen`, `ThreatAwarenessScreen`, `BroadcastScreen`, `IncidentScreen`, `DroneScreen`, `EvidenceScreen`, `TipOffScreen`, `RadioScreen`, `RouteScreen`, `DigitalTwinScreen` |
| **Widgets** | `ResponsiveLayout`, `DegradedModeBanner`, custom widgets |
| **Integration** | Cross-service flows (auth → SOS → messaging) |
| **E2E** | Full app flows via `integration_test` |

### Required Test Structure

```
frontend/test/
  services/
    auth_service_test.dart              # EXISTS — expand coverage
    backend_api_test.dart               # EXISTS — expand coverage
    backend_api_extended_test.dart      # EXISTS — expand coverage
    sos_service_test.dart               # NEW
    push_notification_service_test.dart # NEW
    map_service_test.dart               # NEW
    sync_manager_test.dart              # NEW
    offline_storage_service_test.dart   # NEW
    encryption_service_test.dart        # NEW
    mesh_manager_test.dart              # NEW
    security_manager_test.dart          # NEW
    threat_awareness_service_test.dart  # NEW
    hardware_trigger_service_test.dart  # NEW
    crash_reporter_test.dart            # NEW
  screens/
    sos_screen_test.dart                # NEW
    auth_screen_test.dart               # NEW
    home_screen_test.dart               # NEW
    map_screen_test.dart                # NEW
    chat_screen_test.dart               # NEW
    community_screen_test.dart          # NEW
    profile_screen_test.dart            # NEW
    settings_screen_test.dart           # NEW
    threat_awareness_screen_test.dart   # NEW
    broadcast_screen_test.dart          # NEW
    incident_screen_test.dart           # NEW
    evidence_screen_test.dart           # NEW
  widgets/
    responsive_layout_test.dart         # NEW
    degraded_mode_banner_test.dart      # NEW
  integration/
    auth_flow_test.dart                 # NEW
    sos_flow_test.dart                  # NEW
    messaging_flow_test.dart            # NEW
    community_flow_test.dart            # NEW
  e2e/
    app_e2e_test.dart                   # NEW
```

### Test Types

#### A. Unit Tests (Services)
- Mock HTTP client, local storage, platform channels
- Test business logic in isolation

**Key services to test:**

| Service | Critical Test Cases |
|---------|-------------------|
| `AuthService` | Login (success, 401, network error, offline fallback), Register (success, 409, offline), Emergency bypass, Logout, Session restore, FCM token registration after login |
| `SOSService` | Send SOS (normal, covert, silent), Fetch active alerts, Acknowledge alert, Resolve alert, Offline queue |
| `PushNotificationService` | Initialize Firebase, Request permission, Get FCM token, Register token with backend, Handle foreground message, Handle background message, Handle token refresh, Clear token on logout |
| `SyncManager` | Trigger sync, Queue offline changes, Conflict resolution, Periodic sync |
| `OfflineStorageService` | CRUD operations, Query with filters, Settings storage, Sensitive data encryption |
| `MapService` | Load tiles, Update user location, Show nearby alerts |
| `MeshManager` | Discover peers, Connect, Send message, Receive message |
| `SecurityManager` | Encrypt data, Decrypt data, Key generation, Biometric auth |
| `ThreatAwarenessService` | Analyze threat level, Show local notification, Update threat status |
| `HardwareTriggerService` | Detect button press, Trigger SOS, Covert trigger |

#### B. Widget Tests
- Use `WidgetTester` to pump widgets and verify rendering
- Mock services via Provider injection

**Key screens to test:**

| Screen | Critical Test Cases |
|--------|-------------------|
| `SOSScreen` | Renders alert type selector, Description field, Send button, Covert mode toggle, Evidence capture buttons, Loading state, Error state |
| `LoginScreen` | Email/password fields, Validation errors, Submit button, Loading indicator, Error message display, Emergency bypass button |
| `HomeScreen` | Renders map, Shows user location, Shows nearby alerts, Degraded mode banner |
| `ChatScreen` | Message list, Send message, Read receipts, Offline indicator |
| `CommunityScreen` | Post feed, Create post, Like button, Comment section |
| `PermissionScreen` | Permission request dialogs, Grant/deny flow |

#### C. Integration Tests
- Test interactions between multiple services
- Use mocked HTTP but real local storage

**Key integration flows:**

1. **Auth → SOS Flow**: Login → Create SOS → Verify alert appears in active list
2. **Auth → Messaging Flow**: Login → Send message → Verify message stored locally
3. **Offline → Online Sync**: Create data offline → Come online → Verify sync to backend
4. **Push Notification Flow**: Receive FCM message → Display local notification → Tap notification → Navigate to correct screen

#### D. E2E Tests (integration_test)
- Run on real device or emulator
- Test complete user journeys

**Key E2E flows:**

1. Fresh install → Permission screen → Register → Login → Home screen
2. Login → SOS screen → Create alert → Verify alert sent
3. Login → Chat → Send message → Receive message
4. Login → Community → Create post → Verify in feed
5. Login → Settings → Update profile → Verify changes saved

---

## 4. ML Service (`ml_service/`) — Python

### Current State
- **Zero tests exist**
- No `test/` directory
- Uses FastAPI with scikit-learn, xgboost, prophet

### Required Test Structure

```
ml_service/
  tests/
    __init__.py
    test_predictor.py
    test_batch_predictor.py
    test_data_collector.py
    test_feature_engineer.py
    test_pipeline.py
    test_prophet_trainer.py
    test_xgboost_trainer.py
    test_schemas.py
    conftest.py
```

### Test Types

#### A. Unit Tests
- Test each module in isolation
- Use pytest with fixtures

| Module | Critical Test Cases |
|--------|-------------------|
| `predictor.py` | Single prediction, Input validation, Model loading failure |
| `batch_predictor.py` | Batch prediction, Empty batch, Large batch performance |
| `data_collector.py` | Data fetching, Missing values handling, Data normalization |
| `feature_engineer.py` | Feature extraction, Feature scaling, Invalid input |
| `pipeline.py` | Full pipeline execution, Partial failure recovery |
| `prophet_trainer.py` | Model training, Forecast generation, Parameter tuning |
| `xgboost_trainer.py` | Model training, Feature importance, Prediction confidence |
| `schemas.py` | Request validation, Response serialization, Error models |

#### B. Integration Tests
- Test API endpoints with FastAPI TestClient
- Test model inference end-to-end

| Endpoint | Test Cases |
|----------|-----------|
| POST /predict | Valid input, Invalid input, Model not loaded |
| POST /batch-predict | Batch valid, Batch with errors |
| GET /health | Service health check |
| POST /train | Training trigger, Training status |

---

## 5. Infrastructure & Deployment Tests

### Docker Compose
- Test that all services start correctly
- Test inter-service communication (backend → sos-service → ml_service)
- Test Nginx routing rules

### Existing Smoke Tests
- `deploy/scripts/smoke-test.sh` — Bash smoke test
- `deploy/scripts/smoke-test.ps1` — PowerShell smoke test
- `deploy/scripts/validate-deployment.sh` — Deployment validation

**Enhancements needed:**
- Add health check assertions for all services
- Add API endpoint response validation
- Add database migration verification
- Add MQTT connectivity test

---

## 6. Test Execution Strategy

### Phase 1: Backend Unit Tests (Highest Priority)
**Why first**: The backend is the core of the system. Catching bugs here prevents cascading failures.

```
cd backend && mvn test
```

**Target**: 80%+ code coverage on service layer, 70%+ on controller layer.

### Phase 2: Frontend Service Tests
**Why second**: Services contain the business logic. Catching bugs here prevents UI bugs.

```
cd frontend && flutter test test/services/
```

**Target**: 80%+ code coverage on service layer.

### Phase 3: Backend Integration Tests
```
cd backend && mvn verify
```

**Target**: All controller endpoints tested with success + error cases.

### Phase 4: Frontend Widget Tests
```
cd frontend && flutter test test/screens/ test/widgets/
```

**Target**: All screens tested for render, interaction, and error states.

### Phase 5: ML Service Tests
```
cd ml_service && pytest
```

**Target**: All prediction endpoints tested.

### Phase 6: SOS Service Tests
```
cd sos-service && mvn test
```

**Target**: All SOS-specific logic tested.

### Phase 7: E2E Tests
```
cd frontend && flutter test test/e2e/
```

**Target**: Critical user journeys verified end-to-end.

### Phase 8: Integration Smoke Tests
```
deploy/scripts/smoke-test.sh
```

**Target**: Full deployment pipeline validated.

---

## 7. CI/CD Integration

Add to `.github/workflows/`:

```yaml
# test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  backend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: '17', distribution: 'temurin' }
      - run: cd backend && mvn test

  sos-service-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: '17', distribution: 'temurin' }
      - run: cd sos-service && mvn test

  frontend-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x' }
      - run: cd frontend && flutter test

  ml-service-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: cd ml_service && pip install -r requirements.txt && pytest
```

---

## 8. Test Data Strategy

### Backend Tests
- Use H2 in-memory database (already configured in pom.xml)
- Use `@Sql` annotation to load test data scripts
- Use `@BeforeEach` to reset state between tests

### Frontend Tests
- Use `MockClient` from `http/testing.dart` for HTTP mocking
- Use `SharedPreferences.setMockInitialValues({})` for storage mocking
- Use `Mockito` for dependency injection mocking

### ML Service Tests
- Use pytest fixtures for model loading
- Use synthetic test data for predictions
- Use `tmp_path` fixture for file-based operations

---

## 9. Priority Order for Implementation

| Priority | Area | Effort | Impact |
|----------|------|--------|--------|
| **P0** | Backend Service Unit Tests | High | Catches business logic bugs |
| **P0** | Backend Controller Integration Tests | High | Catches API contract bugs |
| **P1** | Frontend Service Unit Tests | Medium | Catches client logic bugs |
| **P1** | SOS Service Tests | Medium | Catches alert processing bugs |
| **P2** | Frontend Widget Tests | Medium | Catches UI rendering bugs |
| **P2** | ML Service Tests | Low | Catches prediction bugs |
| **P3** | Frontend E2E Tests | High | Catches cross-service bugs |
| **P3** | CI/CD Pipeline | Low | Automates all the above |

---

## 10. Tools & Dependencies

### Backend (already in pom.xml)
- `spring-boot-starter-test` — JUnit 5, Mockito, AssertJ
- `spring-security-test` — Security test utilities
- `h2` — In-memory database for tests

### Frontend (already in pubspec.yaml)
- `flutter_test` — Flutter testing framework
- `mockito` — Mocking framework
- `integration_test` — E2E testing

### ML Service (need to add)
```
# requirements-test.txt
pytest
pytest-cov
httpx  # for TestClient
```

### SOS Service (already in pom.xml)
- `spring-boot-starter-test` — JUnit 5, Mockito, AssertJ
