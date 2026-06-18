import 'package:flutter/material.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../auth/services/auth_service.dart';

/// Screen to view active broadcasts/alerts.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({Key? key}) : super(key: key);

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final BackendApi _api = BackendApi();
  final AuthService _authService = AuthService();
  final OfflineStorageService _storage = OfflineStorageService();
  List<dynamic> _broadcasts = [];
  bool _isLoading = true;
  String? _error;
  bool _isOfflineData = false;

  bool get _canCreateBroadcast {
    final user = _authService.currentUser;
    return user != null && user.role == 'coordinator';
  }

  @override
  void initState() {
    super.initState();
    _loadBroadcasts();
  }

  Future<void> _loadBroadcasts() async {
    setState(() => _isLoading = true);
    try {
      final result = await _api.getActiveBroadcasts();
      setState(() {
        _broadcasts = result['data'] as List<dynamic>? ?? [];
        _isLoading = false;
        _error = null;
        _isOfflineData = false;
      });
    } catch (e) {
      final errorStr = e.toString();
      // Treat 401/403 as "not authenticated" — show empty state instead of error
      if (errorStr.contains('401') || errorStr.contains('403') || errorStr.contains('Unauthorized') || errorStr.contains('Forbidden')) {
        setState(() {
          _broadcasts = [];
          _isLoading = false;
          _error = null;
          _isOfflineData = false;
        });
      } else {
        // Offline fallback — try loading from local cache
        try {
          final cached = await _storage.query('messages',
            where: 'message_type = ?',
            whereArgs: ['broadcast'],
            orderBy: 'created_at DESC',
          );
          if (mounted) {
            setState(() {
              _broadcasts = cached.map((m) => {
                'id': m['id'],
                'title': m['content']?.toString().split(':').first ?? 'Broadcast',
                'message': m['content']?.toString().contains(':') == true
                    ? m['content'].toString().split(':').sublist(1).join(':').trim()
                    : m['content']?.toString() ?? '',
                'severity': m['priority'] != null && (m['priority'] as int) >= 3 ? 'critical'
                    : (m['priority'] as int?) == 2 ? 'urgent'
                    : (m['priority'] as int?) == 1 ? 'warning' : 'info',
                'broadcastType': m['message_type']?.toString() ?? 'broadcast',
                'createdAt': m['created_at'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int).toIso8601String()
                    : DateTime.now().toIso8601String(),
              }).toList();
              _isLoading = false;
              _error = null;
              _isOfflineData = true;
            });
          }
        } catch (cacheError) {
          debugPrint('BroadcastScreen: Cache fallback failed: $cacheError');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _error = 'Failed to load broadcasts: $e';
              _isOfflineData = false;
            });
          }
        }
      }
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return Colors.red;
      case 'urgent': return Colors.orange;
      case 'warning': return Colors.amber;
      case 'info': return Colors.blue;
      default: return Colors.grey;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical': return Icons.gpp_bad;
      case 'urgent': return Icons.warning;
      case 'warning': return Icons.error_outline;
      case 'info': return Icons.info_outline;
      default: return Icons.campaign;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mass Broadcasts'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_canCreateBroadcast)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.createBroadcast),
              tooltip: 'Create Broadcast',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBroadcasts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBroadcasts,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _broadcasts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No active broadcasts', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_isOfflineData)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.orange.withOpacity(0.1),
                            child: Row(
                              children: [
                                Icon(Icons.wifi_off, size: 16, color: Colors.orange[700]),
                                const SizedBox(width: 8),
                                Text(
                                  'Showing cached broadcasts — offline',
                                  style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadBroadcasts,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _broadcasts.length,
                              itemBuilder: (context, index) {
                                final b = _broadcasts[index] as Map<String, dynamic>;
                                final severity = (b['severity'] as String?) ?? 'info';
                                final color = _severityColor(severity);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: color.withOpacity(0.3)),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {},
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(_severityIcon(severity), color: color, size: 20),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: color.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  severity.toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: color,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              if (b['broadcastType'] != null)
                                                Text(
                                                  (b['broadcastType'] as String).replaceAll('_', ' '),
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            b['title'] as String? ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            b['message'] as String? ?? '',
                                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              if (b['targetState'] != null)
                                                Text(
                                                  '📍 ${b['targetState']}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                                ),
                                              if (b['targetLga'] != null)
                                                Text(
                                                  ' / ${b['targetLga']}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                                ),
                                              const Spacer(),
                                              if (b['createdAt'] != null)
                                                Text(
                                                  (b['createdAt'] as String).substring(0, 10),
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
