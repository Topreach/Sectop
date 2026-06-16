import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../core/routes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../maps/services/map_service.dart';

/// Card widget that shows nearby danger zones (terrorist hotspots) on the
/// dashboard. Fetches data from the backend API and falls back to local cache.
/// Also subscribes to real-time zone updates via WebSocket.
class TerroristLocationCard extends StatefulWidget {
  const TerroristLocationCard({Key? key}) : super(key: key);

  @override
  State<TerroristLocationCard> createState() => _TerroristLocationCardState();
}

class _TerroristLocationCardState extends State<TerroristLocationCard> {
  List<Map<String, dynamic>> _dangerZones = [];
  bool _isLoading = true;
  String? _error;

  // WebSocket/STOMP for real-time zone updates
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;
  StreamSubscription<dynamic>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _loadDangerZones();
    _connectWebSocket();
  }

  /// Connect to WebSocket for real-time danger zone updates.
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

      // Subscribe to danger zone updates topic
      _sendStompFrame('SUBSCRIBE', {
        'id': 'danger-zones',
        'destination': '/topic/zones/danger',
      });

      // Listen for incoming STOMP frames
      _wsSubscription = wsChannel.stream.listen((data) {
        _handleStompFrame(data as String);
      });

      debugPrint('TerroristLocationCard: WebSocket connected for real-time zone updates');
    } catch (e) {
      debugPrint('TerroristLocationCard: WebSocket connection failed: $e');
      _isWsConnected = false;
    }
  }

  /// Handle incoming STOMP frames from the server.
  void _handleStompFrame(String frame) {
    if (frame.startsWith('MESSAGE')) {
      // Extract the body after the headers
      final parts = frame.split('\n\n');
      if (parts.length >= 2) {
        final body = parts.sublist(1).join('\n\n').trim().replaceAll('\0', '');
        if (body.isNotEmpty) {
          try {
            final data = json.decode(body);
            if (data is Map<String, dynamic>) {
              // Single zone update
              _updateZoneFromMessage(data);
            } else if (data is List) {
              // Batch zone update
              for (final zone in data) {
                if (zone is Map<String, dynamic>) {
                  _updateZoneFromMessage(zone);
                }
              }
            }
          } catch (e) {
            debugPrint('TerroristLocationCard: Failed to parse STOMP message: $e');
          }
        }
      }
    }
  }

  /// Update the local zone list from a WebSocket message.
  void _updateZoneFromMessage(Map<String, dynamic> zoneData) {
    if (!mounted) return;
    final zoneId = zoneData['id'] as String?;
    if (zoneId == null) return;

    setState(() {
      // Check if this zone already exists
      final existingIndex = _dangerZones.indexWhere((z) => z['id'] == zoneId);
      if (existingIndex >= 0) {
        // Update existing zone
        _dangerZones[existingIndex] = zoneData;
      } else {
        // Add new zone at the beginning
        _dangerZones.insert(0, zoneData);
      }
      _error = null;
    });
  }

  /// Send a raw STOMP frame over the WebSocket.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_wsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.writeln(command);
      headers.forEach((key, value) {
        buffer.writeln('$key:$value');
      });
      buffer.writeln();
      if (body != null && body.isNotEmpty) {
        buffer.write(body);
      }
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('TerroristLocationCard: Failed to send STOMP frame: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  Future<void> _loadDangerZones() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try backend API first
      final response = await BackendApi().getDangerZones();
      final data = response['data'];
      if (data is List) {
        setState(() {
          _dangerZones = data.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
        return;
      }
      if (response['zones'] is List) {
        setState(() {
          _dangerZones = (response['zones'] as List).cast<Map<String, dynamic>>();
          _isLoading = false;
        });
        return;
      }
    } catch (_) {
      // Backend unavailable — fall back to local cache
      debugPrint('TerroristLocationCard: Backend unavailable, using local cache');
    }

    // Fallback: load from offline storage
    try {
      final storage = OfflineStorageService();
      final cached = await storage.query('zones',
          where: 'type = ? AND status = ?',
          whereArgs: ['danger', 'active'],
          orderBy: 'created_at DESC');
      setState(() {
        _dangerZones = cached;
        _isLoading = false;
        if (cached.isEmpty) {
          _error = 'No danger zones reported in your area';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Could not load danger zone data';
      });
    }
  }

  Color _severityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return const Color(0xFFB71C1C);
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.amber;
      default:
        return Colors.red;
    }
  }

  IconData _severityIcon(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return Icons.gps_fixed;
      case 'high':
        return Icons.warning_amber_rounded;
      case 'medium':
        return Icons.info_outline;
      case 'low':
        return Icons.notifications_none;
      default:
        return Icons.place;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        gradient: LinearGradient(
          colors: [
            Colors.red.withOpacity(0.05),
            Colors.orange.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Terrorist / Danger Locations',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.red,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Reported danger zones near you',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Refresh button
                GestureDetector(
                  onTap: _loadDangerZones,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                ),
              ),
            )
          else if (_error != null && _dangerZones.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.shield_outlined, size: 40, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadDangerZones,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(
              _dangerZones.length > 3 ? 3 : _dangerZones.length,
              (index) {
                final zone = _dangerZones[index];
                final name = zone['name'] as String? ?? 'Unknown Location';
                final severity = zone['severity'] as String? ?? 'high';
                final description = zone['description'] as String?;
                final distance = zone['distanceKm'];
                final color = _severityColor(severity);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.withOpacity(0.15),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Severity indicator
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Zone info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (description != null && description.isNotEmpty)
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Severity badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          severity.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      if (distance != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${distance.toStringAsFixed(1)}km',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

          // Footer: View on Map button
          if (_dangerZones.isNotEmpty)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.withOpacity(0.15)),
                ),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.map);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.map_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _dangerZones.length > 3
                          ? 'View all ${_dangerZones.length} danger zones on map'
                          : 'View on map',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
