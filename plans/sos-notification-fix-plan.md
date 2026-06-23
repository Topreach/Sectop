# SOS Alert Notification Delivery Fix Plan

## Root Cause Analysis

### Primary Root Cause: Phone Cannot Reach Server Domain

The frontend is configured to connect to `https://sectop.resultscaleai.com` (domain name), but the phone cannot resolve this domain. The server is at IP `173.249.34.3` with ports 80, 443, and 8080 already open in the firewall.

**Evidence:**
- Diagnostic logs added to `SOSAlertService.processNewAlert()` did NOT appear in server logs after sending SOS
- This confirms the SOS request never reached the backend
- User confirmed: "the phone cannot reach sectop.resultscaleai.com"

### Secondary Issues (to fix after connectivity is restored)

1. **WebSocket topic mismatch** — Frontend subscribes to `/topic/alerts`, backend pushes to `/topic/alerts/new`
2. **FCM_SERVER_KEY not configured** — Push notifications silently skipped
3. **findUsersInArea() ignores bounding box** — Returns all users instead of geographically nearby ones
4. **Fire-and-forget STOMP send** — `_sendAlertViaStomp()` is called without `await`, so "Message sent" shows immediately even if backend never receives it

---

## Architecture Overview

```mermaid
flowchart TD
    Phone[Phone App] -->|wss://173.249.34.3/ws| HostNginx[Host Nginx :443]
    Phone -->|https://173.249.34.3/api| HostNginx
    HostNginx -->|/ws/ -> localhost:8088/ws/| DockerNginx[Docker Nginx :8081]
    HostNginx -->|/api/ -> localhost:8088/api/| DockerNginx
    DockerNginx -->|/ws/ -> backend:8080| Backend[Backend :8080]
    DockerNginx -->|/api/ -> backend:8080| Backend
    Backend -->|STOMP /topic/alerts/new| Phone
    
    subgraph "SOS Flow"
        SOS[SOS Button] -->|STOMP SEND /app/alerts/send| StompCtrl[StompAlertController]
        StompCtrl -->|createAlert| AlertService[SOSAlertService]
        AlertService -->|processNewAlert| Channels{Delivery Channels}
        Channels -->|MQTT| MQTT[Mosquitto :1883]
        Channels -->|WebSocket| WS[/topic/alerts/new]
        Channels -->|Redis Pub/Sub| Redis[Redis :6379]
        Channels -->|FCM Push| FCM[Firebase Cloud Messaging]
        Channels -->|SMS| SMS[Twilio SMS]
    end
```

---

## Fix 1: Update Frontend Constants to Use Server IP

### File: [`frontend/lib/core/constants.dart`](frontend/lib/core/constants.dart)

**Current values (lines 54-69):**
```dart
static const String apiBaseUrl = 'https://sectop.resultscaleai.com/api';
static const String wsBaseUrl = 'wss://sectop.resultscaleai.com/ws';
static const String sosApiBaseUrl = 'https://sectop.resultscaleai.com/api';
static const String sosWsBaseUrl = 'wss://sectop.resultscaleai.com/ws-sos';
static const String msgApiBaseUrl = 'https://sectop.resultscaleai.com/api';
static const String msgWsBaseUrl = 'wss://sectop.resultscaleai.com/ws';
static const String communityApiBaseUrl = 'https://sectop.resultscaleai.com/api';
```

**New values:**
```dart
static const String apiBaseUrl = 'http://173.249.34.3:8080/api';
static const String wsBaseUrl = 'ws://173.249.34.3:8080/ws';
static const String sosApiBaseUrl = 'http://173.249.34.3:8080/api';
static const String sosWsBaseUrl = 'ws://173.249.34.3:8080/ws';
static const String msgApiBaseUrl = 'http://173.249.34.3:8080/api';
static const String msgWsBaseUrl = 'ws://173.249.34.3:8080/ws';
static const String communityApiBaseUrl = 'http://173.249.34.3:8080/api';
```

**Changes:**
- `https://` → `http://` (no SSL needed for local/IP-based access)
- `sectop.resultscaleai.com` → `173.249.34.3:8080` (direct IP + backend port)
- `wss://` → `ws://` (no SSL WebSocket)
- All URLs point to the backend directly on port 8080 (bypassing nginx layers)

---

## Fix 2: Fix WebSocket Topic Mismatch

