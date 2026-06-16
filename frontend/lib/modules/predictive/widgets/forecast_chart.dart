import 'package:flutter/material.dart';
import '../services/predictive_engine.dart';

/// A chart widget that displays ML forecast time-series data.
///
/// Shows risk score over time with color-coded alert levels.
/// Supports both the new ML forecast points and legacy time-series data.
class ForecastChart extends StatelessWidget {
  final List<ForecastPoint> forecastPoints;
  final double maxRiskScore;
  final double height;

  const ForecastChart({
    super.key,
    required this.forecastPoints,
    this.maxRiskScore = 1.0,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (forecastPoints.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No forecast data available', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _ForecastChartPainter(
          forecastPoints: forecastPoints,
          maxRiskScore: maxRiskScore,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ForecastChartPainter extends CustomPainter {
  final List<ForecastPoint> forecastPoints;
  final double maxRiskScore;

  _ForecastChartPainter({
    required this.forecastPoints,
    required this.maxRiskScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (forecastPoints.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..style = PaintingStyle.fill;

    final width = size.width;
    final height = size.height;
    final padding = 20.0;
    final chartWidth = width - padding * 2;
    final chartHeight = height - padding * 2;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final path = Path();
    final fillPath = Path();

    // Calculate time range
    final minTime = forecastPoints.first.timestamp.millisecondsSinceEpoch.toDouble();
    final maxTime = forecastPoints.last.timestamp.millisecondsSinceEpoch.toDouble();
    final timeRange = maxTime - minTime;

    for (int i = 0; i < forecastPoints.length; i++) {
      final point = forecastPoints[i];
      final x = padding + ((point.timestamp.millisecondsSinceEpoch.toDouble() - minTime) / timeRange) * chartWidth;
      final y = padding + chartHeight - (point.riskScore / maxRiskScore) * chartHeight;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, padding + chartHeight);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // Draw dot with alert level color
      dotPaint.color = _alertLevelColor(point.alertLevel);
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }

    // Draw the line
    paint.color = Colors.blueAccent;
    canvas.drawPath(path, paint);

    // Draw fill below the line
    if (forecastPoints.isNotEmpty) {
      final lastX = padding + chartWidth;
      fillPath.lineTo(lastX, padding + chartHeight);
      fillPath.close();

      fillPaint.color = Colors.blueAccent.withOpacity(0.1);
      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw alert level threshold lines
    _drawThresholdLine(canvas, size, padding, chartHeight, 0.2, Colors.green.withOpacity(0.3), 'Normal');
    _drawThresholdLine(canvas, size, padding, chartHeight, 0.4, Colors.yellow.withOpacity(0.3), 'Elevated');
    _drawThresholdLine(canvas, size, padding, chartHeight, 0.6, Colors.orange.withOpacity(0.3), 'High');
    _drawThresholdLine(canvas, size, padding, chartHeight, 0.8, Colors.red.withOpacity(0.3), 'Severe');
  }

  void _drawThresholdLine(Canvas canvas, Size size, double padding, double chartHeight, double threshold, Color color, String label) {
    final y = padding + chartHeight - (threshold / maxRiskScore) * chartHeight;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - padding - textPainter.width - 4, y - textPainter.height - 2));
  }

  Color _alertLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return Colors.deepPurple;
      case 'severe':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'elevated':
        return Colors.yellow.shade700;
      case 'normal':
      default:
        return Colors.green;
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastChartPainter oldDelegate) {
    return oldDelegate.forecastPoints != forecastPoints;
  }
}

/// A simplified bar chart showing state-level risk scores.
class StateRiskBarChart extends StatelessWidget {
  final List<StateForecast> forecasts;
  final double height;

  const StateRiskBarChart({
    super.key,
    required this.forecasts,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    if (forecasts.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No state forecast data')),
      );
    }

    // Sort by risk score descending, take top 10
    final sorted = List<StateForecast>.from(forecasts)
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));
    final topStates = sorted.take(10).toList();

    return SizedBox(
      height: height,
      child: ListView.builder(
        itemCount: topStates.length,
        itemBuilder: (context, index) {
          final state = topStates[index];
          final barWidth = state.riskScore * 200;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    state.state,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        width: barWidth.clamp(4.0, double.infinity),
                        height: 20,
                        decoration: BoxDecoration(
                          color: _riskColor(state.riskScore),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(state.riskScore * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _riskColor(state.riskScore),
                    ),
                  ),
                ),
                Icon(
                  _trendIcon(state.trendDirection),
                  size: 16,
                  color: _trendColor(state.trendDirection),
                ),
              ],
            ),
          );
        },
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
