# Blue Force Tracking (BFT) Module — Implementation Plan

> **System:** Danger Emergence System  
> **Context:** Military-grade friendly force tracking for Nigerian emergency response operations  
> **Target:** Flutter Android app + Spring Boot 3.2 backend + FastAPI ML service  
> **Threat Environment:** Boko Haram, ISWAP, Fulani Herdsmen insurgency

---

## Table of Contents

1. [Communication Architecture](#1-communication-architecture)
2. [Architecture Overview](#2-architecture-overview)
3. [Data Model & Database](#3-data-model--database)
4. [Backend API Specification](#4-backend-api-specification)
5. [Frontend Module Structure](#5-frontend-module-structure)
6. [Android Native Changes](#6-android-native-changes)
7. [User Model Extensions](#7-user-model-extensions)
8. [Data Flow Diagrams](#8-data-flow-diagrams)
9. [Security Model](#9-security-model)
10. [Offline & Mesh Behavior](#10-offline--mesh-behavior)
11. [Implementation Order](#11-implementation-order)
12. [File Change Summary](#12-file-change-summary)
13. [Hostile Force Tracking (HFT)](#13-hostile-force-tracking-hft)

---

## 1. Communication Architecture

This section details the complete communication stack between the Android phone and the backend server, covering all transport mechanisms, protocols, and techniques used to ensure reliable position data delivery in contested environments.

### 1.1 Network Topology

```mermaid
graph TB
    subgraph "Android Phone"
        APP[Flutter App]
        LS[LocationService.kt]
        BFT[BFTService Dart]
        MQTT_C[MQTT Client]
        WS_C[WebSocket Client]
        HTTP_C[HTTP Client]
        MESH[MeshManager Bluetooth/LoRa]
        OQ[Offline SQLite Queue]
    end

    subgraph "Internet Path"
        CELL[4G/LTE Cellular]
        SAT[Satellite BGAN]
        STARLINK[Starlink Terminal]
    end

    subgraph "Cloud Infrastructure"
        CF[Cloudflare CDN]
        NGINX[Nginx Reverse Proxy]
        BE[Spring Boot Backend]
        MQTT_B[Mosquitto MQTT Broker]
        WS_B[WebSocket Server]
        PG[(PostgreSQL)]
        REDIS[(Redis Cache)]
    end

    subgraph "Mesh Network"
        PEER1[Peer Device 1]
        PEER2[Peer Device 2]
        PEER3[Peer Device 3]
    end

    APP --> HTTP_C
    APP --> MQTT_C
    APP --> WS_C
    APP --> MESH
    LS -->|EventChannel| BFT
    BFT --> HTTP_C
    BFT --> MQTT_C
    BFT --> OQ

    HTTP_C -->|HTTPS :443| CF
    MQTT_C -->|MQTT over TLS :8883| CF
    WS_C -->|WSS :443| CF
    CF --> NGINX
    NGINX -->|/api/| BE
    NGINX -->|/ws/| WS_B
    NGINX -->|/mqtt/| MQTT_B
    BE --> PG
    BE --> REDIS
    BE --> MQTT_B

    CELL --> CF
    SAT --> CF
    STARLINK --> CF

    MESH -->|Bluetooth| PEER1
    MESH -->|Bluetooth| PEER2
    MESH -->|LoRa| PEER3
    PEER1 -->|Has Internet| CF
    PEER2 -->|Has Internet| CF
```

### 1.2 Transport Mechanisms

The system uses **four** distinct transport mechanisms, each serving a specific purpose in the BFT data pipeline:

| Transport | Protocol | Port | Encryption | Use Case | Priority |
|-----------|----------|------|------------|----------|----------|
| **HTTPS REST** | HTTP/1.1 + TLS 1.2 | 443 | TLS + JWT | Position reports, API calls, batch sync | Primary |
| **WebSocket** | STOMP over WSS | 443 | TLS + JWT | Real-time position updates, geofence alerts | Secondary |
| **MQTT** | MQTT 3.1.1 over TLS | 8883 | TLS + JWT | Lightweight heartbeat, buddy alerts | Tertiary |
| **Mesh** | Bluetooth / LoRa | N/A | End-to-end encrypt | Last-hop relay when no internet | Fallback |

### 1.3 HTTPS REST Communication Primary Path

This is the **primary** communication channel for BFT. All position reports, heartbeats, and API calls flow through this path.

#### 1.3.1 Full Request Lifecycle

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant BFT as BFTService Dart
    participant API as BackendApi Singleton
    participant TLS as TLS 1.2 Handshake
    participant CF as Cloudflare CDN
    participant Nginx as Nginx Reverse Proxy
    participant JWT as JwtAuthFilter
    participant Ctrl as BFTController
    participant Svc as BFTService
    participant DB as PostgreSQL

    Note over App,DB: Step 1: Position Report POST /api/v1/bft/position

    App->>BFT: Location from EventChannel
    BFT->>API: post/ bft/position, body: json
    API->>API: Build HTTP request
    API->>TLS: Establish TLS 1.2 connection
    TLS-->>API: Cipher suite negotiated
    API->>CF: HTTPS POST /api/v1/bft/position
    CF->>CF: DDoS protection, SSL termination
    CF->>Nginx: HTTP proxy pass
    Nginx->>Nginx: Rate limit check 30r/s
    Nginx->>Nginx: CORS header validation
    Nginx->>JWT: Forward request
    JWT->>JWT: Extract Bearer token
    JWT->>JWT: Validate JWT signature RS256
    JWT->>JWT: Check expiry, role claims
    JWT-->>Nginx: Authenticated principal
    Nginx->>Ctrl: POST /api/v1/bft/position
    Ctrl->>Svc: reportPosition
    Svc->>DB: INSERT position_reports
    DB-->>Svc: saved
    Svc-->>Ctrl: PositionReport entity
    Ctrl-->>Nginx: 200 JSON response
    Nginx-->>CF: Response
    CF-->>API: Response
    API-->>BFT: MapString, dynamic
    BFT-->>App: Position confirmed
```

#### 1.3.2 HTTP Request Format

Every BFT HTTP request follows this exact structure:

```
POST /api/v1/bft/position HTTP/1.1
Host: api.dangeremergence.com
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
Content-Type: application/json
X-Device-ID: device_a1b2c3d4
X-Request-ID: req_550e8400-e29b-41d4-a716-446655440000
Content-Length: 284
Accept-Encoding: gzip
User-Agent: DangerEmergence/1.0.0 Android/13

{
  "latitude": 9.05785,
  "longitude": 7.49508,
  "altitude": 560.2,
  "accuracy": 8.5,
  "speed": 1.2,
  "bearing": 45.0,
  "batteryLevel": 87.0,
  "source": "gps",
  "reportedAt": "2024-01-15T14:30:00.000Z"
}
```

#### 1.3.3 Response Format

```json
HTTP/1.1 200 OK
Content-Type: application/json

{
  "status": "ok",
  "positionId": "pos_660e8400-e29b-41d4-a716-446655440000"
}
```

#### 1.3.4 BackendApi Singleton Architecture

The [`BackendApi`](frontend/lib/shared/services/backend_api.dart) class is a **singleton** that all services use. It provides:

- **Auto JWT injection**: Every request gets `Authorization: Bearer <token>` from secure storage
- **Timeout handling**: 30s default timeout via `AppConstants.apiTimeout`
- **Error normalization**: Non-2xx responses throw `ApiException(statusCode, body)`
- **Gzip compression**: Enabled server-side via Nginx for responses > 1KB
- **Connection pooling**: HTTP client reuses connections via keep-alive

```dart
// BackendApi singleton pattern
class BackendApi {
  static final BackendApi _instance = BackendApi._();
  factory BackendApi() => _instance;
  BackendApi._();

  final String _baseUrl = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
  // https://api.dangeremergence.com/v1

  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }
}
```

### 1.4 WebSocket Communication Secondary Path

WebSocket provides **real-time** position updates without polling overhead. This is the secondary path, used when the app needs to receive position updates from other units immediately.

#### 1.4.1 WebSocket Connection Establishment

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant WS as WebSocket Client
    participant Nginx as Nginx
    participant WSCfg as WebSocketConfig.java
    participant Broker as STOMP Broker
    participant Ctrl as BFTController
    participant DB as PostgreSQL

    App->>WS: Connect to wss://api.dangeremergence.com/ws
    WS->>Nginx: HTTP Upgrade request
    Nginx->>Nginx: Connection: Upgrade
    Nginx->>Nginx: Upgrade: websocket
    Nginx->>WSCfg: WebSocket handshake
    WSCfg-->>WS: 101 Switching Protocols
    WS->>WSCfg: STOMP CONNECT
    WSCfg->>WSCfg: JWT auth from header
    WSCfg-->>WS: STOMP CONNECTED

    Note over WS,Broker: Subscribe to unit position topic
    WS->>Broker: SUBSCRIBE /topic/bft/unit/{unitId}
    WS->>Broker: SUBSCRIBE /user/queue/bft/alerts

    Note over Broker,DB: Real-time position broadcast
    Ctrl->>Broker: ConvertAndSendToUser userId, /queue/bft/position
    Broker->>WS: MESSAGE /user/queue/bft/position
    WS-->>App: PositionReport data
```

#### 1.4.2 WebSocket Configuration

The existing [`WebSocketConfig.java`](backend/src/main/java/com/dangeremergence/config/WebSocketConfig.java) already supports this:

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {
    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns("*")
                .withSockJS();
    }
}
```

#### 1.4.3 BFT WebSocket Topics

| Topic | Direction | Purpose | Auth Required |
|-------|-----------|---------|---------------|
| `/topic/bft/unit/{unitId}` | Server to Client | Position updates for all unit members | JWT + unit membership |
| `/user/queue/bft/position` | Server to Client | Personal position confirmation | JWT |
| `/user/queue/bft/alerts` | Server to Client | Geofence and buddy alerts | JWT |
| `/app/bft/subscribe` | Client to Server | Subscribe to unit tracking | JWT |

### 1.5 MQTT Communication Tertiary Path

MQTT is used for **lightweight, low-bandwidth** communication — ideal for heartbeat messages and simple alerts where full HTTP overhead is wasteful.

#### 1.5.1 MQTT Broker Configuration

The existing Mosquitto broker is configured at [`deploy/mosquitto/mosquitto.conf`](deploy/mosquitto/mosquitto.conf) and the backend connects via:

```yaml
# application.yml
mqtt:
  broker: ${MQTT_BROKER:tcp://localhost:1883}
  client-id: danger-emergence-backend
  topic-prefix: danger/emergence/
```

#### 1.5.2 BFT MQTT Topics

| Topic | QoS | Payload | Purpose |
|-------|-----|---------|---------|
| `danger/emergence/bft/heartbeat/{userId}` | 0 | `{"ts": 1705312200}` | Lightweight alive signal |
| `danger/emergence/bft/alert/{unitId}` | 1 | `{"type": "geofence", ...}` | Geofence breach alerts |
| `danger/emergence/bft/buddy/{userId}` | 1 | `{"buddyId": "...", "status": "stale"}` | Buddy alert notifications |

#### 1.5.3 MQTT vs HTTP Decision Matrix

| Criteria | HTTP REST | MQTT | WebSocket |
|----------|-----------|------|-----------|
| Bandwidth per message | ~400 bytes headers + body | ~50 bytes total | ~100 bytes frame |
| Battery impact | Medium WiFi/cellular radio | Low minimal keep-alive | Medium persistent connection |
| Reliability | High request-response ack | Medium QoS 0-2 levels | High session-aware |
| Latency | 100-500ms | 10-100ms | 10-50ms |
| Connection overhead | Per-request TCP handshake | Persistent lightweight TCP | Persistent TCP |
| Offline support | Queue and retry | Last Will + retain messages | Session reconnect |
| **BFT use case** | Position reports 30s | Heartbeat 60s | Real-time unit updates |

### 1.6 Mesh Network Communication Fallback Path

When no internet connectivity is available, the mesh network provides device-to-device communication.

#### 1.6.1 Mesh Relay Architecture

```mermaid
sequenceDiagram
    participant D1 as Device A No Internet
    participant D2 as Device B Has Internet
    participant BE as Backend

    Note over D1: GPS position acquired
    D1->>D1: Try HTTPS POST /bft/position
    D1->>D1: Connection failed timeout
    D1->>D1: Queue to SQLite offline_queue

    Note over D1,D2: Bluetooth discovery
    D1->>D2: Bluetooth broadcast: bft_position
    D2->>D2: Decrypt payload
    D2->>BE: POST /bft/position relayed=true
    BE-->>D2: 200 OK
    D2-->>D1: Bluetooth ACK

    Note over D1: Mark queued item as synced
    D1->>D1: UPDATE offline_queue SET synced=true
```

#### 1.6.2 Mesh Message Format for BFT

```dart
// MeshManager broadcasts BFT position as:
{
  "type": "bft_position",
  "senderDeviceId": "device_a1b2c3d4",
  "originalUserId": "user_550e8400",
  "payload": {
    "latitude": 9.05785,
    "longitude": 7.49508,
    "altitude": 560.2,
    "accuracy": 8.5,
    "speed": 1.2,
    "bearing": 45.0,
    "batteryLevel": 87.0,
    "source": "gps",
    "reportedAt": "2024-01-15T14:30:00.000Z"
  },
  "priority": 2,  // high
  "timestamp": 1705312200000
}
```

#### 1.6.3 Mesh Peer Discovery for BFT Relay

The [`MeshManager`](frontend/lib/modules/mesh/services/mesh_manager.dart) already supports peer discovery via Bluetooth. For BFT, we add:

```dart
/// Check if any mesh peer has internet connectivity for relay.
Future<String?> findRelayPeer() async {
  for (final peer in _knownPeers) {
    if (peer.hasInternetAccess && peer.linkQuality > 0.7) {
      return peer.deviceId;
    }
  }
  return null;
}
```

### 1.7 Network Resilience Strategy

#### 1.7.1 Connectivity Detection

```mermaid
flowchart TD
    A[Start BFT Tracking] --> B{Has Internet?}
    B -->|Yes| C[Use HTTPS REST]
    B -->|No| D{Has Mesh Peer?}
    D -->|Yes| E[Broadcast via Bluetooth/LoRa]
    D -->|No| F[Queue to SQLite]
    C --> G[Report success]
    E --> G
    F --> H[Retry every 30s]
    H --> B
    G --> I[Wait 30s for next report]
    I --> B
```

#### 1.7.2 Retry and Backoff Strategy

| Attempt | Wait Time | Action |
|---------|-----------|--------|
| 1st failure | Immediate retry | Try HTTPS again |
| 2nd failure | 5s delay | Try mesh relay |
| 3rd failure | 15s delay | Queue to SQLite |
| 4th+ failure | 30s delay | Stay queued, retry on connectivity change |
| On reconnect | Immediate flush | Batch upload all queued positions |

#### 1.7.3 Connection Health Monitoring

The [`SyncManager`](frontend/lib/shared/services/sync_manager.dart) monitors connectivity and triggers BFT queue flush:

```dart
// In BFTService, listen to connectivity changes:
void _onConnectivityRestored() {
  flushOfflineQueue();  // Batch upload queued positions
  _sendHeartbeat();     // Re-register with backend
  _pollNearbyForces();  // Refresh unit positions
}
```

### 1.8 Full Stack Communication Summary

```mermaid
graph LR
    subgraph "Layer 7 Application"
        BFT_DART[BFTService Dart]
        BFT_JAVA[BFTController Java]
    end

    subgraph "Layer 6 Transport Selection"
        HTTPS[HTTPS REST]
        WS[WebSocket STOMP]
        MQTT[MQTT]
        MESH[Mesh Bluetooth/LoRa]
    end

    subgraph "Layer 5 Session"
        JWT[JWT Auth Token]
        TLS_SESSION[TLS Session Resumption]
        MQTT_SESSION[MQTT Persistent Session]
    end

    subgraph "Layer 4 Transport"
        TCP[TCP :443]
        TCP_MQTT[TCP :8883]
        BT[Bluetooth RFCOMM]
    end

    subgraph "Layer 3 Network"
        IP[IPv4/IPv6]
        CELL_NET[Cellular 4G/LTE]
        SAT_NET[Satellite BGAN]
    end

    subgraph "Layer 1-2 Physical"
        CELL_PHY[Cellular Radio]
        SAT_PHY[Satellite Terminal]
        BT_PHY[Bluetooth 5.0]
        LORA[LoRa 868/915MHz]
    end

    BFT_DART --> HTTPS
    BFT_DART --> WS
    BFT_DART --> MQTT
    BFT_DART --> MESH
    HTTPS --> JWT
    WS --> JWT
    MQTT --> JWT
    HTTPS --> TLS_SESSION
    WS --> TLS_SESSION
    MQTT --> MQTT_SESSION
    TLS_SESSION --> TCP
    MQTT_SESSION --> TCP_MQTT
    MESH --> BT
    TCP --> IP
    TCP_MQTT --> IP
    IP --> CELL_NET
    IP --> SAT_NET
    CELL_NET --> CELL_PHY
    SAT_NET --> SAT_PHY
    BT --> BT_PHY
    MESH --> LORA
    BFT_JAVA --> HTTPS
    BFT_JAVA --> WS
    BFT_JAVA --> MQTT
```

### 1.9 Deployment Architecture

The full deployment stack showing how the Android phone reaches the backend:

```
Android Phone
    |
    +-- Cellular 4G/LTE ---+
    +-- Satellite BGAN -----+
    +-- Starlink WiFi ------+
    +-- Mesh Peer Relay ----+
                            |
                    +-------v--------+
                    |  Cloudflare    |
                    |  CDN + DDoS    |
                    |  SSL Term      |
                    +-------+--------+
                            |
                    +-------v--------+
                    |  Nginx Proxy   |
                    |  Rate Limit    |
                    |  CORS          |
                    |  Gzip          |
                    +-------+--------+
                            |
            +---------------+---------------+ 
            |               |               |
    +-------v------+ +------v------+ +------v------+
    |  /api/       | |  /ws/       | |  /mqtt/     |
    |  Spring Boot | |  WebSocket  | |  Mosquitto  |
    |  :8080       | |  :8080      | |  :1883      |
    +-------+------+ +-------------+ +-------------+
            |
    +-------v------+
    |  PostgreSQL  |
    |  :5432       |
    +--------------+
```

---

## 2. Architecture Overview

```mermaid
graph TB
    subgraph "Android Device"
        GPS[GPS Hardware]
        LS[LocationService.kt]
        EC[EventChannel]
        BFTDart[BFTService Dart]
        MapUI[MapScreen + BFT Overlay]
        Mesh[MeshManager]
        OQ[Offline Queue]
    end

    subgraph "Backend Spring Boot"
        BFTController[BFTController]
        BFTService[BFTService]
        PositionRepo[PositionReportRepository]
        GeofenceRepo[GeofenceRepository]
        BuddyRepo[BuddyAlertRepository]
        DB[(PostgreSQL)]
    end

    subgraph "Other Clients"
        CmdDash[Commander Dashboard]
        OtherUnits[Other Unit Members]
    end

    GPS -->|30s interval| LS
    LS -->|EventChannel| EC
    EC -->|location_update| BFTDart
    BFTDart -->|POST /bft/position| BFTController
    BFTDart -->|queue when offline| OQ
    OQ -->|batch upload on reconnect| BFTController
    Mesh -->|relay via peers| BFTDart
    BFTController --> BFTService
    BFTService --> PositionRepo
    BFTService --> GeofenceRepo
    BFTService --> BuddyRepo
    PositionRepo --> DB
    BFTController -->|GET /bft/nearby| CmdDash
    BFTController -->|GET /bft/unit/id| OtherUnits
    BFTDart -->|poll & render| MapUI
```

### Architecture Principles

| Principle | Description |
|-----------|-------------|
| **Backend is source of truth for all alerts** | All geofence breach detection, buddy proximity evaluation, stale/lost status calculation, and HFT threat assessment runs in Spring Boot Java services. The frontend never evaluates alert conditions independently. |
| **Frontend is a thin display client** | The Flutter app collects GPS data, sends it to the backend via API, and renders whatever the backend returns. No alert logic, no staleness calculation, no threat classification runs in Dart code. |
| **Backend pushes alerts via WebSocket** | When the backend detects an alert condition (geofence breach, buddy separation, HFT threat nearby), it pushes the alert to the frontend through WebSocket STOMP `/user/queue/bft/alerts`. The frontend simply displays the alert. |
| **Offline queue is temporary storage only** | When offline, the frontend queues position reports locally. Upon reconnection, it batch-uploads them to the backend. The backend then evaluates all queued positions for alert conditions. The frontend never evaluates alerts from queued data. |
| **API is the sole communication contract** | All data exchange between frontend and backend follows the REST API contract. The backend enriches responses with computed status fields (e.g., `status: "active"|"stale"|"lost"`) so the frontend only needs to render. |

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Position report interval | 30s (battery-optimized) | Military ops may last 24h+; 5s would drain battery in hours |
| Heartbeat interval | 60s (lightweight, no location) | Allows stale detection without constant location fix |
| Stale threshold | 2min to yellow, 10min to red, 30min to removed | Matches typical dismounted infantry movement patterns |
| Position storage | PostgreSQL (not TimescaleDB) | Minimizes new infrastructure; 100 positions/user is small |
| Alert evaluation location | **Backend Java service** | Centralized logic ensures all unit members receive consistent alerts regardless of device state |
| Real-time updates | WebSocket push from backend | Backend pushes alerts via `/user/queue/bft/alerts`; frontend subscribes passively |
| Offline queue | SQLite via existing OfflineStorageService | Reuses existing sync infrastructure; queue is flushed to backend for evaluation |
| Map rendering | Custom overlay on existing MapScreen | MapScreen already has Stack-based overlay pattern |

---

## 3. Data Model & Database

### 3.1 PositionReport Entity

**Java Entity:** [`backend/src/main/java/com/dangeremergence/model/PositionReport.java`](backend/src/main/java/com/dangeremergence/model/PositionReport.java)

```java
package com.dangeremergence.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "position_reports", indexes = {
    @Index(name = "idx_position_reports_user_id", columnList = "user_id"),
    @Index(name = "idx_position_reports_reported_at", columnList = "reported_at"),
    @Index(name = "idx_position_reports_user_reported", columnList = "user_id, reported_at DESC"),
    @Index(name = "idx_position_reports_unit_id", columnList = "unit_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PositionReport {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "user_id", nullable = false, length = 36)
    private String userId;

    @Column(name = "unit_id", length = 36)
    private String unitId;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    private Double altitude;

    private Float accuracy;

    private Float speed;

    private Float bearing;

    @Column(name = "battery_level")
    private Float batteryLevel;

    @Column(nullable = false, length = 20)
    @Enumerated(EnumType.STRING)
    private PositionSource source;

    @Column(name = "reported_at", nullable = false)
    private LocalDateTime reportedAt;

    @Column(name = "received_at", nullable = false)
    private LocalDateTime receivedAt;

    @Column(name = "is_batch")
    private Boolean isBatch = false;

    @PrePersist
    public void ensureId() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
        if (receivedAt == null) {
            receivedAt = LocalDateTime.now();
        }
    }

    public enum PositionSource {
        gps, network
    }
}
```

### 3.2 Geofence Entity

**Java Entity:** [`backend/src/main/java/com/dangeremergence/model/Geofence.java`](backend/src/main/java/com/dangeremergence/model/Geofence.java)

```java
package com.dangeremergence.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "geofences")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Geofence {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "unit_id", length = 36)
    private String unitId;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    @Column(nullable = false)
    private Double radius; // meters

    @Column(length = 20)
    @Enumerated(EnumType.STRING)
    private GeofenceType type;

    @Column(name = "created_by", nullable = false, length = 36)
    private String createdBy;

    @Column(name = "is_active")
    private Boolean isActive = true;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @PrePersist
    public void ensureId() {
        if (id == null) id = UUID.randomUUID().toString();
        if (createdAt == null) createdAt = LocalDateTime.now();
    }

    public enum GeofenceType {
        danger, safe, restricted, rally_point, ambush_alert
    }
}
```

### 3.3 BuddyAlert Entity

**Java Entity:** [`backend/src/main/java/com/dangeremergence/model/BuddyAlert.java`](backend/src/main/java/com/dangeremergence/model/BuddyAlert.java)

```java
package com.dangeremergence.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "buddy_alerts", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"user_id", "buddy_id"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BuddyAlert {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "user_id", nullable = false, length = 36)
    private String userId;

    @Column(name = "buddy_id", nullable = false, length = 36)
    private String buddyId;

    @Column(name = "is_active")
    private Boolean isActive = true;

    @Column(name = "last_movement_at")
    private LocalDateTime lastMovementAt;

    @Column(name = "alert_triggered")
    private Boolean alertTriggered = false;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    public void ensureId() {
        if (id == null) id = UUID.randomUUID().toString();
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
```

### 3.4 SQL Migration: V3__blue_force_tracking.sql

**File:** [`backend/src/main/resources/db/migration/V3__blue_force_tracking.sql`](backend/src/main/resources/db/migration/V3__blue_force_tracking.sql)

```sql
-- Flyway Migration V3: Blue Force Tracking
-- Adds position_reports, geofences, and buddy_alerts tables
-- Extends users table with military fields

-- ============================================================
-- 1. POSITION REPORTS
-- ============================================================
CREATE TABLE IF NOT EXISTS position_reports (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES users(id),
    unit_id VARCHAR(36),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    accuracy REAL,
    speed REAL,
    bearing REAL,
    battery_level REAL,
    source VARCHAR(20) NOT NULL DEFAULT 'gps',
    reported_at TIMESTAMP NOT NULL,
    received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_batch BOOLEAN DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_position_reports_user_id ON position_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_position_reports_reported_at ON position_reports(reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_position_reports_user_reported ON position_reports(user_id, reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_position_reports_unit_id ON position_reports(unit_id);
CREATE INDEX IF NOT EXISTS idx_position_reports_location ON position_reports(latitude, longitude);

-- ============================================================
-- 2. GEOFENCES
-- ============================================================
CREATE TABLE IF NOT EXISTS geofences (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    unit_id VARCHAR(36),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius DOUBLE PRECISION NOT NULL,
    type VARCHAR(20) DEFAULT 'danger',
    created_by VARCHAR(36) NOT NULL REFERENCES users(id),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_geofences_unit_id ON geofences(unit_id);
CREATE INDEX IF NOT EXISTS idx_geofences_active ON geofences(is_active);
CREATE INDEX IF NOT EXISTS idx_geofences_location ON geofences(latitude, longitude);

-- ============================================================
-- 3. BUDDY ALERTS
-- ============================================================
CREATE TABLE IF NOT EXISTS buddy_alerts (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES users(id),
    buddy_id VARCHAR(36) NOT NULL REFERENCES users(id),
    is_active BOOLEAN DEFAULT true,
    last_movement_at TIMESTAMP,
    alert_triggered BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, buddy_id)
);

CREATE INDEX IF NOT EXISTS idx_buddy_alerts_user ON buddy_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_buddy_alerts_buddy ON buddy_alerts(buddy_id);

-- ============================================================
-- 4. EXTEND USERS TABLE WITH MILITARY FIELDS
-- ============================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS military_role VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS unit_id VARCHAR(36);
ALTER TABLE users ADD COLUMN IF NOT EXISTS callsign VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS rank VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_users_unit_id ON users(unit_id);
CREATE INDEX IF NOT EXISTS idx_users_military_role ON users(military_role);
```

### 3.5 Repositories

**PositionReportRepository:** [`backend/src/main/java/com/dangeremergence/repository/PositionReportRepository.java`](backend/src/main/java/com/dangeremergence/repository/PositionReportRepository.java)

```java
package com.dangeremergence.repository;

import com.dangeremergence.model.PositionReport;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface PositionReportRepository extends JpaRepository<PositionReport, String> {

    @Query("SELECT p FROM PositionReport p WHERE p.userId = :userId ORDER BY p.reportedAt DESC")
    List<PositionReport> findRecentByUserId(@Param("userId") String userId, Pageable pageable);

    @Query("SELECT p FROM PositionReport p WHERE p.unitId = :unitId AND p.reportedAt > :since ORDER BY p.reportedAt DESC")
    List<PositionReport> findByUnitIdSince(@Param("unitId") String unitId, @Param("since") LocalDateTime since);

    @Query(value = """
        SELECT DISTINCT ON (p.user_id) p.*
        FROM position_reports p
        WHERE p.unit_id = :unitId
        ORDER BY p.user_id, p.reported_at DESC
    """, nativeQuery = true)
    List<PositionReport> findLatestByUnitId(@Param("unitId") String unitId);

    @Query(value = """
        SELECT p.* FROM position_reports p
        WHERE p.user_id = :userId
        ORDER BY p.reported_at DESC LIMIT 1
    """, nativeQuery = true)
    Optional<PositionReport> findLatestByUserId(@Param("userId") String userId);

    @Query("SELECT p FROM PositionReport p WHERE p.latitude BETWEEN :minLat AND :maxLat " +
           "AND p.longitude BETWEEN :minLng AND :maxLng " +
           "AND p.reportedAt > :since ORDER BY p.reportedAt DESC")
    List<PositionReport> findNearby(@Param("minLat") double minLat, @Param("maxLat") double maxLat,
                                    @Param("minLng") double minLng, @Param("maxLng") double maxLng,
                                    @Param("since") LocalDateTime since);

    @Query("SELECT COUNT(DISTINCT p.userId) FROM PositionReport p WHERE p.reportedAt > :since")
    long countActiveUsers(@Param("since") LocalDateTime since);

    void deleteByReportedAtBefore(LocalDateTime cutoff);
}
```

**GeofenceRepository:** [`backend/src/main/java/com/dangeremergence/repository/GeofenceRepository.java`](backend/src/main/java/com/dangeremergence/repository/GeofenceRepository.java)

```java
package com.dangeremergence.repository;

import com.dangeremergence.model.Geofence;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface GeofenceRepository extends JpaRepository<Geofence, String> {

    List<Geofence

    List<Geofence> findByUnitId(String unitId);

    List<Geofence> findByIsActiveTrue();

    List<Geofence> findByCreatedBy(String userId);

    @Query("SELECT g FROM Geofence g WHERE g.isActive = true AND " +
           "(g.expiresAt IS NULL OR g.expiresAt > :now)")
    List<Geofence> findActiveGeofences(@Param("now") LocalDateTime now);
}

**BuddyAlertRepository:** [ackend/src/main/java/com/dangeremergence/repository/BuddyAlertRepository.java](backend/src/main/java/com/dangeremergence/repository/BuddyAlertRepository.java)

`java
package com.dangeremergence.repository;

import com.dangeremergence.model.BuddyAlert;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
public interface BuddyAlertRepository extends JpaRepository<BuddyAlert, String> {

    List<BuddyAlert> findByUserId(String userId);

    Optional<BuddyAlert> findByUserIdAndBuddyId(String userId, String buddyId);

    List<BuddyAlert> findByBuddyIdAndAlertTriggered(String buddyId, boolean alertTriggered);

    List<BuddyAlert> findByUserIdAndIsActive(String userId, boolean isActive);
}
`

---

## 4. Backend API Specification

### 4.1 BFTController

**File:** [ackend/src/main/java/com/dangeremergence/controller/BFTController.java](backend/src/main/java/com/dangeremergence/controller/BFTController.java)

`java
package com.dangeremergence.controller;

import com.dangeremergence.model.PositionReport;
import com.dangeremergence.service.BFTService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/bft")
@RequiredArgsConstructor
public class BFTController {

    private final BFTService bftService;

    @PostMapping("/position")
    public ResponseEntity<?> reportPosition(
            @RequestBody PositionReport report,
            @AuthenticationPrincipal String userId) {
        report.setUserId(userId);
        PositionReport saved = bftService.reportPosition(report);
        return ResponseEntity.ok(Map.of("status", "ok", "positionId", saved.getId()));
    }

    @PostMapping("/position/batch")
    public ResponseEntity<?> reportBatchPositions(
            @RequestBody List<PositionReport> reports,
            @AuthenticationPrincipal String userId) {
        reports.forEach(r -> r.setUserId(userId));
        int count = bftService.reportBatchPositions(reports);
        return ResponseEntity.ok(Map.of("status", "ok", "count", count));
    }

    @GetMapping("/nearby")
    public ResponseEntity<?> getNearbyForces(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "1000") double radiusMeters,
            @AuthenticationPrincipal String userId) {
        List<PositionReport> nearby = bftService.getNearbyForces(lat, lng, radiusMeters, userId);
        return ResponseEntity.ok(nearby);
    }

    @GetMapping("/unit/{unitId}")
    public ResponseEntity<?> getUnitPositions(@PathVariable String unitId) {
        List<PositionReport> positions = bftService.getUnitPositions(unitId);
        return ResponseEntity.ok(positions);
    }

    @GetMapping("/heartbeat")
    public ResponseEntity<?> heartbeat(@AuthenticationPrincipal String userId) {
        bftService.updateHeartbeat(userId);
        return ResponseEntity.ok(Map.of("status", "alive", "timestamp", LocalDateTime.now()));
    }

    @PostMapping("/geofence")
    public ResponseEntity<?> createGeofence(@RequestBody Geofence geofence,
                                             @AuthenticationPrincipal String userId) {
        geofence.setCreatedBy(userId);
        Geofence saved = bftService.createGeofence(geofence);
        return ResponseEntity.ok(saved);
    }

    @GetMapping("/geofence/active")
    public ResponseEntity<?> getActiveGeofences() {
        return ResponseEntity.ok(bftService.getActiveGeofences());
    }

    @PostMapping("/buddy")
    public ResponseEntity<?> addBuddy(@RequestBody Map<String, String> body,
                                       @AuthenticationPrincipal String userId) {
        BuddyAlert buddy = bftService.addBuddy(userId, body.get("buddyId"));
        return ResponseEntity.ok(buddy);
    }

    @GetMapping("/buddy/alerts")
    public ResponseEntity<?> getBuddyAlerts(@AuthenticationPrincipal String userId) {
        return ResponseEntity.ok(bftService.getBuddyAlerts(userId));
    }

    @GetMapping("/status")
    public ResponseEntity<?> getBFTStatus(@AuthenticationPrincipal String userId) {
        return ResponseEntity.ok(bftService.getBFTStatus(userId));
    }
}
`


### 4.2 BFTService

**File:** [ackend/src/main/java/com/dangeremergence/service/BFTService.java](backend/src/main/java/com/dangeremergence/service/BFTService.java)

`java
package com.dangeremergence.service;

import com.dangeremergence.model.*;
import com.dangeremergence.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class BFTService {

    private final PositionReportRepository positionRepo;
    private final GeofenceRepository geofenceRepo;
    private final BuddyAlertRepository buddyRepo;
    private final UserRepository userRepo;

    private static final long STALE_THRESHOLD_SECONDS = 120;
    private static final long LOST_THRESHOLD_SECONDS = 600;
    private static final long REMOVAL_THRESHOLD_SECONDS = 1800;

    @Transactional
    public PositionReport reportPosition(PositionReport report) {
        report.setReceivedAt(LocalDateTime.now());
        PositionReport saved = positionRepo.save(report);
        checkGeofences(report);
        checkBuddyProximity(report);
        return saved;
    }

    @Transactional
    public int reportBatchPositions(List<PositionReport> reports) {
        reports.forEach(r -> r.setReceivedAt(LocalDateTime.now()));
        positionRepo.saveAll(reports);
        return reports.size();
    }

    public List<PositionReport> getNearbyForces(double lat, double lng, double radiusMeters, String userId) {
        double latDelta = radiusMeters / 111_320.0;
        double lngDelta = radiusMeters / (111_320.0 * Math.cos(Math.toRadians(lat)));
        LocalDateTime since = LocalDateTime.now().minusSeconds(REMOVAL_THRESHOLD_SECONDS);
        return positionRepo.findNearby(lat - latDelta, lat + latDelta,
                                       lng - lngDelta, lng + lngDelta, since)
                .stream()
                .filter(p -> !p.getUserId().equals(userId))
                .collect(Collectors.toList());
    }

    public List<PositionReport> getUnitPositions(String unitId) {
        LocalDateTime since = LocalDateTime.now().minusSeconds(REMOVAL_THRESHOLD_SECONDS);
        return positionRepo.findByUnitIdSince(unitId, since);
    }

    public void updateHeartbeat(String userId) {
        userRepo.findById(userId).ifPresent(user -> {
            user.setLastSeen(LocalDateTime.now());
            userRepo.save(user);
        });
    }

    @Transactional
    public Geofence createGeofence(Geofence geofence) {
        return geofenceRepo.save(geofence);
    }

    public List<Geofence> getActiveGeofences() {
        return geofenceRepo.findActiveGeofences(LocalDateTime.now());
    }

    @Transactional
    public BuddyAlert addBuddy(String userId, String buddyId) {
        BuddyAlert buddy = BuddyAlert.builder()
                .userId(userId)
                .buddyId(buddyId)
                .isActive(true)
                .build();
        return buddyRepo.save(buddy);
    }

    public List<BuddyAlert> getBuddyAlerts(String userId) {
        return buddyRepo.findByUserId(userId);
    }

    public Map<String, Object> getBFTStatus(String userId) {
        Map<String, Object> status = new HashMap<>();
        Optional<PositionReport> latest = positionRepo.findLatestByUserId(userId);
        status.put("hasPosition", latest.isPresent());
        latest.ifPresent(r -> {
            status.put("lastReportedAt", r.getReportedAt());
            long secondsSince = java.time.Duration.between(r.getReportedAt(), LocalDateTime.now()).getSeconds();
            status.put("secondsSinceReport", secondsSince);
            status.put("status", secondsSince < STALE_THRESHOLD_SECONDS ? "active" :
                                  secondsSince < LOST_THRESHOLD_SECONDS ? "stale" : "lost");
        });
        status.put("buddyCount", buddyRepo.findByUserIdAndIsActive(userId, true).size());
        status.put("activeGeofences", geofenceRepo.findActiveGeofences(LocalDateTime.now()).size());
        return status;
    }

    private void checkGeofences(PositionReport report) {
        List<Geofence> active = geofenceRepo.findActiveGeofences(LocalDateTime.now());
        for (Geofence g : active) {
            double distance = haversine(report.getLatitude(), report.getLongitude(),
                                        g.getLatitude(), g.getLongitude());
            if (distance <= g.getRadius()) {
                // Trigger geofence alert via WebSocket/MQTT
            }
        }
    }

    private void checkBuddyProximity(PositionReport report) {
        List<BuddyAlert> buddies = buddyRepo.findByUserIdAndIsActive(report.getUserId(), true);
        for (BuddyAlert buddy : buddies) {
            Optional<PositionReport> buddyPos = positionRepo.findLatestByUserId(buddy.getBuddyId());
            buddyPos.ifPresent(bp -> {
                double distance = haversine(report.getLatitude(), report.getLongitude(),
                                            bp.getLatitude(), bp.getLongitude());
                if (distance > 500) { // Buddy separated by more than 500m
                    buddy.setAlertTriggered(true);
                    buddyRepo.save(buddy);
                }
            });
        }
    }

    private double haversine(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    }
}
`

### 4.3 API Endpoint Summary

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | /api/v1/bft/position | JWT | Report current position |
| POST | /api/v1/bft/position/batch | JWT | Batch upload queued positions |
| GET | /api/v1/bft/nearby?lat=&lng=&radius= | JWT | Get nearby friendly forces |
| GET | /api/v1/bft/unit/{unitId} | JWT | Get all unit member positions |
| GET | /api/v1/bft/heartbeat | JWT | Lightweight alive signal |
| POST | /api/v1/bft/geofence | JWT+COMMANDER | Create geofence |
| GET | /api/v1/bft/geofence/active | JWT | Get active geofences |
| POST | /api/v1/bft/buddy | JWT | Add buddy for proximity alerts |
| GET | /api/v1/bft/buddy/alerts | JWT | Get buddy proximity alerts |
| GET | /api/v1/bft/status | JWT | Get personal BFT status |

---

## 5. Frontend Module Structure

### 5.1 New Files

| File | Purpose |
|------|---------|
| rontend/lib/modules/bft/services/bft_service.dart | Core BFT service: tracking, reporting, polling |
| rontend/lib/modules/bft/services/bft_overlay.dart | Map overlay renderer for BFT dots |
| rontend/lib/modules/bft/models/bft_models.dart | Dart models: BFTUnitMember, BFTStatus |
| rontend/lib/modules/bft/screens/bft_status_screen.dart | Status screen showing unit roster |

### 5.2 BFTService Dart

**File:** [rontend/lib/modules/bft/services/bft_service.dart](frontend/lib/modules/bft/services/bft_service.dart)

`dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../core/constants.dart';
import '../models/bft_models.dart';

/// Thin client BFT service.
///
/// Architecture: All alert logic runs in the backend (Spring Boot Java).
/// The frontend ONLY:
///   1. Collects GPS data from LocationService.kt via EventChannel
///   2. Sends position reports to backend via REST API
///   3. Subscribes to WebSocket for pushed alerts from backend
///   4. Renders whatever the backend returns (no local staleness calculation)
class BFTService extends ChangeNotifier {
  final BackendApi _api = BackendApi();
  final OfflineStorageService _offline = OfflineStorageService();

  Timer? _reportTimer;
  Timer? _heartbeatTimer;
  Timer? _pollTimer;

  List<BFTUnitMember> _nearbyForces = [];
  BFTStatus? _myStatus;

  List<BFTUnitMember> get nearbyForces => _nearbyForces;
  BFTStatus? get myStatus => _myStatus;

  void startTracking() {
    _reportTimer = Timer.periodic(
      Duration(seconds: AppConstants.bftReportInterval), _reportPosition);
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: AppConstants.bftHeartbeatInterval), (_) => _sendHeartbeat());
    _pollTimer = Timer.periodic(
      Duration(seconds: AppConstants.bftPollInterval), (_) => _pollNearbyForces());
    _subscribeToAlerts();  // Listen for backend-pushed alerts via WebSocket
  }

  void stopTracking() {
    _reportTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _unsubscribeFromAlerts();
  }

  Future<void> _reportPosition(Timer timer) async {
    // Get latest location from platform channel
    // Send to backend via POST /bft/position
    // Backend evaluates geofences, buddy proximity, and staleness
  }

  Future<void> _sendHeartbeat() async {
    try {
      await _api.get('/bft/heartbeat');
    } catch (_) {}
  }

  /// Poll nearby forces from backend.
  /// Backend returns pre-computed status (active/stale/lost) per unit member.
  /// Frontend NEVER calculates staleness locally.
  Future<void> _pollNearbyForces() async {
    try {
      final response = await _api.get('/bft/nearby',
        queryParams: {'lat': '...', 'lng': '...', 'radius': '1000'});
      _nearbyForces = (response as List)
          .map((e) => BFTUnitMember.fromJson(e))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Subscribe to backend-pushed alerts via WebSocket STOMP.
  /// Backend pushes: geofence breach, buddy separation, HFT threat detected.
  void _subscribeToAlerts() {
    // STOMP subscribe to /user/queue/bft/alerts
    // On message: parse alert type, notify UI to show alert dialog/banner
  }

  void _unsubscribeFromAlerts() {
    // STOMP unsubscribe from /user/queue/bft/alerts
  }

  Future<void> flushOfflineQueue() async {
    final queued = await _offline.getQueuedItems('bft_position');
    if (queued.isEmpty) return;
    try {
      await _api.post('/bft/position/batch', body: queued);
      await _offline.clearQueue('bft_position');
    } catch (_) {}
  }
}
`

### 5.3 BFT Models

**File:** [rontend/lib/modules/bft/models/bft_models.dart](frontend/lib/modules/bft/models/bft_models.dart)

`dart
class BFTUnitMember {
  final String userId;
  final String? callsign;
  final String? rank;
  final String? unitId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final double batteryLevel;
  final String source;
  final DateTime reportedAt;
  final BFTStatusEnum status;

  BFTUnitMember({
    required this.userId,
    this.callsign,
    this.rank,
    this.unitId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.batteryLevel,
    required this.source,
    required this.reportedAt,
    required this.status,
  });

  /// Backend returns pre-computed status.
  /// Frontend NEVER calculates staleness — the backend is the source of truth.
  factory BFTUnitMember.fromJson(Map<String, dynamic> json) {
    return BFTUnitMember(
      userId: json['userId'],
      callsign: json['callsign'],
      rank: json['rank'],
      unitId: json['unitId'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      bearing: (json['bearing'] as num?)?.toDouble(),
      batteryLevel: (json['batteryLevel'] as num).toDouble(),
      source: json['source'],
      reportedAt: DateTime.parse(json['reportedAt']),
      status: BFTStatusEnum.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => BFTStatusEnum.active,
      ),
    );
  }
}

enum BFTStatusEnum { active, stale, lost, removed }

class BFTStatus {
  final bool hasPosition;
  final DateTime? lastReportedAt;
  final int secondsSinceReport;
  final String status;
  final int buddyCount;
  final int activeGeofences;

  BFTStatus({
    required this.hasPosition,
    this.lastReportedAt,
    required this.secondsSinceReport,
    required this.status,
    required this.buddyCount,
    required this.activeGeofences,
  });

  factory BFTStatus.fromJson(Map<String, dynamic> json) => BFTStatus(
    hasPosition: json['hasPosition'],
    lastReportedAt: json['lastReportedAt'] != null
        ? DateTime.parse(json['lastReportedAt']) : null,
    secondsSinceReport: json['secondsSinceReport'],
    status: json['status'],
    buddyCount: json['buddyCount'],
    activeGeofences: json['activeGeofences'],
  );
}
`

### 5.4 BFT Map Overlay

**File:** [rontend/lib/modules/bft/services/bft_overlay.dart](frontend/lib/modules/bft/services/bft_overlay.dart)

The overlay renders colored dots on the existing [MapScreen](frontend/lib/modules/maps/screens/map_screen.dart):

- **Green dot**: Active (position < 2min old) -- Color(0xFF00FF00)
- **Yellow dot**: Stale (2-10min old) -- Color(0xFFFFD700)
- **Red dot**: Lost (10-30min old) -- Color(0xFFFF0000)
- **No dot**: Removed (>30min old) -- not rendered

Each dot shows:
- Callsign label above the dot
- Battery level indicator (icon color: green >50%, yellow 20-50%, red <20%)
- Direction arrow (bearing indicator)
- Tapping a dot opens a detail popup with full unit info

### 5.5 Integration with MapScreen

The existing [MapScreen](frontend/lib/modules/maps/screens/map_screen.dart) uses a Stack with Positioned overlays. The BFT overlay adds:

`dart
// In map_screen.dart, add BFT overlay layer:
Positioned(
  left: 0, right: 0, top: 0, bottom: 0,
  child: BFTMapOverlay(
    unitMembers: bftService.nearbyForces,
    onMemberTap: _showUnitDetail,
  ),
)
`

### 5.6 Constants Additions

Add to [rontend/lib/core/constants.dart](frontend/lib/core/constants.dart):

`dart
// BFT Constants
static const int bftReportInterval = 30;         // seconds between position reports
static const int bftHeartbeatInterval = 60;       // seconds between heartbeats
static const int bftPollInterval = 15;            // seconds between nearby force polls
static const int bftStaleThreshold = 120;         // seconds before marked stale
static const int bftLostThreshold = 600;          // seconds before marked lost
static const int bftRemovalThreshold = 1800;      // seconds before removed from map
static const int bftBuddyStaleMinutes = 5;        // minutes before buddy alert triggers
static const int bftMaxOfflineQueue = 1000;       // max queued positions
static const int bftBatchSize = 50;               // max positions per batch upload
static const double bftNearbyRadiusDefault = 1000.0; // default nearby search radius
`

---

## 6. Android Native Changes

### 6.1 LocationService.kt Extensions

Add to [LocationService.kt](frontend/android/app/src/main/kotlin/com/dangeremergence/location/LocationService.kt):

`kotlin
// New action constants for BFT
const val ACTION_START_BFT_TRACKING = "com.dangeremergence.action.START_BFT_TRACKING"
const val ACTION_STOP_BFT_TRACKING = "com.dangeremergence.action.STOP_BFT_TRACKING"

// In onStartCommand, add handler:
when (action) {
    ACTION_START_BFT_TRACKING -> startBftTracking()
    ACTION_STOP_BFT_TRACKING -> stopBftTracking()
    // ... existing SOS actions
}

private fun startBftTracking() {
    // Use 30-second interval for BFT (vs 5s for SOS)
    updateInterval(30000L)  // 30 seconds
    registerLocationListeners()
    val notification = buildNotification(sosMode = false)
    startForeground(NOTIFICATION_ID, notification)
}

private fun stopBftTracking() {
    stopTracking()
}
`

### 6.2 EventChannel Updates

The existing EventChannel com.dangeremergence/location_updates already broadcasts location data. For BFT, we add a new event type:

`kotlin
// In broadcastLocation(), add BFT-specific event:
private fun broadcastLocation(location: Location) {
    val map = HashMap<String, Any>().apply {
        put("latitude", location.latitude)
        put("longitude", location.longitude)
        put("altitude", location.altitude)
        put("accuracy", location.accuracy)
        put("speed", location.speed)
        put("bearing", location.bearing)
        put("batteryLevel", getBatteryLevel())
        put("source", location.provider ?: "gps")
        put("timestamp", System.currentTimeMillis())
        put("trackingMode", currentTrackingMode) // "bft" or "sos"
    }
    // Send to both SOS and BFT listeners
    eventSink?.success(map)
}
`

---

## 7. User Model Extensions

### 7.1 Extended UserRole

Add to [User.java](backend/src/main/java/com/dangeremergence/model/User.java):

`java
// Extended roles for BFT
public enum UserRole {
    citizen,
    responder,
    coordinator,
    // New military roles:
    soldier,
    commander,
    medic,
    intel_officer
}

// New fields
@Column(name = "military_role", length = 50)
private String militaryRole;  // e.g., "infantry", "recon", "medic"

@Column(name = "unit_id", length = 36)
private String unitId;        // e.g., "3rd-battalion-alpha"

@Column(name = "callsign", length = 50)
private String callsign;      // e.g., "Eagle-6"

@Column(name = "rank", length = 50)
private String rank;          // e.g., "Captain", "Sergeant"
`

### 7.2 SecurityConfig Role-Based Access

Add to [SecurityConfig.java](backend/src/main/java/com/dangeremergence/config/SecurityConfig.java):

`java
// BFT endpoints - require authentication
.requestMatchers("/api/v1/bft/**").authenticated()

// Commander-only endpoints
.requestMatchers("/api/v1/bft/geofence/**").hasAnyRole("COMMANDER", "INTEL_OFFICER")

// Public health check
.requestMatchers("/api/v1/bft/health").permitAll()
`


---

## 8. Data Flow Diagrams

### 8.1 Position Report Flow (Online)

`mermaid
sequenceDiagram
    participant GPS as GPS Hardware
    participant LS as LocationService.kt
    participant EC as EventChannel
    participant BFT as BFTService Dart
    participant API as BackendApi
    participant Ctrl as BFTController
    participant DB as PostgreSQL

    Note over GPS,DB: Every 30 seconds
    GPS->>LS: Location fix
    LS->>EC: broadcastLocation
    EC->>BFT: location_update event
    BFT->>BFT: Build PositionReport JSON
    BFT->>API: POST /bft/position
    API->>Ctrl: HTTP request
    Ctrl->>Ctrl: Validate JWT
    Ctrl->>DB: INSERT position_reports
    DB-->>Ctrl: saved
    Ctrl-->>API: 200 OK
    API-->>BFT: {positionId: "..."}
    BFT->>BFT: Update local state
    BFT->>BFT: notifyListeners
`

### 8.2 Position Report Flow (Offline)

`mermaid
sequenceDiagram
    participant GPS as GPS Hardware
    participant LS as LocationService.kt
    participant BFT as BFTService Dart
    participant OQ as Offline SQLite Queue
    participant MESH as MeshManager
    participant PEER as Mesh Peer

    Note over GPS,PEER: Every 30 seconds
    GPS->>LS: Location fix
    LS->>BFT: location_update
    BFT->>BFT: Try POST /bft/position
    BFT->>BFT: Connection failed
    BFT->>OQ: INSERT INTO offline_queue
    Note over BFT: Check for mesh relay peer
    BFT->>MESH: findRelayPeer
    MESH-->>BFT: peer device found
    BFT->>MESH: broadcast bft_position
    MESH->>PEER: Bluetooth message
    PEER->>PEER: Has internet, relay to backend
    PEER-->>MESH: ACK
    MESH-->>BFT: relay confirmed
    BFT->>OQ: Mark item as synced
`

### 8.3 Nearby Forces Polling Flow

```mermaid
sequenceDiagram
    participant BFT as BFTService Dart
    participant API as BackendApi
    participant Ctrl as BFTController
    participant Svc as BFTService Java
    participant DB as PostgreSQL
    participant Map as MapScreen

    Note over BFT,Map: Every 15 seconds - frontend polls backend
    BFT->>API: GET /bft/nearby?lat=9.05&lng=7.49&radius=1000
    API->>Ctrl: HTTP request
    Ctrl->>Svc: getNearbyForces()
    Svc->>DB: Query nearby positions
    DB-->>Svc: List of PositionReport
    Note over Svc: Backend computes status per position:<br/>active (<2min), stale (2-10min), lost (10-30min)<br/>removed (>30min, excluded from results)
    Svc->>Svc: Enrich each report with:<br/>- status (active/stale/lost)<br/>- callsign, rank from User table<br/>- distance from query point
    Svc-->>Ctrl: Enriched PositionReport list
    Ctrl-->>API: JSON array with pre-computed status
    API-->>BFT: List of unit members
    Note over BFT: Frontend ONLY renders -<br/>NO local staleness calculation
    BFT->>BFT: Update _nearbyForces
    BFT->>Map: notifyListeners
    Map->>Map: Re-render BFT overlay with status colors from backend
```

### 8.4 Geofence Alert Flow

`mermaid
sequenceDiagram
    participant BFT as BFTService Dart
    participant API as BackendApi
    participant Ctrl as BFTController
    participant Svc as BFTService Java
    participant WS as WebSocket
    participant User as Unit Member

    BFT->>API: POST /bft/position
    API->>Ctrl: reportPosition
    Ctrl->>Svc: reportPosition
    Svc->>Svc: checkGeofences
    Svc->>Svc: haversine distance check
    Note over Svc: Position is within geofence radius
    Svc->>WS: ConvertAndSendToUser
    WS-->>User: Geofence alert message
    User->>User: Show alert notification
`

---

## 9. Security Model

### 9.1 Authentication

| Layer | Mechanism | Details |
|-------|-----------|---------|
| Transport | TLS 1.2+ | All BFT traffic encrypted in transit |
| API Auth | JWT Bearer Token | RS256 signed, 15min expiry |
| Role Auth | Spring Security | Role-based endpoint access |
| Device Auth | X-Device-ID header | Device binding for audit trail |

### 9.2 Authorization Matrix

| Endpoint | soldier | medic | commander | intel_officer |
|----------|---------|-------|-----------|---------------|
| POST /bft/position | YES | YES | YES | YES |
| GET /bft/nearby | YES | YES | YES | YES |
| GET /bft/unit/{id} | YES | YES | YES | YES |
| GET /bft/heartbeat | YES | YES | YES | YES |
| POST /bft/geofence | NO | NO | YES | YES |
| GET /bft/geofence | YES | YES | YES | YES |
| POST /bft/buddy | YES | YES | YES | YES |
| GET /bft/status | YES | YES | YES | YES |

### 9.3 Data Privacy

- Position data is **never** exposed to non-unit members
- Historical positions are auto-purged after 30 days
- Batch uploads are rate-limited to 50 positions per request
- Mesh-relayed positions include 
elayed=true flag for audit

---

## 10. Offline & Mesh Behavior

> **Architecture Rule:** The backend is the **sole source of truth** for all alert state. The frontend's offline queue is temporary storage only — it holds raw position data until connectivity is restored, then flushes to the backend for evaluation.

### 10.1 Offline Queue Strategy

| Scenario | Action | Recovery |
|----------|--------|----------|
| No internet | Queue raw position to SQLite offline_queue table | Flush on connectivity restored |
| Queue full (1000 items) | Drop oldest, keep newest | FIFO eviction |
| Batch upload | POST /bft/position/batch (max 50) | Backend evaluates all positions for alerts |
| App killed | Queue persists in SQLite | Resume on next app launch, flush to backend |
| **Alert during offline** | **No local alert evaluation** | Backend evaluates when batch is uploaded |

### 10.2 Mesh Relay Strategy

| Scenario | Action | Details |
|----------|--------|---------|
| No internet, peer available | Broadcast raw position via Bluetooth | MeshManager handles discovery |
| Multiple peers available | Select peer with best link quality | Link quality > 0.7 threshold |
| Peer relay confirmed | Mark offline item as synced | Prevents duplicate upload |
| **Alert via mesh** | **Peer relays position to backend; backend evaluates and pushes alert back** | Alert reaches device via WebSocket when peer has internet |
| No peer available | Keep in queue, retry every 30s | Connectivity listener triggers flush |

### 10.3 Stale Detection (Backend-Computed)

> **Important:** Stale/lost/removed status is computed by the **backend BFTService Java** on every `/bft/nearby` query and on every position report. The frontend receives pre-computed `status` fields in API responses and WebSocket pushes. The frontend NEVER computes staleness locally.

| Time Since Last Report | Status (Backend-Computed) | Map Color | Backend Action |
|-----------------------|---------------------------|-----------|----------------|
| < 2 minutes | `active` | Green | Normal processing |
| 2 - 10 minutes | `stale` | Yellow | Include in nearby results with `status: "stale"` |
| 10 - 30 minutes | `lost` | Red | Include in nearby results with `status: "lost"`; push alert via WebSocket to buddies |
| > 30 minutes | `removed` | Not shown | Exclude from query results; auto-purge from DB after retention period |

---

## 11. Implementation Order

> **Architecture Priority:** Backend-first. All alert logic (geofence breach, buddy proximity, staleness, HFT threat assessment) must be implemented and tested in the backend **before** the frontend is built. The frontend is a thin client that only sends data and renders responses.

### Phase 1: Backend Foundation — Data Layer (Day 1-2)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 1.1 | Create V3 migration SQL | V3__blue_force_tracking.sql | None |
| 1.2 | Create PositionReport entity | PositionReport.java | V3 migration |
| 1.3 | Create Geofence entity | Geofence.java | V3 migration |
| 1.4 | Create BuddyAlert entity | BuddyAlert.java | V3 migration |
| 1.5 | Create PositionReportRepository | PositionReportRepository.java | Entities |
| 1.6 | Create GeofenceRepository | GeofenceRepository.java | Entities |
| 1.7 | Create BuddyAlertRepository | BuddyAlertRepository.java | Entities |

### Phase 2: Backend Core — Alert Logic (Day 2-3)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 2.1 | Create BFTService with geofence + buddy alert logic | BFTService.java | Repositories |
| 2.2 | Create BFTController | BFTController.java | BFTService |
| 2.3 | Add WebSocket alert push to BFTService (SimpMessagingTemplate) | BFTService.java, WebSocketConfig.java | BFTService |
| 2.4 | Update SecurityConfig for BFT routes | SecurityConfig.java | BFTController |
| 2.5 | Extend User model with military fields | User.java | V3 migration |
| 2.6 | Update AuthController for military fields | AuthController.java | User model |
| 2.7 | Unit tests for BFTService Java | BFTServiceTest.java | BFTService |

### Phase 3: Frontend — Thin Client (Day 4-5)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 3.1 | Add BFT constants | constants.dart | None |
| 3.2 | Create BFT models (receive pre-computed status from backend) | bft_models.dart | None |
| 3.3 | Create BFTService Dart (send-only, no alert logic) | bft_service.dart | BackendApi |
| 3.4 | Add WebSocket STOMP subscription for alerts | bft_service.dart | WebSocketConfig |
| 3.5 | Create BFT map overlay (render-only) | bft_overlay.dart | MapScreen |
| 3.6 | Integrate BFT overlay into MapScreen | map_screen.dart | BFT overlay |
| 3.7 | Register BFTService in main.dart providers | main.dart | BFTService |

### Phase 4: Android Native (Day 5)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 4.1 | Add BFT tracking actions to LocationService | LocationService.kt | None |
| 4.2 | Add BFT event type to EventChannel | LocationService.kt | None |

### Phase 5: Offline & Mesh (Day 6)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 5.1 | Add BFT queue flush to SyncManager | sync_manager.dart | BFTService Dart |
| 5.2 | Add BFT position relay to MeshManager | mesh_manager.dart | MeshManager |

### Phase 6: HFT — Backend First (Day 6-7)

| Step | Task | Files | Depends On |
|------|------|-------|------------|
| 6.1 | Create V4 migration SQL | V4__hostile_force_tracking.sql | None |
| 6.2 | Create RFSighting, HostileThreat, ThreatSignature entities | Java entities | V4 migration |
| 6.3 | Create HFT repositories | Java repositories | Entities |
| 6.4 | Create HFTService Java (triangulation + proximity alert) | HFTService.java | Repositories |
| 6.5 | Create HFTController | HFTController.java | HFTService |
| 6.6 | Add HFT WebSocket alert push | HFTService.java | WebSocketConfig |
| 6.7 | Update SecurityConfig for HFT routes | SecurityConfig.java | HFTController |
| 6.8 | Add Bluetooth scanning to MeshForegroundService | MeshForegroundService.kt | Android BT permissions |
| 6.9 | Create HFT Wi-Fi scanner (sends raw data to backend) | hft_wifi_scanner.dart | wifi_iot package |
| 6.10 | Create HFT Dart service (send-only, receives alerts via WebSocket) | hft_service.dart | BackendApi |
| 6.11 | Create HFT map overlay (render-only) | hft_overlay.dart | MapScreen |
| 6.12 | Add SDR bridge (optional) | SdrBridge.kt | USB-OTG + RTL-SDR |
| 6.13 | Train TFLite RF classifier | rf_classifier.tflite | generate_tflite_models.py |

### Phase 7: Testing & Polish (Day 7)

| Step | Task | Details |
|------|------|---------|
| 7.1 | Integration test: position report flow | End-to-end POST + GET |
| 7.2 | Integration test: geofence alert via WebSocket | POST position inside geofence → verify WebSocket push |
| 7.3 | Integration test: buddy proximity alert | POST two positions >500m apart → verify alert |
| 7.4 | Integration test: HFT sighting → threat escalation | POST 3 sightings → verify HostileThreat created |
| 7.5 | Battery drain test | 30s interval for 4 hours |
| 7.6 | Offline queue test | Airplane mode + reconnect → verify batch upload |

---

## 12. File Change Summary

### New Files (Backend)

| File | Purpose |
|------|---------|
| ackend/src/main/java/com/dangeremergence/model/PositionReport.java | Position report JPA entity |
| ackend/src/main/java/com/dangeremergence/model/Geofence.java | Geofence JPA entity |
| ackend/src/main/java/com/dangeremergence/model/BuddyAlert.java | Buddy alert JPA entity |
| ackend/src/main/java/com/dangeremergence/repository/PositionReportRepository.java | Position report JPA repository |
| ackend/src/main/java/com/dangeremergence/repository/GeofenceRepository.java | Geofence JPA repository |
| ackend/src/main/java/com/dangeremergence/repository/BuddyAlertRepository.java | Buddy alert JPA repository |
| ackend/src/main/java/com/dangeremergence/service/BFTService.java | BFT business logic service |
| ackend/src/main/java/com/dangeremergence/controller/BFTController.java | BFT REST controller |
| ackend/src/main/resources/db/migration/V3__blue_force_tracking.sql | Flyway migration for BFT tables |

### New Files (Frontend)

| File | Purpose |
|------|---------|
| rontend/lib/modules/bft/services/bft_service.dart | Core BFT service |
| rontend/lib/modules/bft/services/bft_overlay.dart | Map overlay renderer |
| rontend/lib/modules/bft/models/bft_models.dart | Dart data models |
| rontend/lib/modules/bft/screens/bft_status_screen.dart | BFT status screen |

### Modified Files

| File | Changes |
|------|---------|
| rontend/lib/core/constants.dart | Add BFT constants |
| rontend/lib/modules/maps/screens/map_screen.dart | Add BFT overlay layer |
| rontend/lib/main.dart | Register BFTService provider |
| rontend/android/.../LocationService.kt | Add BFT tracking actions |
| ackend/.../model/User.java | Add military fields |
| ackend/.../config/SecurityConfig.java | Add BFT route matchers |
| ackend/.../controller/AuthController.java | Include military fields in responses |
| rontend/.../services/sync_manager.dart | Add BFT queue flush trigger |
| rontend/.../services/mesh_manager.dart | Add bft_position message type |

---

## 13. Hostile Force Tracking (HFT)

> **Purpose:** Detect, classify, and track hostile forces (kidnappers, terrorists) who use walkie-talkies, radios, and RF equipment. Provide proximity alerts when threats are nearby.
> **Key Insight:** The Android phone's Bluetooth and Wi-Fi radios can detect RF signatures from common insurgent equipment (Baofeng UV-5R walkie-talkies, Motorola DP-series radios, Bluetooth headsets, drone controllers).

### 13.1 Threat Model

| Threat Type | Equipment | RF Signature | Detection Method |
|-------------|-----------|-------------|------------------|
| Walkie-talkie user | Baofeng UV-5R, Kenwood TK-series | VHF 136-174MHz, UHF 400-470MHz | External SDR dongle + TFLite classification |
| Bluetooth radio user | Bluetooth headset, handheld radio with BT | Bluetooth Classic 2.4GHz | Android BluetoothDiscovery API |
| Cellular hotspot | Mobile phone hotspot | Wi-Fi 2.4/5GHz beacon frames | Android WifiManager scan |
| Vehicle-mounted comms | Vehicle repeater, mobile radio | High-power RF, periodic transmission | RSSI triangulation via mesh peers |
| Drone operator | DJI controller, FRC transmitter | 2.4GHz/5.8GHz control signal | Wi-Fi beacon fingerprinting |

### 13.2 Detection Architecture

`mermaid
graph TB
    subgraph "Android Phone - RF Detection Layer"
        BT_SCAN[BluetoothScanner]
        WIFI_SCAN[WiFiScanner]
        SDR_BRIDGE[SDR USB-OTG Bridge]
        TFLITE[TFLite RF Classifier]
        HFT_SVC[HFTService Dart]
    end

    subgraph "Signal Processing"
        FFT[FFT 1024-point]
        FEATURES[Feature Extraction]
        CNN[CNN Model Inference]
    end

    subgraph "Backend"
        HFT_CTRL[HFTController]
        HFT_SVC_JAVA[HFTService Java]
        RF_REPO[RFSightingRepository]
        THREAT_REPO[HostileThreatRepository]
        SIG_REPO[ThreatSignatureRepository]
    end

    subgraph "Alert System"
        PROX_ALERT[ProximityAlert]
        MAP_OVERLAY[HFT Map Overlay]
        NOTIFY[Push Notification]
    end

    BT_SCAN -->|BluetoothDevice found| HFT_SVC
    WIFI_SCAN -->|ScanResult| HFT_SVC
    SDR_BRIDGE -->|IQ samples 2.4MHz| FFT
    FFT --> FEATURES
    FEATURES --> CNN
    CNN --> TFLITE
    TFLITE -->|Classification result| HFT_SVC
    HFT_SVC -->|POST /hft/sighting| HFT_CTRL
    HFT_CTRL --> HFT_SVC_JAVA
    HFT_SVC_JAVA --> RF_REPO
    HFT_SVC_JAVA --> THREAT_REPO
    HFT_SVC_JAVA --> SIG_REPO
    HFT_SVC_JAVA -->|Check proximity| PROX_ALERT
    PROX_ALERT --> MAP_OVERLAY
    PROX_ALERT --> NOTIFY
`

### 13.3 Bluetooth Device Scanning

The existing [MeshForegroundService.kt](frontend/android/app/src/main/kotlin/com/dangeremergence/mesh/MeshForegroundService.kt) already runs a Bluetooth RFCOMM server. For HFT, we extend it to also scan for **unknown** Bluetooth devices (potential hostile equipment).

#### 13.3.1 BluetoothReceiver BroadcastReceiver

`kotlin
// Add to MeshForegroundService.kt
private val bluetoothReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            BluetoothDevice.ACTION_FOUND -> {
                val device: BluetoothDevice? =
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, 0)
                device?.let { onHostileDeviceDetected(it, rssi) }
            }
        }
    }
}

private fun startHftBluetoothScan() {
    val filter = IntentFilter(BluetoothDevice.ACTION_FOUND)
    registerReceiver(bluetoothReceiver, filter)
    bluetoothAdapter?.startDiscovery()
}

private fun onHostileDeviceDetected(device: BluetoothDevice, rssi: Short) {
    // Check if device is in known-friendly list
    if (knownFriendlyDevices.contains(device.address)) return

    // Classify device type based on name pattern and class
    val deviceType = classifyBluetoothDevice(device)
    if (deviceType == HostileDeviceType.UNKNOWN) return

    // Send sighting to HFT service
    val sighting = mapOf(
        "type" to "bluetooth",
        "deviceAddress" to device.address,
        "deviceName" to (device.name ?: "Unknown"),
        "deviceClass" to device.bluetoothClass?.deviceClass,
        "rssi" to rssi,
        "latitude" to currentLatitude,
        "longitude" to currentLongitude,
        "timestamp" to System.currentTimeMillis()
    )
    sendHftSighting(sighting)
}

private fun classifyBluetoothDevice(device: BluetoothDevice): HostileDeviceType {
    val name = device.name?.lowercase() ?: return HostileDeviceType.UNKNOWN
    val btClass = device.bluetoothClass?.deviceClass ?: -1

    return when {
        // Baofeng UV-5R with Bluetooth PTT adapter
        name.contains("baofeng") || name.contains("uv-5r") ->
            HostileDeviceType.WALKIE_TALKIE
        // Motorola radio with Bluetooth
        name.contains("motorola") && btClass == 0x100 ->
            HostileDeviceType.TACTICAL_RADIO
        // Unknown audio device (potential surveillance)
        btClass == 0x404 && !knownFriendlyAudioDevices.contains(name) ->
            HostileDeviceType.SUSPICIOUS_AUDIO
        // Unknown phone in hotspot mode
        name.contains("android") || name.contains("iphone") ->
            HostileDeviceType.MOBILE_HOTSPOT
        else -> HostileDeviceType.UNKNOWN
    }
}

enum class HostileDeviceType {
    WALKIE_TALKIE, TACTICAL_RADIO, SUSPICIOUS_AUDIO,
    MOBILE_HOTSPOT, DRONE_CONTROLLER, UNKNOWN
}
`

#### 13.3.2 Existing Infrastructure Used

The [AndroidManifest.xml](frontend/android/app/src/main/AndroidManifest.xml) already has:
`xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
`

No new permissions needed for Bluetooth scanning.

### 13.4 Wi-Fi Device Scanning

> **Architecture:** The frontend Wi-Fi scanner collects **raw scan data** (SSID, BSSID, frequency, signal strength) and sends it to the backend via `POST /hft/sighting`. The **backend HFTService Java** performs classification using the `threat_signatures` database table. The frontend never classifies threats locally — it is a pure data collector and display client.

The [pubspec.yaml](frontend/pubspec.yaml) already includes wifi_iot package. For HFT, we scan for Wi-Fi access points and send raw data to the backend.

#### 13.4.1 HFT Wi-Fi Scanner (Thin Client)

```dart
// frontend/lib/modules/hft/services/hft_wifi_scanner.dart
import 'package:wifi_iot/wifi_iot.dart';

class HftWifiScanner {
  /// Scan for Wi-Fi access points and send raw data to backend.
  /// Backend classifies threats using threat_signatures table.
  Future<List<Map<String, dynamic>>> scanAndReport() async {
    final results = await WiFiForIoTPlugin.getWifiList();
    final sightings = <Map<String, dynamic>>[];

    for (final ap in results) {
      sightings.add({
        'detectionMethod': 'wifi',
        'deviceAddress': ap.bssid,
        'deviceName': ap.ssid,
        'signalStrength': ap.level,
        'frequency': ap.frequency,
        'latitude': _currentLatitude,  // from LocationService
        'longitude': _currentLongitude,
        'reportedAt': DateTime.now().toIso8601String(),
      });
    }
    return sightings;
  }
}
```

### 13.5 External SDR Integration (Optional Hardware)

For users with an RTL-SDR dongle connected via USB-OTG, the app can detect raw RF signals from walkie-talkies.

#### 13.5.1 SDR Bridge Architecture

`kotlin
// frontend/android/app/src/main/kotlin/com/dangeremergence/hft/SdrBridge.kt
class SdrBridge(private val context: Context) {

    companion object {
        private const val SAMPLE_RATE = 2_400_000  // 2.4 MHz
        private const val CENTER_FREQ = 400_000_000 // 400 MHz (UHF walkie-talkie band)
        private const val FFT_SIZE = 1024
    }

    // Frequency bands of interest
    val threatBands = listOf(
        ThreatBand("VHF Low", 136_000_000, 174_000_000, ThreatType.WALKIE_TALKIE),
        ThreatBand("UHF", 400_000_000, 470_000_000, ThreatType.WALKIE_TALKIE),
        ThreatBand("ISM 2.4GHz", 2_400_000_000, 2_485_000_000, ThreatType.DRONE),
        ThreatBand("ISM 5.8GHz", 5_725_000_000, 5_875_000_000, ThreatType.DRONE),
    )

    data class ThreatBand(
        val name: String,
        val freqStart: Long,
        val freqEnd: Long,
        val type: ThreatType
    )

    enum class ThreatType { WALKIE_TALKIE, DRONE, TACTICAL_RADIO, UNKNOWN }

    /**
     * Process IQ samples through TFLite model.
     * Returns classification confidence for each threat type.
     */
    fun classifySignal(iqSamples: FloatArray): Map<ThreatType, Float> {
        // 1. Apply FFT to convert time-domain to frequency-domain
        val fftOutput = computeFFT(iqSamples, FFT_SIZE)

        // 2. Extract features: spectral peaks, bandwidth, pulse intervals
        val features = extractFeatures(fftOutput)

        // 3. Run TFLite inference
        return runTfliteInference(features)
    }

    private fun computeFFT(samples: FloatArray, size: Int): FloatArray {
        // Real FFT implementation using Android's FFT class
        // Returns magnitude spectrum
        return FloatArray(size) { i -> samples[i] }
    }

    private fun extractFeatures(spectrum: FloatArray): FloatArray {
        // Extract: peak frequency, bandwidth, roll-off, spectral centroid
        return FloatArray(64) { 0f }
    }

    private fun runTfliteInference(features: FloatArray): Map<ThreatType, Float> {
        // Use existing SecurityProvider.kt TFLite bridge
        // Model: rf_classifier.tflite (CNN, 64 input features, 5 output classes)
        return mapOf(
            ThreatType.WALKIE_TALKIE to 0.85f,
            ThreatType.DRONE to 0.12f,
            ThreatType.TACTICAL_RADIO to 0.03f,
            ThreatType.UNKNOWN to 0.0f
        )
    }
}
`

#### 13.5.2 TFLite RF Classification Model

The existing [SecurityProvider.kt](frontend/android/app/src/main/kotlin/com/dangeremergence/security/SecurityProvider.kt) already has TFLite inference methods (handleTfliteLoadModel, handleTfliteRunInference). For HFT, we add:

| Model | Input | Output | Purpose |
|-------|-------|--------|---------|
| 
f_classifier.tflite | 1024-point FFT magnitude spectrum | 5 classes (background, Baofeng UV-5R, Motorola DP, Bluetooth headset, drone controller) | Classify RF signals from SDR |
| luetooth_classifier.tflite | Device name + class + RSSI history | 3 classes (friendly, unknown, hostile) | Classify Bluetooth devices |

The TFLite models can be generated using the existing [generate_tflite_models.py](frontend/scripts/generate_tflite_models.py) script.

### 13.6 Mesh Network Triangulation (Backend Java)

> **Architecture:** Triangulation runs in the **backend HFTService Java**, not on the frontend. The frontend sends raw sightings (Bluetooth device address + RSSI + GPS location) to the backend via `POST /hft/sighting`. The backend aggregates sightings from multiple peers and computes the estimated threat position.

When multiple mesh peers detect the same hostile RF signal (same Bluetooth MAC address or same Wi-Fi BSSID), the backend triangulates the threat's position.

#### 13.6.1 RSSI-to-Distance Estimation (Backend Java)

```java
// In HFTService.java
private double rssiToDistance(int rssi, int txPower) {
    // Log-distance path loss model
    // n = 2.5 (typical for outdoor environments)
    return Math.pow(10.0, (txPower - rssi) / (10.0 * 2.5));
}
```

#### 13.6.2 Trilateration Algorithm (Backend Java)

```java
// In HFTService.java
public class ThreatTriangulation {

    /**
     * Triangulate threat position from 3+ peer sightings.
     * Each sighting has: reporterLat, reporterLng, estimatedDistance.
     * Uses least-squares multilateration.
     */
    public LatLng triangulate(List<Sighting> sightings) {
        if (sightings.size() < 3) return null;

        // Weighted centroid based on RSSI confidence
        double sumX = 0, sumY = 0, totalWeight = 0;
        for (Sighting s : sightings) {
            double weight = 1.0 / Math.max(s.getEstimatedDistance(), 1.0);
            sumX += s.getReporterLng() * weight;
            sumY += s.getReporterLat() * weight;
            totalWeight += weight;
        }
        return new LatLng(sumY / totalWeight, sumX / totalWeight);
    }

    @Data
    public static class Sighting {
        private String reporterId;
        private double reporterLat;
        private double reporterLng;
        private double estimatedDistance;
        private int rssi;
        private String deviceAddress;
    }

    @Data
    public static class LatLng {
        private final double latitude;
        private final double longitude;
    }
}
```

### 13.7 Proximity Alert System (Backend Java)

> **Architecture:** All proximity alert evaluation runs in the **backend HFTService Java**. When a sighting is reported, the backend checks the distance from the reporting user's position to the estimated threat position. If the threat is within alert range, the backend pushes the alert to the user via WebSocket `/user/queue/hft/alerts`. The frontend simply displays the alert — it never evaluates proximity locally.

#### 13.7.1 Alert Tiers

| Tier | Distance | Color | Icon | Backend Action |
|------|----------|-------|------|----------------|
| Green | > 500m | Green | Shield | Log sighting, no alert pushed |
| Yellow | 200-500m | Yellow | Warning triangle | Push notification via WebSocket |
| Orange | 50-200m | Orange | Alert bell | Push notification + vibration pattern |
| Red | < 50m | Red | Skull | Push urgent alert + full-screen warning |

#### 13.7.2 Alert Trigger Logic (Backend Java)

```java
// In HFTService.java
@Service
public class HFTService {

    private static final double GREEN_THRESHOLD = 500.0;   // meters
    private static final double YELLOW_THRESHOLD = 200.0;
    private static final double ORANGE_THRESHOLD = 50.0;

    private final SimpMessagingTemplate messagingTemplate;

    /**
     * Evaluate proximity and push alert if needed.
     * Called after every sighting report.
     */
    public void evaluateProximity(RFSighting sighting, HostileThreat threat) {
        double distance = haversine(
            sighting.getLatitude(), sighting.getLongitude(),
            threat.getEstimatedLatitude(), threat.getEstimatedLongitude()
        );

        HftAlertTier tier = getAlertTier(distance);
        if (tier == HftAlertTier.GREEN) return; // No alert needed

        // Build alert payload
        Map<String, Object> alert = new HashMap<>();
        alert.put("type", "HFT_PROXIMITY");
        alert.put("tier", tier.name());
        alert.put("threatType", threat.getThreatType());
        alert.put("distanceMeters", distance);
        alert.put("estimatedLatitude", threat.getEstimatedLatitude());
        alert.put("estimatedLongitude", threat.getEstimatedLongitude());
        alert.put("confidenceScore", threat.getConfidenceScore());
        alert.put("timestamp", LocalDateTime.now());

        // Push alert to reporting user via WebSocket
        messagingTemplate.convertAndSendToUser(
            sighting.getReportedBy(),
            "/queue/hft/alerts",
            alert
        );

        // If RED tier, also alert unit commander
        if (tier == HftAlertTier.RED) {
            notifyUnitCommander(sighting.getReportedBy(), alert);
        }
    }

    private HftAlertTier getAlertTier(double distanceMeters) {
        if (distanceMeters > GREEN_THRESHOLD) return HftAlertTier.GREEN;
        if (distanceMeters > YELLOW_THRESHOLD) return HftAlertTier.YELLOW;
        if (distanceMeters > ORANGE_THRESHOLD) return HftAlertTier.ORANGE;
        return HftAlertTier.RED;
    }

    private void notifyUnitCommander(String userId, Map<String, Object> alert) {
        // Look up user's unit, find commander, push alert
    }

    private double haversine(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    }
}

enum HftAlertTier { GREEN, YELLOW, ORANGE, RED }
```

### 13.8 Backend HFT Service

#### 13.8.1 New Entities

**RFSighting Entity:** [ackend/src/main/java/com/dangeremergence/model/RFSighting.java](backend/src/main/java/com/dangeremergence/model/RFSighting.java)

`java
@Entity
@Table(name = "rf_sightings", indexes = {
    @Index(name = "idx_rf_sightings_reported_at", columnList = "reported_at DESC"),
    @Index(name = "idx_rf_sightings_threat_type", columnList = "threat_type"),
    @Index(name = "idx_rf_sightings_location", columnList = "latitude, longitude")
})
public class RFSighting {
    @Id @Column(length = 36) private String id;
    @Column(name = "reported_by", nullable = false, length = 36) private String reportedBy;
    @Column(name = "threat_type", nullable = false, length = 30) private String threatType;
    @Column(name = "detection_method", nullable = false, length = 20) private String detectionMethod;
    @Column(nullable = false) private Double latitude;
    @Column(nullable = false) private Double longitude;
    private Float accuracy;
    @Column(name = "signal_strength") private Integer signalStrength;
    @Column(name = "device_address", length = 30) private String deviceAddress;
    @Column(name = "device_name", length = 100) private String deviceName;
    @Column(name = "classification_confidence") private Float classificationConfidence;
    @Column(name = "reported_at", nullable = false) private LocalDateTime reportedAt;
    @Column(name = "expires_at") private LocalDateTime expiresAt;
}
`

**HostileThreat Entity:** [ackend/src/main/java/com/dangeremergence/model/HostileThreat.java](backend/src/main/java/com/dangeremergence/model/HostileThreat.java)

`java
@Entity
@Table(name = "hostile_threats")
public class HostileThreat {
    @Id @Column(length = 36) private String id;
    @Column(name = "threat_type", nullable = false, length = 30) private String threatType;
    @Column(name = "estimated_latitude") private Double estimatedLatitude;
    @Column(name = "estimated_longitude") private Double estimatedLongitude;
    @Column(name = "estimated_radius") private Double estimatedRadius;
    @Column(name = "confidence_score") private Float confidenceScore;
    @Column(name = "sighting_count") private Integer sightingCount;
    @Column(name = "last_sighted_at") private LocalDateTime lastSightedAt;
    @Column(name = "is_active") private Boolean isActive = true;
    @Column(name = "created_at") private LocalDateTime createdAt;
}
`

**ThreatSignature Entity:** [ackend/src/main/java/com/dangeremergence/model/ThreatSignature.java](backend/src/main/java/com/dangeremergence/model/ThreatSignature.java)

`java
@Entity
@Table(name = "threat_signatures")
public class ThreatSignature {
    @Id @Column(length = 36) private String id;
    @Column(name = "signature_name", nullable = false, unique = true) private String signatureName;
    @Column(name = "threat_type", nullable = false, length = 30) private String threatType;
    @Column(name = "detection_method", nullable = false, length = 20) private String detectionMethod;
    @Column(name = "signature_data", columnDefinition = "TEXT") private String signatureData;
    @Column(name = "is_active") private Boolean isActive = true;
    @Column(name = "created_at") private LocalDateTime createdAt;
}
`

#### 13.8.2 SQL Migration: V4__hostile_force_tracking.sql

**File:** [ackend/src/main/resources/db/migration/V4__hostile_force_tracking.sql](backend/src/main/resources/db/migration/V4__hostile_force_tracking.sql)

`sql
-- Flyway Migration V4: Hostile Force Tracking
-- Adds rf_sightings, hostile_threats, and threat_signatures tables

CREATE TABLE IF NOT EXISTS rf_sightings (
    id VARCHAR(36) PRIMARY KEY,
    reported_by VARCHAR(36) NOT NULL REFERENCES users(id),
    threat_type VARCHAR(30) NOT NULL,
    detection_method VARCHAR(20) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy REAL,
    signal_strength INTEGER,
    device_address VARCHAR(30),
    device_name VARCHAR(100),
    classification_confidence REAL,
    reported_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rf_sightings_reported_at ON rf_sightings(reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_rf_sightings_threat_type ON rf_sightings(threat_type);
CREATE INDEX IF NOT EXISTS idx_rf_sightings_location ON rf_sightings(latitude, longitude);

CREATE TABLE IF NOT EXISTS hostile_threats (
    id VARCHAR(36) PRIMARY KEY,
    threat_type VARCHAR(30) NOT NULL,
    estimated_latitude DOUBLE PRECISION,
    estimated_longitude DOUBLE PRECISION,
    estimated_radius DOUBLE PRECISION,
    confidence_score REAL,
    sighting_count INTEGER DEFAULT 1,
    last_sighted_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hostile_threats_active ON hostile_threats(is_active);
CREATE INDEX IF NOT EXISTS idx_hostile_threats_type ON hostile_threats(threat_type);

CREATE TABLE IF NOT EXISTS threat_signatures (
    id VARCHAR(36) PRIMARY KEY,
    signature_name VARCHAR(255) NOT NULL UNIQUE,
    threat_type VARCHAR(30) NOT NULL,
    detection_method VARCHAR(20) NOT NULL,
    signature_data TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
`

#### 13.8.3 HFTController

**File:** [ackend/src/main/java/com/dangeremergence/controller/HFTController.java](backend/src/main/java/com/dangeremergence/controller/HFTController.java)

`java
@RestController
@RequestMapping("/api/v1/hft")
@RequiredArgsConstructor
public class HFTController {

    private final HFTService hftService;

    @PostMapping("/sighting")
    public ResponseEntity<?> reportSighting(
            @RequestBody RFSighting sighting,
            @AuthenticationPrincipal String userId) {
        sighting.setReportedBy(userId);
        RFSighting saved = hftService.reportSighting(sighting);
        return ResponseEntity.ok(Map.of("status", "ok", "sightingId", saved.getId()));
    }

    @GetMapping("/threats/nearby")
    public ResponseEntity<?> getNearbyThreats(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "2000") double radiusMeters) {
        return ResponseEntity.ok(hftService.getNearbyThreats(lat, lng, radiusMeters));
    }

    @GetMapping("/threats/active")
    public ResponseEntity<?> getActiveThreats() {
        return ResponseEntity.ok(hftService.getActiveThreats());
    }

    @PostMapping("/signatures")
    public ResponseEntity<?> addSignature(@RequestBody ThreatSignature signature) {
        return ResponseEntity.ok(hftService.addSignature(signature));
    }

    @GetMapping("/signatures")
    public ResponseEntity<?> getSignatures() {
        return ResponseEntity.ok(hftService.getActiveSignatures());
    }
}
`

### 13.9 HFT Map Overlay (Render-Only)

> **Architecture:** The HFT map overlay is a **pure render component**. It receives threat data from the backend via `GET /hft/threats/nearby` and WebSocket pushes. It never evaluates threat proximity or classification locally — it only displays what the backend provides.

The HFT overlay renders on the same [MapScreen](frontend/lib/modules/maps/screens/map_screen.dart) as the BFT overlay, but with distinct icons:

| Threat Type | Icon | Color | Behavior |
|-------------|------|-------|----------|
| Walkie-talkie | Radio tower | Orange | Pulsing if actively transmitting (backend sets `isActive` flag) |
| Tactical radio | Antenna | Red | Static position estimate from backend |
| Drone controller | Drone | Purple | Moving if signal moves (backend updates position) |
| Unknown hotspot | Question mark | Yellow | Low confidence (backend sets `confidenceScore < 0.5`) |
| Triangulated threat | Skull | Red | Highest priority, shows radius circle from backend |

### 13.10 HFT Implementation Order
### 13.10 HFT Implementation Order

> **Architecture Priority:** Backend-first. All threat classification, triangulation, and proximity alert logic runs in the backend. The frontend only collects raw data and renders results.

| Step | Task | Files | Dependencies |
|------|------|-------|-------------|
| 1 | Create V4 migration SQL | V4__hostile_force_tracking.sql | None |
| 2 | Create RFSighting entity | RFSighting.java | V4 migration |
| 3 | Create HostileThreat entity | HostileThreat.java | V4 migration |
| 4 | Create ThreatSignature entity | ThreatSignature.java | V4 migration |
| 5 | Create HFT repositories | RFSightingRepository.java, HostileThreatRepository.java, ThreatSignatureRepository.java | Entities |
| 6 | **Create HFTService Java (triangulation + proximity alert + WebSocket push)** | HFTService.java | Repositories |
| 7 | Create HFTController | HFTController.java | HFTService |
| 8 | Update SecurityConfig for HFT routes | SecurityConfig.java | HFTController |
| 9 | Add Bluetooth scanning to MeshForegroundService (sends raw sightings to backend) | MeshForegroundService.kt | Android BT permissions |
| 10 | Create HFT Wi-Fi scanner (sends raw scan data to backend) | hft_wifi_scanner.dart | wifi_iot package |
| 11 | Create HFT Dart service (send-only, receives alerts via WebSocket) | hft_service.dart | BackendApi |
| 12 | Create HFT map overlay (render-only) | hft_overlay.dart | MapScreen |
| 13 | Add SDR bridge (optional) | SdrBridge.kt | USB-OTG + RTL-SDR |
| 14 | Train TFLite RF classifier | rf_classifier.tflite | generate_tflite_models.py |
| 15 | Integrate HFT into main.dart | main.dart | All HFT services |
| 16 | Unit tests: HFTService Java | HFTServiceTest.java | HFTService |
| 17 | End-to-end testing: sighting → threat escalation → WebSocket alert | N/A | All components |

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| BFT | Blue Force Tracking - tracking friendly military units |
| HFT | Hostile Force Tracking - detecting and tracking enemy forces |
| Unit | A military unit (e.g., platoon, squad) with a unique ID |
| Buddy | Another user monitored for proximity separation alerts |
| Geofence | A virtual perimeter (circle) that triggers alerts when entered/exited |
| Stale | Position data older than 2 minutes but less than 10 minutes |
| Lost | Position data older than 10 minutes but less than 30 minutes |
| Mesh | Device-to-device communication without internet |
| Relay | Forwarding data through a peer device that has internet access |
| SDR | Software-Defined Radio - RF receiver using USB dongle |
| TFLite | TensorFlow Lite - on-device ML inference |
| RSSI | Received Signal Strength Indicator - signal power measurement |
| FFT | Fast Fourier Transform - converts time-domain signal to frequency-domain |

## Appendix B: Configuration Reference

### Backend application.yml additions

`yaml
bft:
  stale-threshold-seconds: 120
  lost-threshold-seconds: 600
  removal-threshold-seconds: 1800
  position-retention-days: 30
  batch-max-size: 50
  nearby-default-radius-meters: 1000

hft:
  sighting-retention-hours: 72
  threat-escalation-count: 3
  proximity-alert-green: 500
  proximity-alert-yellow: 200
  proximity-alert-orange: 50
  bluetooth-scan-interval-seconds: 60
  wifi-scan-interval-seconds: 120
`

### Frontend constants additions

`dart
// HFT Constants
static const int hftBluetoothScanInterval = 60;    // seconds
static const int hftWifiScanInterval = 120;         // seconds
static const double hftProximityGreen = 500.0;      // meters
static const double hftProximityYellow = 200.0;
static const double hftProximityOrange = 50.0;
static const int hftSightingRetentionHours = 72;
static const int hftThreatEscalationCount = 3;
`

