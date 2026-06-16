import 'dart:async';
import 'package:flutter/material.dart';
import '../services/predictive_engine.dart';
import '../widgets/forecast_chart.dart';
import '../widgets/hotspot_card.dart';
import '../../maps/services/map_service.dart';

/// Main dashboard screen for the predictive ML model.
///
/// Displays:
/// - Current threat level gauge
/// - ML forecast chart for the user's area
/// - Hotspot predictions list
/// - All-states risk overview
/// - Model training status and controls
class PredictiveDashboardScreen extends StatefulWidget {
  const PredictiveDashboardScreen({super.key});

  @override
  State<PredictiveDashboardScreen> createState() => _PredictiveDashboardScreenState();
}

class _PredictiveDashboardScreenState extends State<PredictiveDashboardScreen>
    with SingleTickerProviderStateMixin {
  final PredictiveEngine _engine = PredictiveEngine();
  final MapService _mapService = MapService();

  late TabController _tabController;

  // State
  bool _isLoading = true;
  bool _isTraining = false;
  String? _error;

  // ML Forecast
  MLForecastResult? _forecastResult;
  HotspotResult? _hotspotResult;
  AllStatesForecastResult? _allStatesResult;
  Map<String, dynamic>? _modelInfo;

  // Auto-refresh
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    // Auto-refresh every 5 minutes
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final position = _mapService.currentPosition;
      final results = await Future.wait([
        if (position != null)
          _engine.getMLForecast(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 50,
            hours: 48,
          )
        else
          Future.value(MLForecastResult(
            latitude: 9.08,
            longitude: 7.48,
            forecastPoints: [],
            hotspots: [],
          )),
        if (position != null)
          _engine.getHotspots(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 100,
          )
        else
          _engine.getHotspots(latitude: 9.08, longitude: 7.48, radiusKm: 100),
        _engine.getAllStatesForecast(),
        _engine.getModelInfo(),
      ]);

      setState(() {
        _forecastResult = results[0] as MLForecastResult;
        _hotspotResult = results[1] as HotspotResult;
        _allStatesResult = results[2] as AllStatesForecastResult;
        _modelInfo = results[3] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerTraining() async {
    setState(() => _isTraining = true);
    try {
      await _engine.triggerTraining(forceRetrain: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Training started'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Training failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isTraining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predictive Intelligence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: _isTraining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.model_training),
            onPressed: _isTraining ? null : _triggerTraining,
            tooltip: 'Train Model',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Forecast', icon: Icon(Icons.timeline)),
            Tab(text: 'Hotspots', icon: Icon(Icons.whatshot)),
            Tab(text: 'All States', icon: Icon(Icons.map)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildForecastTab(),
                    _buildHotspotsTab(),
                    _buildAllStatesTab(),
                  ],
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Failed to load predictive data',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Forecast Tab
  // ---------------------------------------------------------------------------
  Widget _buildForecastTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current threat level card
          _buildThreatLevelCard(),
          const SizedBox(height: 16),

          // Forecast chart
          const Text('Risk Forecast (48h)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 220,
                child: _forecastResult != null &&
                        _forecastResult!.forecastPoints.isNotEmpty
                    ? ForecastChart(
                        forecastPoints: _forecastResult!.forecastPoints,
                      )
                    : const Center(child: Text('No forecast data available')),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Model info
          if (_modelInfo != null) _buildModelInfoCard(),
        ],
      ),
    );
  }

  Widget _buildThreatLevelCard() {
    // Calculate average risk from forecast
    double avgRisk = 0;
    if (_forecastResult != null && _forecastResult!.forecastPoints.isNotEmpty) {
      avgRisk = _forecastResult!.forecastPoints
              .map((p) => p.riskScore)
              .reduce((a, b) => a + b) /
          _forecastResult!.forecastPoints.length;
    }

    final level = _alertLevel(avgRisk);
    final color = _alertColor(avgRisk);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: avgRisk,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(color),
                      strokeWidth: 8,
                    ),
                  ),
                  Text(
                    '${(avgRisk * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Threat Level: $level',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on ML model analysis of your area',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (_forecastResult != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_forecastResult!.hotspots.length} hotspots detected',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelInfoCard() {
    final status = _modelInfo!['status'] as String? ?? 'unknown';
    final modelVersion = _modelInfo!['model_version'] as String? ?? 'N/A';
    final lastTraining = _modelInfo!['last_training'] as String? ?? 'N/A';
    final cellsTrained = _modelInfo!['cells_trained'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Model Information',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Divider(),
            _infoRow('Status', status),
            _infoRow('Version', modelVersion),
            _infoRow('Last Training', lastTraining),
            _infoRow('Cells Trained', cellsTrained.toString()),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hotspots Tab
  // ---------------------------------------------------------------------------
  Widget _buildHotspotsTab() {
    final hotspots = _hotspotResult?.hotspots ?? [];

    if (hotspots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text('No hotspots detected in your area',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Sort by risk score descending
    final sorted = List<HotspotPrediction>.from(hotspots)
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: sorted.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('${sorted.length} Hotspot Predictions',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_hotspotResult!.cached)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Cached',
                          style: TextStyle(fontSize: 11, color: Colors.orange)),
                    ),
                ],
              ),
            );
          }
          final hotspot = sorted[index - 1];
          return HotspotCard(
            hotspot: hotspot,
            onTap: () => _showHotspotDetail(context, hotspot),
          );
        },
      ),
    );
  }

  void _showHotspotDetail(BuildContext context, HotspotPrediction hotspot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                HotspotCard(hotspot: hotspot),
                const SizedBox(height: 16),
                const Text('Recommended Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _actionItem('Increase patrols in this area'),
                _actionItem('Alert local security agencies'),
                _actionItem('Monitor communication channels'),
                _actionItem('Prepare emergency response teams'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actionItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: Colors.blue.shade400),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // All States Tab
  // ---------------------------------------------------------------------------
  Widget _buildAllStatesTab() {
    final forecasts = _allStatesResult?.forecasts ?? [];

    if (forecasts.isEmpty) {
      return const Center(child: Text('No state forecast data'));
    }

    return Column(
      children: [
        if (_allStatesResult?.generatedAt != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Generated: ${_formatDateTime(_allStatesResult!.generatedAt!)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        Expanded(
          child: StateRiskBarChart(forecasts: forecasts),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _alertLevel(double riskScore) {
    if (riskScore >= 0.8) return 'Critical';
    if (riskScore >= 0.6) return 'Severe';
    if (riskScore >= 0.4) return 'High';
    if (riskScore >= 0.2) return 'Elevated';
    return 'Normal';
  }

  Color _alertColor(double riskScore) {
    if (riskScore >= 0.8) return Colors.deepPurple;
    if (riskScore >= 0.6) return Colors.red;
    if (riskScore >= 0.4) return Colors.orange;
    if (riskScore >= 0.2) return Colors.yellow.shade700;
    return Colors.green;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
