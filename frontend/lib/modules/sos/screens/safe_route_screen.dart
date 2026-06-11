import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/widgets/nigeria_location_picker.dart';

/// Screen to plan a safe route avoiding danger zones.
/// Users select start and destination locations by place name (state/town)
/// instead of entering raw latitude/longitude coordinates.
class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({Key? key}) : super(key: key);

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  final BackendApi _api = BackendApi();

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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.planSafeRoute(
        fromLat: _fromLat!, fromLng: _fromLng!,
        toLat: _toLat!, toLng: _toLng!,
      );
      setState(() {
        _routeResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to plan route: $e';
      });
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
                    NigeriaLocationPicker(
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
                    NigeriaLocationPicker(
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
            ],
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