### File: [`frontend/lib/modules/sos/services/sos_service.dart`](frontend/lib/modules/sos/services/sos_service.dart)

**Current (lines 149-152):**
```dart
_sendStompFrame('SUBSCRIBE', {
  'id': 'sub-1',
  'destination': '/topic/alerts',
});
```

**New:**
```dart
_sendStompFrame('SUBSCRIBE', {
  'id': 'sub-1',
  'destination': '/topic/alerts/new',
});
```

Also add a subscription to `/user/queue/alerts` for personal alerts:
```dart
_sendStompFrame('SUBSCRIBE', {
  'id': 'sub-2',
  'destination': '/user/queue/alerts',
});
```

---

## Fix 3: Configure FCM_SERVER_KEY on Server

### File: [`deploy/scripts/deploy-server.sh`](deploy/scripts/deploy-server.sh)

Add `FCM_SERVER_KEY` to the backend environment variables (around line 129-137):

```yaml
environment:
  ...
  FCM_SERVER_KEY: ${FCM_SERVER_KEY}
```

Then on the server, set the environment variable:
```bash
export FCM_SERVER_KEY="your-firebase-server-key-here"
```

Or add it to the `.env` file in the project directory.

---

## Fix 4: Fix findUsersInArea() Query

### File: [`backend/src/main/java/com/dangeremergence/repository/UserRepository.java`](backend/src/main/java/com/dangeremergence/repository/UserRepository.java)

**Current (lines 52-58):**
```java
@Query("SELECT u FROM User u WHERE u.active = true AND u.fcmToken IS NOT NULL AND u.fcmToken <> ''")
List<User> findUsersInArea(
        @Param("minLat") double minLat, @Param("maxLat") double maxLat,
        @Param("minLng") double minLng, @Param("maxLng") double maxLng
);
```

**New:**
```java
@Query("SELECT u FROM User u WHERE u.active = true AND u.fcmToken IS NOT NULL AND u.fcmToken <> '' " +
       "AND u.latitude BETWEEN :minLat AND :maxLat AND u.longitude BETWEEN :minLng AND :maxLng")
List<User> findUsersInArea(
        @Param("minLat") double minLat, @Param("maxLat") double maxLat,
        @Param("minLng") double minLng, @Param("maxLng") double maxLng
);
```

**Note:** This requires the `User` entity to have `latitude` and `longitude` fields. If they don't exist yet, a database migration is needed.

---

## Fix 5: Ensure FCM Token Registration Works

### File: [`frontend/lib/modules/sos/services/sos_service.dart`](frontend/lib/modules/sos/services/sos_service.dart)

The `_sendAlertViaStomp()` method (line 307) is fire-and-forget — it doesn't `await` the result. Add error handling and a retry mechanism:

```dart
void _sendAlertViaStomp(SOSAlert alert) {
    if (_wsChannel == null) {
      debugPrint('SOSService: WebSocket not connected, falling back to HTTP POST');
      unawaited(_tryCloudSend(alert));
      return;
    }
    try {
      // ... send STOMP frame ...
      debugPrint('SOSService: Alert sent via STOMP SEND: ${alert.id}');
      // Add a confirmation check
      _waitForDeliveryConfirmation(alert.id);
    } catch (e) {
      debugPrint('SOSService: STOMP SEND failed, falling back to HTTP POST: $e');
      unawaited(_tryCloudSend(alert));
    }
}
```

---

## Implementation Order

1. **Fix 1** — Update frontend constants (most critical — without this, nothing works)
2. **Fix 2** — Fix WebSocket topic mismatch (needed for real-time delivery)
3. **Fix 3** — Configure FCM_SERVER_KEY (needed for push notifications)
4. **Fix 4** — Fix findUsersInArea() query (needed for geographic filtering)
5. **Rebuild debug APK** with all frontend changes
6. **Deploy updated backend** to server
7. **Test end-to-end** with both phones

---

## Testing Plan

1. Install the updated debug APK on both phones
2. Ensure both phones have internet access (mobile data or Wi-Fi)
3. Send SOS from Phone A
4. Verify in server logs: `=== processNewAlert START for alert ... ===`
5. Verify Phone B receives the alert via WebSocket (if on same network) or FCM push
6. Check `docker logs danger-emergence-backend --tail 50` for diagnostic messages
