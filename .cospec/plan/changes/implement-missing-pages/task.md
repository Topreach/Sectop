# Task: Implement Missing/Placeholder Pages and Connect to Backend APIs

## Objective
Replace all placeholder/stub screens in the Danger Emergence Flutter app with fully functional pages that connect to the existing backend API controllers. Also implement the 7 routes that currently show "Route not found".

## Backend API Endpoints Available

### AuthController (`/api/v1/auth`)
- `POST /login` → `{email, password}` → `{userId, name, email, phone, role, token}`
- `POST /register` → `{name, email, phone, password, role}` → `{userId, name, email, role, token}`

### SOSAlertController (`/api/v1/alerts`)
- `POST /` → create alert
- `GET /active` → get active alerts
- `GET /user/{userId}` → get alerts for user
- `GET /nearby?latitude=&longitude=&radiusKm=` → get alerts in area
- `GET /sync?since=` → get alerts since timestamp
- `POST /{alertId}/acknowledge` → acknowledge alert
- `POST /{alertId}/resolve` → resolve alert
- `GET /count` → `{active_count}`

### MessageController (`/api/v1/messages`)
- `POST /` → send message `{sender_id, receiver_id, content, message_type, priority, latitude, longitude}`
- `GET /user/{userId}` → get messages for user
- `GET /sync?userId=&since=` → get messages since timestamp
- `PUT /{messageId}/deliver` → mark as delivered
- `PUT /{messageId}/read` → mark as read
- `PUT /{messageId}/sync` → mark as synced
- `GET /pending-sync` → get pending sync messages
- `GET /unread/{userId}` → `{count}`

### ZoneController (`/api/v1/zones`)
- `POST /` → create zone
- `GET /{zoneId}` → get zone by ID
- `GET /active` → get active zones
- `GET /danger` → get danger zones
- `GET /restricted` → get restricted zones
- `GET /nearby?latitude=&longitude=&radiusDegrees=` → get zones nearby
- `GET /sync?since=` → get zones since timestamp
- `PUT /{zoneId}` → update zone

## Tasks

### Task 1: Implement MapScreen with flutter_map and zone overlay (HIGH PRIORITY) ✅
**Files to modify:**
- `frontend/lib/modules/maps/screens/map_screen.dart` (rewrite)
- `frontend/pubspec.yaml` (add `flutter_map` and `latlong2` dependencies)

**What to do:**
1. Add `flutter_map: ^7.0.2` and `latlong2: ^0.9.1` to pubspec.yaml
2. Rewrite MapScreen to show an actual OpenStreetMap tile map using flutter_map
3. Add markers for:
   - Current user location (blue dot)
   - Danger zones (red markers) fetched from `GET /api/v1/zones/danger`
   - Safe zones (green markers) fetched from `GET /api/v1/zones/active`
   - Active SOS alerts (pulsing red markers) fetched from `GET /api/v1/alerts/active`
4. Keep the zone overlay controls (Report Zone, Safe Zones, Danger Zones) but make them functional:
   - "Report Zone" → calls `POST /api/v1/zones` via BackendApi
   - "Safe Zones" → filters map to show only safe zones
   - "Danger Zones" → filters map to show only danger zones
5. Keep the bottom info card but update it to show selected zone/alert details on tap
6. Add `BackendApi` methods for zones if not already present

### Task 2: Implement InboxScreen with real messages and alerts from backend ✅
**Files to modify:**
- `frontend/lib/modules/sos/screens/inbox_screen.dart` (rewrite)

**What to do:**
1. **Messages tab**: Fetch and display messages from `GET /api/v1/messages/user/{userId}`
   - Show message list with sender, content preview, timestamp, read/unread status
   - Tap to mark as read via `PUT /api/v1/messages/{messageId}/read`
   - Pull-to-refresh
2. **Alerts tab**: Fetch and display alerts from `GET /api/v1/alerts/user/{userId}`
   - Show alert list with type, status, timestamp
   - Show active alerts prominently with red styling
3. **Updates tab**: Keep the SyncManager status but add:
   - Fetch pending sync items from `GET /api/v1/messages/pending-sync`
   - Show system update notifications

### Task 3: Implement Dashboard Map and Inbox tabs with real content ✅
**Files to modify:**
- `frontend/lib/modules/sos/screens/dashboard_screen.dart` (rewrite `_MapView` and `_InboxView`)

**What to do:**
1. Replace `_MapView` placeholder with a mini embedded map (same flutter_map setup, smaller)
   - Show current location + nearby zones
   - Tap to navigate to full MapScreen
2. Replace `_InboxView` placeholder with:
   - Unread message count badge
   - Recent messages preview (last 3 messages from `GET /api/v1/messages/user/{userId}`)
   - Active alerts count
   - Tap to navigate to full InboxScreen

### Task 4: Implement Profile options (Edit Profile, Medical Info, Emergency Contacts) ✅
**Files to modify:**
- `frontend/lib/modules/sos/screens/dashboard_screen.dart` (Profile section)

**What to do:**
1. **Edit Profile**: Create a dialog/screen that allows editing name, email, phone
   - Save locally via AuthService.updateProfile()
   - Optionally sync to backend
2. **Medical Info**: Create a dialog/screen with editable medical information fields
   - Store in OfflineStorageService
3. **Emergency Contacts**: Create a dialog/screen to add/edit emergency contacts
   - Store in OfflineStorageService
   - Show list of contacts with phone numbers

### Task 5: Implement missing routes (7 routes currently showing "Route not found") ✅
**Files to modify:**
- `frontend/lib/core/routes.dart` (add route cases)
- Create new screen files as needed

**What to do:**
Add proper route handlers for:
1. `/profile` → Navigate to Profile tab in Dashboard (or create standalone ProfileScreen)
2. `/help` → Create HelpScreen with FAQ, usage guide, emergency numbers
3. `/settings` → Create SettingsScreen with notification toggles, theme selection, data usage
4. `/emergency-contacts` → Navigate to Emergency Contacts dialog (from Task 4)
5. `/incident-report` → Create IncidentReportScreen with form (type, description, location, photo)
6. `/zone-details` → Create ZoneDetailsScreen showing zone info, severity, status
7. `/message-detail` → Create MessageDetailScreen showing full message content, reply option

## Dependencies to add to pubspec.yaml
```yaml
dependencies:
  flutter_map: ^7.0.2
  latlong2: ^0.9.1
```

## Acceptance Criteria
1. MapScreen shows real OpenStreetMap tiles with zone markers
2. InboxScreen shows real messages and alerts from backend API
3. Dashboard tabs show real data instead of placeholders
4. Profile options (Edit Profile, Medical Info, Emergency Contacts) are functional
5. All 7 missing routes show proper pages instead of "Route not found"
6. All pages gracefully handle offline mode (show cached data or "offline" message)
7. App still builds successfully with `flutter build apk --release`
