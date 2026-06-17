import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/shared/services/backend_api.dart';

void main() {
  late BackendApi api;
  late MockClient mockClient;
  List<http.BaseRequest> capturedRequests = [];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    capturedRequests = [];

    mockClient = MockClient((request) async {
      capturedRequests.add(request);
      return http.Response(json.encode({'status': 'ok'}), 200);
    });

    api = BackendApi();
    api.setClient(mockClient);
    api.resetCircuitBreaker();
  });

  group('BackendApi - Auth Endpoints', () {
    test('forgotPassword sends correct request', () async {
      final result = await api.forgotPassword('test@example.com');
      expect(result, isA<Map<String, dynamic>>());
      expect(capturedRequests.last.url.toString(), contains('/auth/forgot-password'));
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['email'], 'test@example.com');
    });

    test('resetPassword sends correct request', () async {
      final result = await api.resetPassword('reset_token_123', 'newPassword123');
      expect(result, isA<Map<String, dynamic>>());
      expect(capturedRequests.last.url.toString(), contains('/auth/reset-password'));
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['token'], 'reset_token_123');
      expect(body['newPassword'], 'newPassword123');
    });
  });

  group('BackendApi - AI Endpoints', () {
    test('analyzeMessage sends correct body', () async {
      await api.analyzeMessage('Help! Fire!', userId: 'user1');
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['text'], 'Help! Fire!');
      expect(body['userId'], 'user1');
    });

    test('prioritize sends correct body', () async {
      await api.prioritize('Emergency!');
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['text'], 'Emergency!');
    });

    test('prioritizeBatch sends correct body', () async {
      await api.prioritizeBatch(['Help', 'Fire', 'OK']);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['texts'], ['Help', 'Fire', 'OK']);
    });

    test('analyzeAudio sends correct body', () async {
      await api.analyzeAudio('base64encodedaudio');
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['audio'], 'base64encodedaudio');
    });
  });

  group('BackendApi - Predictive Endpoints', () {
    test('forecastDangerZones sends correct body', () async {
      await api.forecastDangerZones(
        ['zone_1', 'zone_2'],
        historyHours: 72,
        forecastHours: 6,
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['zoneIds'], ['zone_1', 'zone_2']);
      expect(body['historyHours'], 72);
      expect(body['forecastHours'], 6);
    });

    test('detectAnomaly sends correct body', () async {
      await api.detectAnomaly([1.0, 2.0, 3.0, 100.0, 4.0]);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['values'], [1.0, 2.0, 3.0, 100.0, 4.0]);
    });

    test('optimizeResources sends correct body', () async {
      await api.optimizeResources(
        [
          {'id': 'z1', 'priority': 3, 'latitude': 40.71, 'longitude': -74.00, 'requiredSkill': 'medical'}
        ],
        [
          {'id': 'r1', 'name': 'Responder A', 'latitude': 40.72, 'longitude': -74.01, 'skill': 'medical', 'availability': 100}
        ],
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['zones'], isA<List>());
      expect(body['responders'], isA<List>());
      expect(body['zones'].length, 1);
      expect(body['responders'].length, 1);
    });
  });

  group('BackendApi - Digital Twin Endpoints', () {
    test('getCityTileset builds correct URL', () async {
      await api.getCityTileset('new-york');
      expect(capturedRequests.last.url.toString(), contains('/digital-twin/cities/new-york/tileset'));
    });

    test('getCityBuildings builds correct URL', () async {
      await api.getCityBuildings('lagos');
      expect(capturedRequests.last.url.toString(), contains('/digital-twin/cities/lagos/buildings'));
    });

    test('predictPropagation sends correct body', () async {
      await api.predictPropagation({
        'cityId': 'new-york',
        'hazardType': 'fire',
        'originLat': 40.7128,
        'originLng': -74.0060,
        'windSpeed': 15,
        'windDirection': 45,
      });
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['cityId'], 'new-york');
      expect(body['hazardType'], 'fire');
    });

    test('getEvacuationPlan sends correct body', () async {
      await api.getEvacuationPlan(40.7128, -74.0060);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['latitude'], 40.7128);
      expect(body['longitude'], -74.0060);
    });
  });

  group('BackendApi - Drone Endpoints', () {
    test('getAvailableDrones builds correct URL', () async {
      await api.getAvailableDrones(latitude: 40.7128, longitude: -74.0060);
      expect(capturedRequests.last.url.toString(), contains('/drones/available'));
      expect(capturedRequests.last.url.toString(), contains('latitude=40.7128'));
      expect(capturedRequests.last.url.toString(), contains('longitude=-74.006'));
    });

    test('deployRelayDrone sends correct body', () async {
      await api.deployRelayDrone('drone_0', 40.7128, -74.0060);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['droneId'], 'drone_0');
      expect(body['latitude'], 40.7128);
      expect(body['longitude'], -74.0060);
    });

    test('assessDamage sends correct body', () async {
      await api.assessDamage('zone_test', 40.7128, -74.0060, 1.0);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['zoneId'], 'zone_test');
      expect(body['centerLat'], 40.7128);
      expect(body['centerLng'], -74.0060);
      expect(body['radiusKm'], 1.0);
    });

    test('deploySwarmMesh sends correct body', () async {
      await api.deploySwarmMesh('zone_test', 40.7128, -74.0060, 1.0);
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['zoneId'], 'zone_test');
      expect(body['centerLat'], 40.7128);
      expect(body['centerLng'], -74.0060);
      expect(body['radiusKm'], 1.0);
    });
  });

  group('BackendApi - Mesh Endpoints', () {
    test('findRoute sends correct body', () async {
      await api.findRoute(
        'device_a',
        'device_b',
        neighborMetrics: [
          {'deviceId': 'device_b', 'rssi': -65, 'battery': 80, 'linkQuality': 0.9}
        ],
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['sourceDeviceId'], 'device_a');
      expect(body['targetDeviceId'], 'device_b');
      expect(body['neighborMetrics'], isA<List>());
    });

    test('broadcastMeshMessage sends correct body', () async {
      await api.broadcastMeshMessage(
        'device_a',
        'sos',
        3,
        {'text': 'Help!'},
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['sourceDeviceId'], 'device_a');
      expect(body['messageType'], 'sos');
      expect(body['priority'], 3);
      expect(body['payload'], {'text': 'Help!'});
    });

    test('getMeshPeers builds correct URL', () async {
      await api.getMeshPeers();
      expect(capturedRequests.last.url.toString(), contains('/mesh/peers'));
    });

    test('reportMeshStats sends correct body', () async {
      await api.reportMeshStats({
        'deviceId': 'device_a',
        'battery': 75,
        'rssi': -60,
        'messagesRelayed': 42,
      });
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['deviceId'], 'device_a');
      expect(body['battery'], 75);
    });
  });

  group('BackendApi - Zone Endpoints', () {
    test('getActiveZones builds correct URL', () async {
      await api.getActiveZones();
      expect(capturedRequests.last.url.toString(), contains('/zones/active'));
    });

    test('getDangerZones builds correct URL', () async {
      await api.getDangerZones();
      expect(capturedRequests.last.url.toString(), contains('/zones/danger'));
    });

    test('getRestrictedZones builds correct URL', () async {
      await api.getRestrictedZones();
      expect(capturedRequests.last.url.toString(), contains('/zones/restricted'));
    });

    test('getZonesNearby builds correct URL', () async {
      await api.getZonesNearby(40.7128, -74.0060, radiusDegrees: 0.5);
      expect(capturedRequests.last.url.toString(), contains('/zones/nearby'));
      expect(capturedRequests.last.url.toString(), contains('latitude=40.7128'));
      expect(capturedRequests.last.url.toString(), contains('longitude=-74.006'));
      expect(capturedRequests.last.url.toString(), contains('radiusDegrees=0.5'));
    });

    test('createZone sends correct body', () async {
      await api.createZone({'name': 'Test Zone', 'type': 'danger', 'latitude': 40.71, 'longitude': -74.00});
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['name'], 'Test Zone');
      expect(body['type'], 'danger');
    });
  });

  group('BackendApi - Message Endpoints', () {
    test('getMessages builds correct URL', () async {
      await api.getMessages('user_123');
      expect(capturedRequests.last.url.toString(), contains('/messages/user/user_123'));
    });

    test('getUnreadCount builds correct URL', () async {
      await api.getUnreadCount('user_123');
      expect(capturedRequests.last.url.toString(), contains('/messages/unread/user_123'));
    });

    test('markMessageRead sends correct request', () async {
      await api.markMessageRead('msg_123');
      expect(capturedRequests.last.url.toString(), contains('/messages/msg_123/read'));
    });

    test('sendMessage sends correct body', () async {
      await api.sendMessage({'sender_id': 'user_1', 'content': 'Hello', 'priority': 1});
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['sender_id'], 'user_1');
      expect(body['content'], 'Hello');
    });
  });

  group('BackendApi - Alert Endpoints', () {
    test('getActiveAlerts builds correct URL', () async {
      await api.getActiveAlerts();
      expect(capturedRequests.last.url.toString(), contains('/alerts/active'));
    });

    test('getUserAlerts builds correct URL', () async {
      await api.getUserAlerts('user_123');
      expect(capturedRequests.last.url.toString(), contains('/alerts/user/user_123'));
    });

    test('getAlertCount builds correct URL', () async {
      await api.getAlertCount();
      expect(capturedRequests.last.url.toString(), contains('/alerts/count'));
    });
  });

  group('BackendApi - Incident Endpoints', () {
    test('reportIncident sends correct body', () async {
      await api.reportIncident(
        reporterId: 'user_1',
        incidentType: 'suspicious',
        description: 'Suspicious activity at market',
        latitude: 6.5244,
        longitude: 3.3792,
        severity: 'high',
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['incidentType'], 'suspicious');
      expect(body['description'], 'Suspicious activity at market');
      expect(body['latitude'], 6.5244);
      expect(body['longitude'], 3.3792);
      expect(body['severity'], 'high');
    });

    test('getNearbyIncidents builds correct URL', () async {
      await api.getNearbyIncidents(latitude: 6.5244, longitude: 3.3792, radiusKm: 10);
      expect(capturedRequests.last.url.toString(), contains('/incidents/nearby'));
      expect(capturedRequests.last.url.toString(), contains('latitude=6.5244'));
      expect(capturedRequests.last.url.toString(), contains('longitude=3.3792'));
      expect(capturedRequests.last.url.toString(), contains('radiusKm=10'));
    });

    test('getIncidentHeatmap builds correct URL', () async {
      await api.getIncidentHeatmap(latitude: 6.5244, longitude: 3.3792, radiusKm: 20);
      expect(capturedRequests.last.url.toString(), contains('/incidents/heatmap'));
      expect(capturedRequests.last.url.toString(), contains('latitude=6.5244'));
      expect(capturedRequests.last.url.toString(), contains('longitude=3.3792'));
      expect(capturedRequests.last.url.toString(), contains('radiusKm=20'));
    });

    test('upvoteIncident sends correct request', () async {
      await api.upvoteIncident('incident_123');
      expect(capturedRequests.last.url.toString(), contains('/incidents/incident_123/upvote'));
    });

    test('getIncidentStats builds correct URL', () async {
      await api.getIncidentStats();
      expect(capturedRequests.last.url.toString(), contains('/incidents/stats'));
    });
  });

  group('BackendApi - Broadcast Endpoints', () {
    test('getActiveBroadcasts builds correct URL', () async {
      await api.getActiveBroadcasts(state: 'Lagos', lga: 'Ikeja');
      expect(capturedRequests.last.url.toString(), contains('/broadcasts/active'));
      expect(capturedRequests.last.url.toString(), contains('state=Lagos'));
      expect(capturedRequests.last.url.toString(), contains('lga=Ikeja'));
    });

    test('getBroadcast builds correct URL', () async {
      await api.getBroadcast('broadcast_123');
      expect(capturedRequests.last.url.toString(), contains('/broadcasts/broadcast_123'));
    });

    test('createBroadcast sends correct body', () async {
      await api.createBroadcast({
        'title': 'Emergency Alert',
        'message': 'Flood warning in Lagos',
        'state': 'Lagos',
        'severity': 'high',
      });
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['title'], 'Emergency Alert');
      expect(body['message'], 'Flood warning in Lagos');
      expect(body['state'], 'Lagos');
    });

    test('expireBroadcast sends correct request', () async {
      await api.expireBroadcast('broadcast_123');
      expect(capturedRequests.last.url.toString(), contains('/broadcasts/broadcast_123/expire'));
    });

    test('getBroadcastCount builds correct URL', () async {
      await api.getBroadcastCount();
      expect(capturedRequests.last.url.toString(), contains('/broadcasts/count'));
    });
  });

  group('BackendApi - Route Endpoints', () {
    test('planSafeRoute sends correct body', () async {
      await api.planSafeRoute(
        fromLat: 6.5244,
        fromLng: 3.3792,
        toLat: 6.6018,
        toLng: 3.3515,
        avoidHighways: true,
        preferLitRoads: true,
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['fromLat'], 6.5244);
      expect(body['fromLng'], 3.3792);
      expect(body['toLat'], 6.6018);
      expect(body['toLng'], 3.3515);
      expect(body['avoidHighways'], true);
      expect(body['preferLitRoads'], true);
    });

    test('getDangerScore builds correct URL', () async {
      await api.getDangerScore(latitude: 6.5244, longitude: 3.3792, radiusKm: 5);
      expect(capturedRequests.last.url.toString(), contains('/routes/danger-score'));
      expect(capturedRequests.last.url.toString(), contains('latitude=6.5244'));
      expect(capturedRequests.last.url.toString(), contains('longitude=3.3792'));
      expect(capturedRequests.last.url.toString(), contains('radiusKm=5'));
    });
  });

  group('BackendApi - Tip-Off Endpoints', () {
    test('submitTip sends correct body', () async {
      await api.submitTip({
        'title': 'Suspicious package',
        'description': 'Unattended bag at bus stop',
        'latitude': 6.5244,
        'longitude': 3.3792,
        'isAnonymous': true,
      });
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['title'], 'Suspicious package');
      expect(body['isAnonymous'], true);
    });

    test('getPendingTips builds correct URL', () async {
      await api.getPendingTips();
      expect(capturedRequests.last.url.toString(), contains('/tips/pending'));
    });

    test('getTipById builds correct URL', () async {
      await api.getTipById('tip_123');
      expect(capturedRequests.last.url.toString(), contains('/tips/tip_123'));
    });

    test('reviewTip sends correct body', () async {
      await api.reviewTip('tip_123', {'status': 'verified', 'notes': 'Confirmed threat'});
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['status'], 'verified');
      expect(body['notes'], 'Confirmed threat');
    });

    test('getTipStats builds correct URL', () async {
      await api.getTipStats();
      expect(capturedRequests.last.url.toString(), contains('/tips/stats'));
    });
  });

  group('BackendApi - Radio Broadcast Endpoints', () {
    test('createRadioBroadcast sends correct body', () async {
      await api.createRadioBroadcast({
        'message': 'Emergency broadcast',
        'targetState': 'Lagos',
        'language': 'en',
        'priority': 1,
      });
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['message'], 'Emergency broadcast');
      expect(body['targetState'], 'Lagos');
    });

    test('getRadioBroadcasts builds correct URL', () async {
      await api.getRadioBroadcasts();
      expect(capturedRequests.last.url.toString(), contains('/radio/broadcasts'));
    });

    test('getRadioBroadcast builds correct URL', () async {
      await api.getRadioBroadcast('radio_123');
      expect(capturedRequests.last.url.toString(), contains('/radio/broadcasts/radio_123'));
    });

    test('retryRadioBroadcast sends correct request', () async {
      await api.retryRadioBroadcast('radio_123');
      expect(capturedRequests.last.url.toString(), contains('/radio/broadcasts/radio_123/retry'));
    });
  });

  group('BackendApi - Evidence Endpoints', () {
    test('uploadEvidence sends correct body', () async {
      await api.uploadEvidence(
        parentId: 'alert_123',
        evidenceType: 'photo',
        fileName: 'evidence.jpg',
        fileBytes: 'base64encodedbytes',
        mimeType: 'image/jpeg',
        parentType: 'alert',
        latitude: 6.5244,
        longitude: 3.3792,
      );
      final request = capturedRequests.last as http.Request;
      final body = json.decode(request.body);
      expect(body['parentId'], 'alert_123');
      expect(body['evidenceType'], 'photo');
      expect(body['fileName'], 'evidence.jpg');
      expect(body['mimeType'], 'image/jpeg');
      expect(body['fileContent'], 'base64encodedbytes');
    });

    test('getEvidence builds correct URL', () async {
      await api.getEvidence('alert_123');
      expect(capturedRequests.last.url.toString(), contains('/evidence/parent/alert_123'));
    });

    test('getEvidenceById builds correct URL', () async {
      await api.getEvidenceById('evidence_123');
      expect(capturedRequests.last.url.toString(), contains('/evidence/evidence_123'));
    });

    test('deleteEvidence sends correct request', () async {
      await api.deleteEvidence('evidence_123');
      expect(capturedRequests.last.url.toString(), contains('/evidence/evidence_123'));
      expect(capturedRequests.last.method, 'DELETE');
    });

    test('deleteEvidenceForParent sends correct request', () async {
      await api.deleteEvidenceForParent('alert_123');
      expect(capturedRequests.last.url.toString(), contains('/evidence/parent/alert_123'));
      expect(capturedRequests.last.method, 'DELETE');
    });
  });

  group('BackendApi - Observability Endpoints', () {
    test('sendTraces does not throw', () async {
      await api.sendTraces([
        {'traceId': 'abc', 'spanId': 'def', 'name': 'test'}
      ]);
      expect(capturedRequests.last.url.toString(), contains('/observability/traces'));
    });

    test('sendMetrics does not throw', () async {
      await api.sendMetrics([
        {'name': 'test_metric', 'value': 42}
      ]);
      expect(capturedRequests.last.url.toString(), contains('/observability/metrics'));
    });

    test('sendLogs does not throw', () async {
      await api.sendLogs([
        {'level': 'INFO', 'message': 'test log'}
      ]);
      expect(capturedRequests.last.url.toString(), contains('/observability/logs'));
    });

    test('sendCrashReport does not throw', () async {
      await api.sendCrashReport({
        'error': 'Test error',
        'stackTrace': 'at main.dart:42',
        'deviceInfo': {'platform': 'android'},
      });
      expect(capturedRequests.last.url.toString(), contains('/observability/crash-report'));
    });
  });

  group('BackendApi - Error Handling', () {
    test('ApiException is thrown on non-2xx', () async {
      mockClient = MockClient((request) async {
        return http.Response(json.encode({'error': 'Not found'}), 404);
      });
      api.setClient(mockClient);

      expect(
        () => api.getActiveZones(),
        throwsA(isA<ApiException>()),
      );
    });

    test('ApiException contains correct status code', () async {
      mockClient = MockClient((request) async {
        return http.Response(json.encode({'error': 'Forbidden'}), 403);
      });
      api.setClient(mockClient);

      try {
        await api.getActiveZones();
        fail('Expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.body, contains('Forbidden'));
      }
    });

    test('ApiException toString returns formatted message', () {
      final ex = ApiException(401, 'Unauthorized');
      expect(ex.toString(), contains('401'));
      expect(ex.toString(), contains('Unauthorized'));
    });

    test('circuit breaker opens after 5 failures', () async {
      // Disable retries for this test to avoid timeout from exponential backoff
      api.setRetryCount(1);

      mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });
      api.setClient(mockClient);

      // Make 5 failing requests
      for (int i = 0; i < 5; i++) {
        try {
          await api.getActiveZones();
        } catch (_) {}
      }

      // Verify circuit breaker state is open after 5 consecutive failures
      expect(api.isCircuitOpen(), true);

      // The next request: forceResetCircuitBreaker() runs before _executeWithCircuitBreaker(),
      // so the circuit is reset to closed. The request then proceeds and gets a 500 from the mock.
      try {
        await api.getActiveZones();
        fail('Expected ApiException for server error');
      } on ApiException catch (e) {
        // forceResetCircuitBreaker resets the circuit, so we get the server's 500, not 503
        expect(e.statusCode, 500);
      }
    });

    test('circuit breaker resets after resetCircuitBreaker', () async {
      // Disable retries for this test to avoid timeout from exponential backoff
      api.setRetryCount(1);

      // First open the circuit
      mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });
      api.setClient(mockClient);

      for (int i = 0; i < 5; i++) {
        try {
          await api.getActiveZones();
        } catch (_) {}
      }

      // Reset
      api.resetCircuitBreaker();

      // Now it should try again (and fail with 500, not circuit breaker)
      mockClient = MockClient((request) async {
        return http.Response(json.encode({'status': 'ok'}), 200);
      });
      api.setClient(mockClient);

      final result = await api.getActiveZones();
      expect(result, {'status': 'ok'});
    });
  });

  group('BackendApi - Auth Header', () {
    test('includes Bearer token when available', () async {
      // Save a token to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'test_bearer_token');

      await api.getActiveZones();
      final headers = capturedRequests.last.headers;
      expect(headers['Authorization'], 'Bearer test_bearer_token');
    });

    test('does not include Authorization header when no token', () async {
      SharedPreferences.setMockInitialValues({});
      // Clear any cached token from previous tests
      api.invalidateTokenCache();

      await api.getActiveZones();
      final headers = capturedRequests.last.headers;
      expect(headers.containsKey('Authorization'), false);
    });
  });

  group('BackendApi - Response Parsing', () {
    test('parses JSON list response as data wrapper', () async {
      mockClient = MockClient((request) async {
        return http.Response(json.encode([
          {'id': '1', 'name': 'Item 1'},
          {'id': '2', 'name': 'Item 2'},
        ]), 200);
      });
      api.setClient(mockClient);

      final result = await api.getActiveZones();
      expect(result, containsPair('data', isA<List>()));
      expect((result['data'] as List).length, 2);
    });

    test('handles empty response body', () async {
      mockClient = MockClient((request) async {
        return http.Response('', 204);
      });
      api.setClient(mockClient);

      final result = await api.getActiveZones();
      expect(result, isEmpty);
    });
  });
}
