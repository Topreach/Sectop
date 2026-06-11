import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';

/// Screen to plan a safe route avoiding danger zones.
class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({Key? key}) : super(key: key);

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  final _fromLatController = TextEditingController();
  final _fromLngController = TextEditingController();
  final _toLatController = TextEditingController();
  final _toLngController = TextEditingController();
  final BackendApi _api = BackendApi();

  Map<String, dynamic>? _routeResult;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _fromLatController.dispose();
    _fromLngController.dispose();
    _toLatController.dispose();
    _toLngController.dispose();
    super.dispose();
  }

  Future<void> _planRoute() async {
    final fromLat = double.tryParse(_fromLatController.text);
    final fromLng = double.tryParse(_fromLngController.text);
    final toLat = double.tryParse(_toLatController.text);
    final toLng = double.tryParse(_toLngController.text);

    if (fromLat == null || fromLng == null || toLat == null || toLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid coordinates')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.planSafeRoute(
        fromLat: fromLat, fromLng: fromLng,
        toLat: toLat, toLng: toLng,
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
              'Enter start and destination coordinates',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // From coordinates
            const Text('From', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromLatController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                      hintText: '9.0765',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fromLngController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                      hintText: '7.3986',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // To coordinates
            const Text('To', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toLatController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                      hintText: '6.5244',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _toLngController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                      hintText: '3.3792',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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

            // Results
            if (_error != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),

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
