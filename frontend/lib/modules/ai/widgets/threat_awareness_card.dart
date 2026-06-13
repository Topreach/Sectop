import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/themes.dart';
import '../../../core/routes.dart';
import '../services/threat_awareness_service.dart';

/// Dashboard widget that shows real-time threat awareness information.
///
/// Displays:
/// - Current threat level indicator (color-coded bar)
/// - Nearby incident count
/// - Active danger zone count
/// - Recent threat alerts feed
/// - Quick access to map for visual threat view
class ThreatAwarenessCard extends StatefulWidget {
  const ThreatAwarenessCard({Key? key}) : super(key: key);

  @override
  State<ThreatAwarenessCard> createState() => _ThreatAwarenessCardState();
}

class _ThreatAwarenessCardState extends State<ThreatAwarenessCard> {
  @override
  void initState() {
    super.initState();
    // Start monitoring when widget mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThreatAwarenessService>().startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    final threatService = context.watch<ThreatAwarenessService>();
    final threatLevel = threatService.currentThreatLevel;
    final unreadCount = threatService.unreadCount;
    final incidentCount = threatService.nearbyIncidentCount;
    final zoneCount = threatService.nearbyDangerZoneCount;
    final criticalAlerts = threatService.criticalAlerts;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _threatColor(threatLevel).withOpacity(0.3),
        ),
        gradient: LinearGradient(
          colors: [
            _threatColor(threatLevel).withOpacity(0.08),
            _threatColor(threatLevel).withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(threatService, threatLevel, unreadCount),

          // Threat level bar
          _buildThreatLevelBar(threatLevel),

          // Stats row
          _buildStatsRow(threatLevel, incidentCount, zoneCount),

          // Critical alerts
          if (criticalAlerts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1),
            ),
            _buildCriticalAlertsList(criticalAlerts),
          ],

          // Recent alerts
          if (threatService.alerts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1),
            ),
            _buildRecentAlerts(threatService),
          ],

          // Empty state
          if (threatService.alerts.isEmpty && !threatService.isLoading)
            _buildEmptyState(),

          // Loading
          if (threatService.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // View all button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(AppRoutes.map),
                icon: const Icon(Icons.map, size: 18),
                label: const Text('View Threat Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _threatColor(threatLevel),
                  side: BorderSide(
                    color: _threatColor(threatLevel).withOpacity(0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThreatAwarenessService service,
    double threatLevel,
    int unreadCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _threatColor(threatLevel).withOpacity(0.1),
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
              color: _threatColor(threatLevel).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _threatIcon(threatLevel),
              color: _threatColor(threatLevel),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _threatLabel(threatLevel),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _threatColor(threatLevel),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Real-time threat monitoring active',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Unread badge
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _threatColor(threatLevel),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Refresh button
          GestureDetector(
            onTap: () => service.pollThreats(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.refresh,
                size: 18,
                color: _threatColor(threatLevel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatLevelBar(double threatLevel) {
    final color = _threatColor(threatLevel);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Threat Level',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              Text(
                '${(threatLevel * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: threatLevel,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Safe', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('Caution', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('Danger', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              Text('Critical', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(double threatLevel, int incidentCount, int zoneCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.warning_amber_rounded,
              label: 'Incidents',
              value: '$incidentCount',
              color: incidentCount > 0 ? Colors.deepOrange : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              icon: Icons.gps_fixed,
              label: 'Danger Zones',
              value: '$zoneCount',
              color: zoneCount > 0 ? Colors.red : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              icon: Icons.notifications_active,
              label: 'Alerts',
              value: '${(threatLevel * 100).toInt()}%',
              color: _threatColor(threatLevel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalAlertsList(List<ThreatAlert> alerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Critical Alerts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.red[700],
            ),
          ),
        ),
        ...alerts.take(3).map((alert) => _AlertTile(alert: alert)),
      ],
    );
  }

  Widget _buildRecentAlerts(ThreatAwarenessService service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Threats',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              GestureDetector(
                onTap: () => service.markAllAsRead(),
                child: Text(
                  'Mark all read',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...service.alerts.take(5).map((alert) => _AlertTile(
          alert: alert,
          onTap: () => service.markAsRead(alert.id),
        )),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.shield_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No threats detected in your area',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              'Monitoring ${20}km radius',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Color _threatColor(double level) {
    if (level >= 0.7) return const Color(0xFFB71C1C); // Critical - dark red
    if (level >= 0.4) return Colors.deepOrange; // High
    if (level >= 0.2) return Colors.orange; // Medium
    if (level >= 0.05) return Colors.amber; // Low
    return Colors.green; // Safe
  }

  IconData _threatIcon(double level) {
    if (level >= 0.7) return Icons.warning;
    if (level >= 0.4) return Icons.warning_amber_rounded;
    if (level >= 0.2) return Icons.info_outline;
    return Icons.shield;
  }

  String _threatLabel(double level) {
    if (level >= 0.7) return 'CRITICAL THREAT LEVEL';
    if (level >= 0.4) return 'High Threat Level';
    if (level >= 0.2) return 'Moderate Threat Level';
    if (level >= 0.05) return 'Low Threat Level';
    return 'Area is Safe';
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final ThreatAlert alert;
  final VoidCallback? onTap;

  const _AlertTile({required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(alert.severity);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: alert.isRead ? null : severityColor.withOpacity(0.04),
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: severityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _typeIcon(alert.type),
                size: 16,
                color: severityColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: alert.isRead
                                ? FontWeight.normal
                                : FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!alert.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: severityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.description,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(alert.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: severityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                alert.severity.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: severityColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return const Color(0xFFB71C1C);
      case 'high': return Colors.deepOrange;
      case 'medium': return Colors.orange;
      case 'low': return Colors.amber;
      default: return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'incident': return Icons.warning_amber_rounded;
      case 'danger_zone': return Icons.gps_fixed;
      case 'sos_alert': return Icons.notifications_active;
      case 'message_analysis': return Icons.message;
      default: return Icons.notifications;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
