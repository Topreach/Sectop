import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../core/themes.dart';
import '../../../core/routes.dart';

/// Model for a community notification event.
class CommunityNotification {
  final String id;
  final String type; // 'like', 'comment', 'favorite', 'share', 'new_post'
  final String message;
  final String? postId;
  final String? actorName;
  final DateTime timestamp;
  bool read;

  CommunityNotification({
    required this.id,
    required this.type,
    required this.message,
    this.postId,
    this.actorName,
    required this.timestamp,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'message': message,
        'postId': postId,
        'actorName': actorName,
        'timestamp': timestamp.toIso8601String(),
        'read': read,
      };

  factory CommunityNotification.fromJson(Map<String, dynamic> json) =>
      CommunityNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        message: json['message'] as String,
        postId: json['postId'] as String?,
        actorName: json['actorName'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        read: json['read'] as bool? ?? false,
      );

  IconData get icon {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'favorite':
        return Icons.bookmark;
      case 'share':
        return Icons.share;
      case 'new_post':
        return Icons.camera_alt;
      default:
        return Icons.notifications;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return Colors.blue;
      case 'favorite':
        return Colors.amber;
      case 'share':
        return Colors.green;
      case 'new_post':
        return AppTheme.primaryColor;
      default:
        return Colors.grey;
    }
  }
}

/// Manages community notifications with local persistence.
class CommunityNotificationService {
  static const String _storageKey = 'community_notifications';
  static CommunityNotificationService? _instance;
  List<CommunityNotification> _notifications = [];
  int _unreadCount = 0;

  CommunityNotificationService._();

  static CommunityNotificationService get instance {
    _instance ??= CommunityNotificationService._();
    return _instance!;
  }

  List<CommunityNotification> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadCount => _unreadCount;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      final list = jsonDecode(stored) as List;
      _notifications =
          list.map((e) => CommunityNotification.fromJson(e as Map<String, dynamic>)).toList();
      _unreadCount = _notifications.where((n) => !n.read).length;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_notifications.map((n) => n.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  Future<void> addNotification(CommunityNotification notification) async {
    _notifications.insert(0, notification);
    _unreadCount++;
    await _save();
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx >= 0 && !_notifications[idx].read) {
      _notifications[idx].read = true;
      _unreadCount = (_unreadCount - 1).clamp(0, _notifications.length);
      await _save();
    }
  }

  Future<void> markAllAsRead() async {
    for (final n in _notifications) {
      n.read = true;
    }
    _unreadCount = 0;
    await _save();
  }

  Future<void> clearAll() async {
    _notifications.clear();
    _unreadCount = 0;
    await _save();
  }
}

/// Screen showing community notifications with actionable items.
class CommunityNotificationsScreen extends StatefulWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  State<CommunityNotificationsScreen> createState() =>
      _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState
    extends State<CommunityNotificationsScreen> {
  final CommunityNotificationService _service =
      CommunityNotificationService.instance;
  List<CommunityNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.load();
    setState(() {
      _notifications = _service.notifications;
      _isLoading = false;
    });
  }

  Future<void> _markAllRead() async {
    await _service.markAllAsRead();
    setState(() {});
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.clearAll();
      setState(() => _notifications = []);
    }
  }

  void _onTapNotification(CommunityNotification notification) async {
    await _service.markAsRead(notification.id);
    setState(() {});
    if (notification.postId != null) {
      Navigator.pushNamed(
        context,
        AppRoutes.communityPostDetail,
        arguments: notification.postId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.any((n) => !n.read))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When someone likes, comments, or shares your posts,\n'
                          'you\'ll see it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    return _NotificationTile(
                      notification: notification,
                      onTap: () => _onTapNotification(notification),
                    );
                  },
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final CommunityNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(notification.timestamp);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: notification.iconColor.withOpacity(0.15),
        child: Icon(notification.icon,
            color: notification.iconColor, size: 20),
      ),
      title: Text(
        notification.message,
        style: TextStyle(
          fontWeight: notification.read ? FontWeight.normal : FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        timeStr,
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      trailing: notification.read
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
            ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}
