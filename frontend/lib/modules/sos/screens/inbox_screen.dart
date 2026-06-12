import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/sync_manager.dart';
import '../../auth/services/auth_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({Key? key}) : super(key: key);

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoadingMessages = true;
  bool _isLoadingAlerts = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadMessages(), _loadAlerts()]);
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoadingMessages = true);
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      if (userId == null) {
        setState(() {
          _messages = [];
          _isLoadingMessages = false;
        });
        return;
      }

      // Primary: Load messages from local storage (offline-first)
      final storage = OfflineStorageService();
      final localMessages = await storage.getLocalMessages(userId);
      if (localMessages.isNotEmpty) {
        setState(() {
          _messages = localMessages;
          _isLoadingMessages = false;
          _isOffline = false;
        });
        return;
      }

      // Fallback: Try loading from server if local is empty
      try {
        final api = context.read<BackendApi>();
        final result = await api.getMessages(userId);
        final serverMessages = result['messages'] is List
            ? List<Map<String, dynamic>>.from(result['messages'])
            : [];

        // Cache server messages locally
        for (final msg in serverMessages) {
          await storage.saveMessageLocally(msg);
        }

        setState(() {
          _messages = serverMessages;
          _isLoadingMessages = false;
          _isOffline = false;
        });
      } catch (_) {
        setState(() {
          _messages = [];
          _isLoadingMessages = false;
          _isOffline = true;
        });
      }
    } catch (e) {
      debugPrint('InboxScreen: Failed to load messages: $e');
      setState(() {
        _isLoadingMessages = false;
        _isOffline = true;
      });
    }
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoadingAlerts = true);
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      if (userId == null) {
        setState(() {
          _alerts = [];
          _isLoadingAlerts = false;
        });
        return;
      }
      final api = context.read<BackendApi>();
      final result = await api.getUserAlerts(userId);
      setState(() {
        _alerts = result['alerts'] is List
            ? List<Map<String, dynamic>>.from(result['alerts'])
            : [];
        _isLoadingAlerts = false;
        _isOffline = false;
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to load alerts: $e');
      setState(() {
        _isLoadingAlerts = false;
        _isOffline = true;
      });
    }
  }

  /// Mark a message as read locally (no server call).
  Future<void> _markAsRead(String messageId) async {
    try {
      final storage = OfflineStorageService();
      await storage.markMessageReadLocally(messageId);
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == messageId);
        if (idx >= 0) {
          _messages[idx]['read_at'] = DateTime.now().millisecondsSinceEpoch;
        }
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to mark as read locally: $e');
    }
  }

  /// Delete a message from local storage.
  Future<void> _deleteMessage(String messageId) async {
    try {
      final storage = OfflineStorageService();
      await storage.deleteMessage(messageId);
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('InboxScreen: Failed to delete message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    final int ms;
    if (ts is int) {
      ms = ts;
    } else if (ts is String) {
      ms = int.tryParse(ts) ?? 0;
    } else {
      return '';
    }
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Messages', icon: Icon(Icons.message_outlined, size: 20)),
            Tab(
                text: 'Alerts',
                icon: Icon(Icons.warning_amber_outlined, size: 20)),
            Tab(text: 'Updates', icon: Icon(Icons.update_outlined, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MessagesTab(
            messages: _messages,
            isLoading: _isLoadingMessages,
            isOffline: _isOffline,
            onRefresh: _loadMessages,
            onMarkRead: _markAsRead,
            onDelete: _deleteMessage,
            formatTimestamp: _formatTimestamp,
          ),
          _AlertsTab(
            alerts: _alerts,
            isLoading: _isLoadingAlerts,
            isOffline: _isOffline,
            onRefresh: _loadAlerts,
            formatTimestamp: _formatTimestamp,
          ),
          _UpdatesTab(),
        ],
      ),
    );
  }
}

