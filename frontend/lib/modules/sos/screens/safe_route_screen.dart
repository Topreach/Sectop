import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/widgets/global_location_picker.dart';
import '../../monetization/widgets/feature_gate.dart';

/// Screen to plan a safe route avoiding danger zones.
/// Users select start and destination locations by place name (state/town)
/// instead of entering raw latitude/longitude coordinates.
/// Can also receive pre-filled coordinates via route arguments.
class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({Key? key}) : super(key: key);

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> with FeatureGateMixin {
  final BackendApi _api = BackendApi();

  // WebSocket/STOMP for fast route planning
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;
  StreamSubscription<dynamic>? _wsSubscription;

  // From location
  double? _fromLat;
  double? _fromLng;
  String? _fromName;

  // To location
  double? _toLat;
  double? _toLng;
  String? _toName;

  Map<String, dynamic>? _routeResult;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  /// Connect to WebSocket for STOMP SEND fast path.
  Future<void> _connectWebSocket() async {
    try {
      final storage = OfflineStorageService();
      final token = await storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return;

      final wsUrl = AppConstants.wsBaseUrl;
      final wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel = wsChannel;
      _isWsConnected = true;

      // Send STOMP CONNECT frame
      _sendStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'localhost',
        'Authorization': 'Bearer $token',
      });

      // Subscribe to user's personal queue for route results
      _sendStompFrame('SUBSCRIBE', {
        'id': 'route-result',
        'destination': '/user/queue/route/result',
      });

      // Listen for incoming STOMP frames
      _wsSubscription = wsChannel.stream.listen((data) {
        _handleStompFrame(data as String);
      });

      debugPrint('SafeRouteScreen: WebSocket connected for STOMP fast path');
    } catch (e) {
      debugPrint('SafeRouteScreen: WebSocket connection failed: $e');
      _isWsConnected = false;
    }
  }

  /// Handle incoming STOMP frames from the server.
  void _handleStompFrame(String frame) {
    if (frame.startsWith('MESSAGE')) {
      // Extract the body after the headers
      // STOMP protocol uses \r\n line endings
      final parts = frame.split('\r\n\r\n');
      if (parts.length >= 2) {
        final body = parts.sublist(1).join('\r\n\r\n').trim().replaceAll('\0', '');
        if (body.isNotEmpty) {
          try {
            final result = json.decode(body) as Map<String, dynamic>;
            if (result['success'] == true && result['data'] != null) {
              setState(() {
                _routeResult = result['data'] as Map<String, dynamic>;
                _isLoading = false;
              });
            } else if (result['success'] == false) {
              setState(() {
                _isLoading = false;
                _error = result['error'] as String? ?? 'Route planning failed';
              });
            }
          } catch (e) {
            debugPrint('SafeRouteScreen: Failed to parse STOMP message: $e');
          }
        }
      }
    }
  }

  /// Send a raw STOMP frame over the WebSocket.
  /// Uses \r\n line endings per the STOMP protocol specification.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_wsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.write(command);
      buffer.write('\r\n');
      headers.forEach((key, value) {
        buffer.write('$key:$value');
        buffer.write('\r\n');
      });
      buffer.write('\r\n');
      if (body != null && body.isNotEmpty) {
        buffer.write(body);
      }
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('SafeRouteScreen: Failed to send STOMP frame: $e');
    }
  }

  /// Send route planning request via STOMP SEND for instant delivery.
  void _sendRouteViaStomp(Map<String, dynamic> routeData) {
    if (_wsChannel == null || !_isWsConnected) {
      debugPrint('SafeRouteScreen: WebSocket not connected, using HTTP');
      return;
    }
    try {
      final body = json.encode(routeData);
      _sendStompFrame('SEND', {
        'destination': '/app/route/plan',
        'content-type': 'application/json',
      }, body: body);
      debugPrint('SafeRouteScreen: Route request sent via STOMP SEND');
    } catch (e) {
      debugPrint('SafeRouteScreen: STOMP SEND failed: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for route arguments (from MapScreen "Navigate Safely" button)
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && _fromLat == null) {
      setState(() {
        _fromLat = args['fromLat'] as double?;
        _fromLng = args['fromLng'] as double?;
        _fromName = args['fromName'] as String?;
        _toLat = args['toLat'] as double?;
        _toLng = args['toLng'] as double?;
        _toName = args['toName'] as String?;
      });
      // Auto-plan route if both locations are provided
      if (_fromLat != null && _toLat != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _planRoute());
      }
    }
  }

  void _onFromLocationSelected(double? lat, double? lng, String? name) {
    setState(() {
      _fromLat = lat;
      _fromLng = lng;
      _fromName = name;
      _error = null;
      _routeResult = null;
    });
  }

  void _onToLocationSelected(double? lat, double? lng, String? name) {
    setState(() {
      _toLat = lat;
      _toLng = lng;
      _toName = name;
      _error = null;
      _routeResult = null;
    });
  }

  Future<void> _planRoute() async {
    if (_fromLat == null || _fromLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a starting location')),
      );
      return;
    }
    if (_toLat == null || _toLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination location')),
      );
      return;
    }

    // Check feature access — route planning costs 2 points
    final hasAccess = await checkFeatureAccess('route_plan', 'Route Planning');
    if (!hasAccess) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final routeData = <String, dynamic>{
      'userId': '', // Will be populated from auth
      'fromLat': _fromLat,
      'fromLng': _fromLng,
      'toLat': _toLat,
      'toLng': _toLng,
      'avoidHighways': false,
      'preferLitRoads': false,
    };

    // STEP 1: Send via STOMP SEND over existing WebSocket (FASTEST PATH - ~1ms)
    _sendRouteViaStomp(routeData);

    // STEP 2: Fire HTTP POST in the background as reliability fallback
    // The STOMP result will arrive via WebSocket subscription and update the UI
    unawaited(_planRouteViaHttp());
  }

  /// Fallback: plan route via HTTP POST (used when WebSocket is unavailable).
  Future<void> _planRouteViaHttp() async {
    try {
      final result = await _api.planSafeRoute(
        fromLat: _fromLat!, fromLng: _fromLng!,
        toLat: _toLat!, toLng: _toLng!,
      );
      if (mounted) {
        setState(() {
          _routeResult = result;
          _isLoading = false;
        });
      }
      // Spend points for route planning (2 pts)
      unawaited(spendPointsForFeature('route_plan'));
      // Cache the successful route result locally for offline fallback
      try {
        final storage = OfflineStorageService();
        final cacheKey = 'cached_route_${_fromLat!.toStringAsFixed(4)}_${_fromLng!.toStringAsFixed(4)}_${_toLat!.toStringAsFixed(4)}_${_toLng!.toStringAsFixed(4)}';
        await storage.saveSetting(cacheKey, json.encode({
          'result': result,
          'fromName': _fromName,
          'toName': _toName,
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        // Try to load cached route when offline
        try {
          final storage = OfflineStorageService();
          final cacheKey = 'cached_route_${_fromLat!.toStringAsFixed(4)}_${_fromLng!.toStringAsFixed(4)}_${_toLat!.toStringAsFixed(4)}_${_toLng!.toStringAsFixed(4)}';
          final cached = await storage.getSetting(cacheKey);
          if (cached != null && cached is String) {
            final decoded = json.decode(cached) as Map<String, dynamic>;
            if (decoded['result'] != null) {
              setState(() {
                _routeResult = decoded['result'] as Map<String, dynamic>;
                _isLoading = false;
                _error = null;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Showing cached route — offline'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              return;
            }
          }
        } catch (_) {}
        // No cached route available — show error
        setState(() {
          _isLoading = false;
          _error = 'Failed to plan route: $e';
        });
      }
    }
  }

  void _swapLocations() {
    setState(() {
      final tempLat = _fromLat;
      final tempLng = _fromLng;
      final tempName = _fromName;
      _fromLat = _toLat;
      _fromLng = _toLng;
      _fromName = _toName;
      _toLat = tempLat;
      _toLng = tempLng;
      _toName = tempName;
      _error = null;
      _routeResult = null;
    });
  }

  Color _dangerColor(String level) {
    switch (level) {
      case 'safe': return Colors.green;
      case 'caution': return Colors.orange;
      case 'dangerous': return Colors.red;
      case 'critical': return Colors.deepPurple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Route Planning'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select your start and destination locations',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // From location picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text('From', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        if (_fromName != null)
                          Text(_fromName!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GlobalLocationPicker(
                      label: 'Starting Location',
                      onLocationSelected: _onFromLocationSelected,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Swap button
            Center(
              child: IconButton(
                onPressed: _fromLat != null || _toLat != null ? _swapLocations : null,
                icon: const Icon(Icons.swap_vert, color: AppTheme.primaryColor),
                tooltip: 'Swap start and destination',
              ),
            ),
            const SizedBox(height: 8),

            // To location picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        const Text('To', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        if (_toName != null)
                          Text(_toName!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GlobalLocationPicker(
                      label: 'Destination',
                      onLocationSelected: _onToLocationSelected,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Plan route button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _planRoute,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.route),
              label: Text(_isLoading ? 'Planning...' : 'Plan Safe Route'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),

            // Error display
            if (_error != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),

            // Results
            if (_routeResult != null) ...[
              // Mini-map showing the route
              if (_fromLat != null && _toLat != null)
                _buildMiniRouteMap(),
              const SizedBox(height: 16),

              const Text('Route Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildResultCard('Overall Danger', _routeResult!['overallDangerLevel'] as String? ?? 'unknown',
                  _routeResult!['overallDangerScore']?.toString() ?? '0'),
              const SizedBox(height: 8),
              _buildResultCard('Max Segment Danger', _routeResult!['maxSegmentDangerScore']?.toString() ?? '0', null),
              const SizedBox(height: 8),
              _buildResultCard('Total Distance', '${_routeResult!['totalDistanceKm'] ?? '?'} km', null),
              const SizedBox(height: 8),
              _buildResultCard('Est. Duration', '${_routeResult!['estimatedDurationMinutes'] ?? '?'} min', null),
              const SizedBox(height: 8),
              _buildResultCard('Nearby Incidents', '${_routeResult!['nearbyIncidentCount'] ?? 0}', null),
              const SizedBox(height: 8),
              _buildResultCard('Nearby Danger Zones', '${_routeResult!['nearbyDangerZoneCount'] ?? 0}', null),

              if (_routeResult!['routes'] != null) ...[
                const SizedBox(height: 16),
                const Text('Route Segments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(_routeResult!['routes'] as List).take(1).expand((route) {
                  final segments = (route as Map<String, dynamic>)['segments'] as List? ?? [];
                  return segments.map((seg) {
                    final s = seg as Map<String, dynamic>;
                    final level = s['dangerLevel'] as String? ?? 'unknown';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.circle, color: _dangerColor(level), size: 12),
                        title: Text('Score: ${s['dangerScore']}'),
                        subtitle: Text('Level: $level'),
                      ),
                    );
                  });
                }),
              ],

              // Open in Map button
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/map',
                  );
                },
                icon: const Icon(Icons.map),
                label: const Text('View on Emergency Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build a mini-map showing the route with color-coded danger segments.
  Widget _buildMiniRouteMap() {
    // Collect all waypoints from the first route
    List<LatLng> routePoints = [];
    List<Color> segmentColors = [];

    if (_routeResult != null && _routeResult!['routes'] is List) {
      final routes = _routeResult!['routes'] as List;
      if (routes.isNotEmpty) {
        final firstRoute = routes[0] as Map<String, dynamic>;
        final segments = firstRoute['segments'] as List? ?? [];
        for (final seg in segments) {
          final s = seg as Map<String, dynamic>;
          final startLat = (s['startLat'] as num).toDouble();
          final startLng = (s['startLng'] as num).toDouble();
          final endLat = (s['endLat'] as num).toDouble();
          final endLng = (s['endLng'] as num).toDouble();
          final level = s['dangerLevel'] as String? ?? 'safe';
          routePoints.add(LatLng(startLat, startLng));
          segmentColors.add(_dangerColor(level));
        }
        // Add the last endpoint
        if (segments.isNotEmpty) {
          final lastSeg = segments.last as Map<String, dynamic>;
          routePoints.add(LatLng(
            (lastSeg['endLat'] as num).toDouble(),
            (lastSeg['endLng'] as num).toDouble(),
          ));
        }
      }
    }

    // If no segments yet, just show start/end points
    if (routePoints.isEmpty) {
      routePoints = [
        LatLng(_fromLat!, _fromLng!),
        LatLng(_toLat!, _toLng!),
      ];
    }

    // Calculate bounding box for the route
    double minLat = _fromLat!;
    double maxLat = _fromLat!;
    double minLng = _fromLng!;
    double maxLng = _fromLng!;

    for (final p in routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add padding
    final latPad = (maxLat - minLat) * 0.3 + 0.02;
    final lngPad = (maxLng - minLng) * 0.3 + 0.02;
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLng),
            initialZoom: 9,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.dangeremergence.app',
            ),
            // Route polylines with color-coded segments
            PolylineLayer<Object>(
              polylines: [
                // Draw each segment with its danger color
                for (int i = 0; i < routePoints.length - 1; i++)
                  Polyline(
                    points: [routePoints[i], routePoints[i + 1]],
                    color: i < segmentColors.length
                        ? segmentColors[i]
                        : Colors.grey,
                    strokeWidth: 5,
                  ),
              ],
            ),
            // Start marker
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_fromLat!, _fromLng!),
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.trip_origin, color: Colors.white, size: 16),
                  ),
                ),
                Marker(
                  point: LatLng(_toLat!, _toLng!),
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String label, String value, String? level) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
            if (level != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _dangerColor(level).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  level.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: _dangerColor(level),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
