import 'package:flutter/material.dart';
import '../services/predictive_engine.dart';

/// A card widget that displays a single hotspot prediction from the ML model.
///
/// Shows risk score, alert level, location, trend direction, peak time,
/// expected incident count, and contributing factors.
class HotspotCard extends StatelessWidget {
  final HotspotPrediction hotspot;
  final VoidCallback? onTap;
  final bool compact;

  const HotspotCard({
    super.key,
    required this.hotspot,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactCard(context);
    }
    return _buildFullCard(context);
  }

  Widget _buildCompactCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _alertLevelIcon(hotspot.alertLevel),
        title: Text(
          hotspot.state ?? 'Unknown Location',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          'Risk: ${(hotspot.riskScore * 100).toStringAsFixed(0)}% · ${hotspot.trendDirection}',
          style: TextStyle(fontSize: 12, color: _riskColor(hotspot.riskScore)),
        ),
        trailing: _alertLevelBadge(hotspot.alertLevel),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _riskColor(hotspot.riskScore).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  _alertLevelIcon(hotspot.alertLevel, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hotspot.state ?? 'Unknown Location',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hotspot.lga != null)
                          Text(
                            hotspot.lga!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _alertLevelBadge(hotspot.alertLevel),
                ],
              ),
              const Divider(height: 20),

              // Risk score bar
              Row(
                children: [
                  const Text('Risk Score: ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: hotspot.riskScore,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(_riskColor(hotspot.riskScore)),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(hotspot.riskScore * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _riskColor(hotspot.riskScore),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Details grid
              Row(
                children: [
                  _detailItem(Icons.schedule, 'Peak Time',
                      hotspot.peakTime != null
                          ? '${hotspot.peakTime!.hour.toString().padLeft(2, '0')}:${hotspot.peakTime!.minute.toString().padLeft(2, '0')}'
                          : 'N/A'),
                  const SizedBox(width: 16),
                  _detailItem(Icons.bar_chart, '24h Forecast',
                      hotspot.expectedCount24h.toStringAsFixed(1)),
                  const SizedBox(width: 16),
                  _detailItem(
                    _trendIcon(hotspot.trendDirection),
                    'Trend',
                    hotspot.trendDirection,
                    valueColor: _trendColor(hotspot.trendDirection),
                  ),
                ],
              ),

              // Contributing factors
              if (hotspot.contributingFactors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Contributing Factors:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: hotspot.contributingFactors.map((factor) {
                    return Chip(
                      label: Text(factor, style: const TextStyle(fontSize: 11)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.orange.shade50,
                    );
                  }).toList(),
                ),
              ],

              // Coordinates
              const SizedBox(height: 8),
              Text(
                '📍 ${hotspot.latitude.toStringAsFixed(4)}, ${hotspot.longitude.toStringAsFixed(4)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(IconData icon, String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertLevelIcon(String level, {double size = 24}) {
    IconData icon;
    Color color;
    switch (level.toLowerCase()) {
      case 'critical':
        icon = Icons.gpp_bad;
        color = Colors.deepPurple;
        break;
      case 'severe':
        icon = Icons.warning;
        color = Colors.red;
        break;
      case 'high':
        icon = Icons.error_outline;
        color = Colors.orange;
        break;
      case 'elevated':
        icon = Icons.info_outline;
        color = Colors.yellow.shade700;
        break;
      default:
        icon = Icons.check_circle_outline;
        color = Colors.green;
    }
    return Icon(icon, color: color, size: size);
  }

  Widget _alertLevelBadge(String level) {
    Color bgColor;
    Color textColor;
    switch (level.toLowerCase()) {
      case 'critical':
        bgColor = Colors.deepPurple;
        textColor = Colors.white;
        break;
      case 'severe':
        bgColor = Colors.red;
        textColor = Colors.white;
        break;
      case 'high':
        bgColor = Colors.orange;
        textColor = Colors.white;
        break;
      case 'elevated':
        bgColor = Colors.yellow.shade700;
        textColor = Colors.black;
        break;
      default:
        bgColor = Colors.green;
        textColor = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _riskColor(double score) {
    if (score >= 0.8) return Colors.deepPurple;
    if (score >= 0.6) return Colors.red;
    if (score >= 0.4) return Colors.orange;
    if (score >= 0.2) return Colors.yellow.shade700;
    return Colors.green;
  }

  IconData _trendIcon(String trend) {
    switch (trend.toLowerCase()) {
      case 'rising':
        return Icons.trending_up;
      case 'falling':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _trendColor(String trend) {
    switch (trend.toLowerCase()) {
      case 'rising':
        return Colors.red;
      case 'falling':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