class _MessagesTab extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final bool isOffline;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onMarkRead;
  final Future<void> Function(String) onDelete;
  final String Function(dynamic) formatTimestamp;

  const _MessagesTab({
    required this.messages,
    required this.isLoading,
    required this.isOffline,
    required this.onRefresh,
    required this.onMarkRead,
    required this.onDelete,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: messages.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.message_outlined,
                          size: 48,
                          color: isOffline ? Colors.orange : Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        isOffline ? 'Offline' : 'No messages yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: isOffline ? Colors.orange : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isOffline
                            ? 'Connect to the internet to load messages'
                            : 'Messages from responders and peers will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isRead = msg['read_at'] != null;
                final content = msg['content'] as String? ?? '';
                final senderId = msg['sender_id'] as String? ?? 'Unknown';
                final timestamp = formatTimestamp(msg['created_at']);

                return Dismissible(
                  key: Key(msg['id'] as String),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Message'),
                        content: const Text(
                            'Are you sure you want to delete this message? It will be permanently removed from your device.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => onDelete(msg['id'] as String),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isRead ? Colors.grey[300] : AppTheme.primaryColor,
                      child: Icon(
                        Icons.person,
                        color: isRead ? Colors.grey : Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      senderId,
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        if (timestamp.isNotEmpty)
                          Text(
                            timestamp,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isRead)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.grey[400],
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Message'),
                                content: const Text(
                                    'Are you sure you want to delete this message? It will be permanently removed from your device.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              onDelete(msg['id'] as String);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      if (!isRead) {
                        onMarkRead(msg['id'] as String);
                      }
                      _showMessageDetail(context, msg, formatTimestamp, onDelete);
                    },
                  ),
                );
              },
            ),
    );
  }

  void _showMessageDetail(
      BuildContext context,
      Map<String, dynamic> msg,
      String Function(dynamic) formatTimestamp,
      Future<void> Function(String) onDelete) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg['sender_id'] as String? ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        formatTimestamp(msg['created_at']),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              msg['content'] as String? ?? '',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            if (msg['priority'] != null)
              Chip(
                label: Text(
                  'Priority: ${msg['priority']}',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.orange[100],
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onDelete(msg['id'] as String);
                },
                icon: const Icon(Icons.delete_outlined, color: Colors.red),
                label: const Text('Delete Message',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsTab extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final bool isLoading;
  final bool isOffline;
  final Future<void> Function() onRefresh;
  final String Function(dynamic) formatTimestamp;

  const _AlertsTab({
    required this.alerts,
    required this.isLoading,
    required this.isOffline,
    required this.onRefresh,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: alerts.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 48,
                          color: isOffline ? Colors.orange : Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        isOffline ? 'Offline' : 'No active alerts',
                        style: TextStyle(
                          fontSize: 16,
                          color: isOffline ? Colors.orange : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isOffline
                            ? 'Connect to the internet to load alerts'
                            : 'Emergency alerts and warnings will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final alert = alerts[index];
                final status = alert['status'] as String? ?? 'active';
                final type = alert['type'] as String? ?? 'Alert';
                final isActive = status == 'active';

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  color: isActive ? Colors.red[50] : null,
                  child: ListTile(
                    leading: Icon(
                      isActive
                          ? Icons.warning
                          : Icons.check_circle_outline,
                      color: isActive ? Colors.red : Colors.green,
                      size: 32,
                    ),
                    title: Text(
                      type,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.red[900] : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (alert['description'] != null)
                          Text(
                            alert['description'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? Colors.red[700] : Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.red.withOpacity(0.2)
                                    : Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatTimestamp(alert['created_at']),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => _showAlertDetail(context, alert, formatTimestamp),
                  ),
                );
              },
            ),
    );
  }

  void _showAlertDetail(
      BuildContext context, Map<String, dynamic> alert, String Function(dynamic) formatTimestamp) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  alert['status'] == 'active'
                      ? Icons.warning
                      : Icons.check_circle,
                  color: alert['status'] == 'active' ? Colors.red : Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert['type'] as String? ?? 'Alert',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'Status: ${alert['status'] ?? 'unknown'}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (alert['description'] != null)
              Text(
                alert['description'] as String,
                style: const TextStyle(fontSize: 15),
              ),
            const SizedBox(height: 12),
            Text(
              'Created: ${formatTimestamp(alert['created_at'])}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            if (alert['resolved_at'] != null)
              Text(
                'Resolved: ${formatTimestamp(alert['resolved_at'])}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _UpdatesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final syncManager = context.watch<SyncManager>();

    return RefreshIndicator(
      onRefresh: () => syncManager.triggerSync(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sync status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    syncManager.isOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: syncManager.isOnline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          syncManager.isOnline ? 'Connected' : 'Offline',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          syncManager.isSyncing
                              ? 'Syncing...'
                              : '${syncManager.pendingCount} items pending sync',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (syncManager.pendingCount > 0)
                    TextButton(
                      onPressed: () => syncManager.triggerSync(),
                      child: const Text('Sync Now'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (syncManager.lastSyncTime != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.sync, color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Last sync: ${_formatDateTime(syncManager.lastSyncTime!)}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.update_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No updates available',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'System updates and notifications will appear here',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
