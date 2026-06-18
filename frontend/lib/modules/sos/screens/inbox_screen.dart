import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/sync_manager.dart';
import '../../auth/services/auth_service.dart';
import '../../ai/services/distress_detector.dart';

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
  List<Map<String, dynamic>> _tips = [];
  bool _isLoadingMessages = true;
  bool _isLoadingAlerts = true;
  bool _isLoadingTips = true;
  bool _isMessagesOffline = false;
  bool _isAlertsOffline = false;
  bool _isTipsOffline = false;

  // WebSocket for real-time message delivery
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _wsReconnectTimer;

  // Compose message state
  final TextEditingController _composeController = TextEditingController();
  bool _isSending = false;
  final List<Map<String, dynamic>> _outgoingMessages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _connectMessageWebSocket();
  }

  @override
  void dispose() {
    _wsReconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _composeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadMessages(), _loadAlerts(), _loadTips()]);
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

      final storage = OfflineStorageService();

      // Primary: Load messages from server (online-first for fast delivery)
      try {
        final api = context.read<BackendApi>();
        final result = await api.getMessages(userId);
        final rawMessages = result['messages'];
        final List<Map<String, dynamic>> serverMessages;
        if (rawMessages is List) {
          serverMessages = rawMessages.cast<Map<String, dynamic>>().toList();
        } else {
          serverMessages = [];
        }

        // Cache server messages locally for offline fallback
        for (final msg in serverMessages) {
          await storage.saveMessageLocally(msg);
        }

        setState(() {
          _messages = serverMessages;
          _isLoadingMessages = false;
          _isMessagesOffline = false;
        });
        return;
      } catch (_) {
        debugPrint('InboxScreen: Server unavailable, trying local storage...');
      }

      // Fallback: Load from local storage when server is unreachable
      final localMessages = await storage.getLocalMessages(userId);
      setState(() {
        _messages = localMessages;
        _isLoadingMessages = false;
        // Only mark offline if we had messages before but can't reach server.
        // If local is empty, the user simply has no messages — don't show "Offline".
        _isMessagesOffline = false;
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to load messages: $e');
      setState(() {
        _isLoadingMessages = false;
        _isMessagesOffline = false;
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

      final storage = OfflineStorageService();

      // Primary: Load alerts from server (online-first)
      try {
        final api = context.read<BackendApi>();
        final result = await api.getUserAlerts(userId);
        final rawAlerts = result['alerts'];
        final List<Map<String, dynamic>> serverAlerts;
        if (rawAlerts is List) {
          serverAlerts = rawAlerts.cast<Map<String, dynamic>>().toList();
        } else {
          serverAlerts = [];
        }

        // Cache server alerts locally for offline fallback
        for (final alert in serverAlerts) {
          await storage.saveAlertLocally(alert);
        }

        setState(() {
          _alerts = serverAlerts;
          _isLoadingAlerts = false;
          _isAlertsOffline = false;
        });
        return;
      } catch (_) {
        debugPrint('InboxScreen: Server unavailable for alerts, trying local storage...');
      }

      // Fallback: Load from local storage when server is unreachable
      final localAlerts = await storage.getLocalAlerts(userId);
      setState(() {
        _alerts = localAlerts;
        _isLoadingAlerts = false;
        // Only mark offline if we had alerts before but can't reach server.
        // If local is empty, the user simply has no alerts — don't show "Offline".
        _isAlertsOffline = false;
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to load alerts: $e');
      setState(() {
        _isLoadingAlerts = false;
        _isAlertsOffline = false;
      });
    }
  }

  /// Load recent actionable/forwarded tips for the Updates tab.
  /// Shows tips that have been reviewed as actionable or forwarded.
  Future<void> _loadTips() async {
    setState(() => _isLoadingTips = true);
    try {
      final api = context.read<BackendApi>();
      final result = await api.getRecentTips();
      // _handleResponse wraps JSON arrays in {'data': [...]}
      final rawTips = result['data'];
      final List<Map<String, dynamic>> serverTips;
      if (rawTips is List) {
        serverTips = rawTips.cast<Map<String, dynamic>>().toList();
      } else {
        serverTips = [];
      }

      setState(() {
        _tips = serverTips;
        _isLoadingTips = false;
        _isTipsOffline = false;
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to load tips: $e');
      setState(() {
        _isLoadingTips = false;
        _isTipsOffline = false;
      });
    }
  }

  /// Connect to WebSocket for real-time message delivery.
  /// Subscribes to the user's personal message queue and urgent topic.
  Future<void> _connectMessageWebSocket() async {
    try {
      final storage = OfflineStorageService();
      final token = await storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return;

      final wsUrl = AppConstants.wsBaseUrl;
      final wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsChannel = wsChannel;
      debugPrint('InboxScreen: Message WebSocket connected');

      _wsSubscription = wsChannel.stream.listen(
        (dynamic data) {
          final body = data is String
              ? data
              : (data is List<int> ? utf8.decode(data) : data.toString());
          _handleIncomingMessage(body);
        },
        onError: (dynamic error) {
          debugPrint('InboxScreen: Message WebSocket error: $error');
          _scheduleMessageWsReconnect();
        },
        onDone: () {
          debugPrint('InboxScreen: Message WebSocket closed');
          _scheduleMessageWsReconnect();
        },
        cancelOnError: false,
      );

      // Send STOMP CONNECT frame with auth token
      _sendMessageStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'localhost',
        'Authorization': 'Bearer $token',
      });

      // Subscribe to personal message queue and urgent topic
      await Future.delayed(const Duration(milliseconds: 500));
      _sendMessageStompFrame('SUBSCRIBE', {
        'id': 'msg-sub-0',
        'destination': '/user/queue/messages',
      });
      _sendMessageStompFrame('SUBSCRIBE', {
        'id': 'msg-sub-1',
        'destination': '/topic/messages/urgent',
      });
    } catch (e) {
      debugPrint('InboxScreen: Message WebSocket connection failed: $e');
      _scheduleMessageWsReconnect();
    }
  }

  /// Send a raw STOMP frame over the message WebSocket.
  void _sendMessageStompFrame(String command, Map<String, String> headers, {String? body}) {
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
      buffer.write('\0');
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('InboxScreen: Failed to send STOMP frame: $e');
    }
  }

  /// Send a message via STOMP SEND frame for instant delivery (faster than HTTP POST).
  /// Falls back to HTTP POST if WebSocket is not connected.
  void _sendMessageViaStomp(Map<String, dynamic> messageData) {
    if (_wsChannel == null) {
      debugPrint('InboxScreen: WebSocket not connected, falling back to HTTP POST');
      _sendMessageViaHttp(messageData);
      return;
    }
    try {
      final body = json.encode(messageData);
      _sendMessageStompFrame('SEND', {
        'destination': '/app/messages/send',
        'content-type': 'application/json',
      }, body: body);
      debugPrint('InboxScreen: Message sent via STOMP SEND: ${messageData['id']}');
    } catch (e) {
      debugPrint('InboxScreen: STOMP SEND failed, falling back to HTTP POST: $e');
      _sendMessageViaHttp(messageData);
    }
  }

  /// Send a message via HTTP POST (fallback when WebSocket is unavailable).
  Future<void> _sendMessageViaHttp(Map<String, dynamic> messageData) async {
    try {
      final api = context.read<BackendApi>();
      await api.sendMessage(messageData);
      debugPrint('InboxScreen: Message sent via HTTP: ${messageData['id']}');
    } catch (e) {
      debugPrint('InboxScreen: HTTP send failed: $e');
    }
  }

  /// Compose and send a message with optimistic UI update.
  ///
  /// This method is designed for MAXIMUM SPEED:
  /// 1. Shows the message in the list IMMEDIATELY (optimistic UI)
  /// 2. Sends via STOMP SEND over existing WebSocket (fire-and-forget, ~1ms)
  /// 3. Fires HTTP POST in the background (does NOT await it)
  /// 4. Updates status to 'sent' immediately — no waiting for server round-trip
  Future<void> _sendComposedMessage() async {
    final text = _composeController.text.trim();
    if (text.isEmpty || _isSending) return;

    final authService = context.read<AuthService>();
    final userId = authService.currentUser?.id;
    if (userId == null) return;

    // Generate a temporary ID for optimistic UI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Create optimistic message entry — appears instantly in the list
    final optimisticMessage = <String, dynamic>{
      'id': tempId,
      'sender_id': userId,
      'content': text,
      'message_type': 'text',
      'priority': 0,
      'status': 'sending',
      'created_at': now,
      '_optimistic': true,
    };

    // Add to messages list immediately (optimistic UI) and clear input
    setState(() {
      _messages.insert(0, optimisticMessage);
      _outgoingMessages.add(optimisticMessage);
      _composeController.clear();
    });

    // Build the actual message payload
    final messageData = <String, dynamic>{
      'id': tempId,
      'sender_id': userId,
      'content': text,
      'message_type': 'text',
      'priority': 0,
    };

    // STEP 1: Send via STOMP SEND over existing WebSocket (FASTEST PATH — ~1ms)
    // This is fire-and-forget; the backend pushes directly to the receiver's queue
    _sendMessageViaStomp(messageData);

    // STEP 2: Update UI to 'sent' IMMEDIATELY — no waiting for HTTP round-trip
    // The message will appear as 'sent' on both sender and receiver screens
    // within milliseconds via the WebSocket path
    setState(() {
      final idx = _messages.indexWhere((m) => m['id'] == tempId);
      if (idx >= 0) {
        _messages[idx]['status'] = 'sent';
        _messages[idx].remove('_optimistic');
      }
      _outgoingMessages.removeWhere((m) => m['id'] == tempId);
      _isSending = false;
    });

    // STEP 3: Fire HTTP POST in the background (DO NOT AWAIT)
    // This ensures delivery even if WebSocket message is lost.
    // The backend deduplicates by message ID, so this is safe.
    unawaited(_sendMessageViaHttp(messageData));
  }

  /// Handle incoming real-time message from WebSocket.
  void _handleIncomingMessage(String body) {
    if (body.isEmpty) return;
    try {
      // Parse STOMP frame to extract JSON body
      String jsonStr = body;
      if (body.contains('\n\n')) {
        jsonStr = body.substring(body.indexOf('\n\n') + 2).trim();
      }
      jsonStr = jsonStr.replaceAll('\0', '').trim();
      if (jsonStr.isEmpty) return;

      final data = json.decode(jsonStr) as Map<String, dynamic>;

      // Check if it's a message (has 'content' field) or alert
      if (data.containsKey('content') || data.containsKey('sender_id')) {
        // It's a message - add to messages list
        final storage = OfflineStorageService();
        storage.saveMessageLocally(data);
        if (mounted) {
          setState(() {
            // Avoid duplicates
            _messages.removeWhere((m) => m['id'] == data['id']);
            _messages.insert(0, data);
          });
        }
        debugPrint('InboxScreen: Real-time message received: ${data['id']}');
      }
    } catch (e) {
      debugPrint('InboxScreen: Failed to parse incoming message: $e');
    }
  }

  /// Schedule WebSocket reconnection with exponential backoff.
  void _scheduleMessageWsReconnect() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('InboxScreen: Attempting message WebSocket reconnect...');
      _connectMessageWebSocket();
    });
  }

  /// Mark a message as read (online-first: notify server, then update locally).
  Future<void> _markAsRead(String messageId) async {
    try {
      // Primary: Notify server first (online-first)
      try {
        final api = context.read<BackendApi>();
        await api.markMessageRead(messageId);
        debugPrint('InboxScreen: Message $messageId marked read on server');
      } catch (_) {
        debugPrint('InboxScreen: Server mark-read failed (no internet)');
      }

      // Update local storage
      final storage = OfflineStorageService();
      await storage.markMessageReadLocally(messageId);
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == messageId);
        if (idx >= 0) {
          _messages[idx]['read_at'] = DateTime.now().millisecondsSinceEpoch;
        }
      });
    } catch (e) {
      debugPrint('InboxScreen: Failed to mark as read: $e');
    }
  }

  /// Delete a message (online-first: notify server, then delete locally).
  Future<void> _deleteMessage(String messageId) async {
    try {
      // Primary: Notify server first (online-first)
      try {
        final api = context.read<BackendApi>();
        await api.delete('/messages/$messageId');
        debugPrint('InboxScreen: Message $messageId deleted on server');
      } catch (_) {
        debugPrint('InboxScreen: Server delete failed (no internet)');
      }

      // Delete from local storage
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
        title: Text('Inbox'),
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
      body: Column(
        children: [
          // Messages/Alerts/Updates tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MessagesTab(
                  messages: _messages,
                  isLoading: _isLoadingMessages,
                  isOffline: _isMessagesOffline,
                  onRefresh: _loadMessages,
                  onMarkRead: _markAsRead,
                  onDelete: _deleteMessage,
                  formatTimestamp: _formatTimestamp,
                ),
                _AlertsTab(
                  alerts: _alerts,
                  isLoading: _isLoadingAlerts,
                  isOffline: _isAlertsOffline,
                  onRefresh: _loadAlerts,
                  formatTimestamp: _formatTimestamp,
                ),
                _UpdatesTab(
                  tips: _tips,
                  isLoading: _isLoadingTips,
                  isOffline: _isTipsOffline,
                  onRefresh: _loadTips,
                  formatTimestamp: _formatTimestamp,
                ),
              ],
            ),
          ),
          // Compose bar — only show on Messages tab
          _buildComposeBar(),
        ],
      ),
    );
  }

  /// Build the compose message bar at the bottom of the screen.
  /// Provides a text field and send button for instant message sending.
  Widget _buildComposeBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Text input field
              Expanded(
                child: TextField(
                  controller: _composeController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppTheme.primaryColor),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendComposedMessage(),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              Material(
                color: _isSending ? Colors.grey[400] : AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _isSending ? null : _sendComposedMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesTab extends StatefulWidget {
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
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  /// Cache of AI analysis results keyed by message content hash.
  final Map<String, DistressResult> _aiAnalysisCache = {};
  final DistressDetector _detector = DistressDetector();

  /// Get priority label and color from a message's priority field.
  String _priorityLabel(dynamic priority) {
    if (priority == null) return 'unknown';
    if (priority is int) {
      switch (priority) {
        case 0: return 'low';
        case 1: return 'medium';
        case 2: return 'high';
        case 3: return 'critical';
      }
    }
    if (priority is String) return priority;
    return 'unknown';
  }

  Color _priorityColor(String label) {
    switch (label) {
      case 'critical': return Colors.red;
      case 'high': return Colors.orange;
      case 'medium': return Colors.amber;
      case 'low': return Colors.green;
      default: return Colors.grey;
    }
  }

  Color _priorityBgColor(String label) {
    switch (label) {
      case 'critical': return Colors.red.shade50;
      case 'high': return Colors.orange.shade50;
      case 'medium': return Colors.amber.shade50;
      case 'low': return Colors.green.shade50;
      default: return Colors.grey.shade50;
    }
  }

  IconData _priorityIcon(String label) {
    switch (label) {
      case 'critical': return Icons.warning;
      case 'high': return Icons.warning_amber_rounded;
      case 'medium': return Icons.info_outline;
      case 'low': return Icons.check_circle_outline;
      default: return Icons.help_outline;
    }
  }

  /// Run AI analysis on a message content and cache the result.
  Future<DistressResult?> _analyzeMessage(Map<String, dynamic> msg) async {
    final content = msg['content'] as String? ?? '';
    if (content.isEmpty) return null;

    // Use content hash as cache key
    final cacheKey = content.hashCode.toString();
    if (_aiAnalysisCache.containsKey(cacheKey)) {
      return _aiAnalysisCache[cacheKey];
    }

    try {
      final result = await _detector.analyzeMessage(content);
      _aiAnalysisCache[cacheKey] = result;
      if (mounted) setState(() {});
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: widget.messages.isEmpty
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
                          color: widget.isOffline ? Colors.orange : Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        widget.isOffline ? 'Offline' : 'No messages yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.isOffline ? Colors.orange : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isOffline
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
              itemCount: widget.messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final msg = widget.messages[index];
                final isRead = msg['read_at'] != null;
                final content = msg['content'] as String? ?? '';
                final senderId = msg['sender_id'] as String? ?? 'Unknown';
                final timestamp = widget.formatTimestamp(msg['created_at']);

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
                        title: Text('Delete Message'),
                        content: const Text(
                            'Are you sure you want to delete this message? It will be permanently removed from your device.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => widget.onDelete(msg['id'] as String),
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
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderId,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // AI Priority Badge
                        _buildPriorityBadge(msg),
                      ],
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
                                title: Text('Delete Message'),
                                content: const Text(
                                    'Are you sure you want to delete this message? It will be permanently removed from your device.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              widget.onDelete(msg['id'] as String);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      if (!isRead) {
                        widget.onMarkRead(msg['id'] as String);
                      }
                      _showMessageDetail(context, msg, widget.formatTimestamp, widget.onDelete);
                    },
                  ),
                );
              },
            ),
    );
  }

  /// Build a small priority badge for the message list item.
  Widget _buildPriorityBadge(Map<String, dynamic> msg) {
    final priority = msg['priority'];
    final label = _priorityLabel(priority);
    final color = _priorityColor(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_priorityIcon(label), size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageDetail(
      BuildContext context,
      Map<String, dynamic> msg,
      String Function(dynamic) formatTimestamp,
      Future<void> Function(String) onDelete) {
    final content = msg['content'] as String? ?? '';
    final priority = msg['priority'];
    final label = _priorityLabel(priority);
    final color = _priorityColor(label);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              // Sender info
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

              // Message content
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  content,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),

              // AI Analysis Panel
              _buildAiAnalysisPanel(content, label, color),
              const SizedBox(height: 16),

              // Delete button
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
      ),
    );
  }

  /// Build the AI analysis panel showing distress detection results.
  Widget _buildAiAnalysisPanel(String content, String priorityLabel, Color priorityColor) {
    return FutureBuilder<DistressResult?>(
      future: _analyzeMessage({ 'content': content }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text('AI analyzing message...', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
          );
        }

        final result = snapshot.data;
        if (result == null || result.label == 'error') {
          return const SizedBox.shrink();
        }

        final reasons = result.reasons;
        final aiPriorityColor = _priorityColor(result.priority);
        final aiPriorityBg = _priorityBgColor(result.priority);

        return Card(
          elevation: 0,
          color: aiPriorityBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: aiPriorityColor.withOpacity(0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(_priorityIcon(result.priority), size: 18, color: aiPriorityColor),
                    const SizedBox(width: 8),
                    Text(
                      'AI Distress Analysis',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: aiPriorityColor,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: aiPriorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        result.priority.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: aiPriorityColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Confidence bar
                Row(
                  children: [
                    Text('Confidence: ', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: result.confidence,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(aiPriorityColor),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(result.confidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: aiPriorityColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Method
                Text(
                  'Method: ${result.method.replaceAll('_', ' ')}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),

                // Detected reasons
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Detected Signals:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: reasons.map((reason) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: aiPriorityColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          reason.replaceAll('_', ' '),
                          style: TextStyle(fontSize: 10, color: aiPriorityColor),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
  final List<Map<String, dynamic>> tips;
  final bool isLoading;
  final bool isOffline;
  final Future<void> Function() onRefresh;
  final String Function(dynamic) formatTimestamp;

  const _UpdatesTab({
    required this.tips,
    required this.isLoading,
    required this.isOffline,
    required this.onRefresh,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final syncManager = context.watch<SyncManager>();

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([syncManager.triggerSync(), onRefresh()]);
      },
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
          // Tip-Offs / Intelligence Updates section
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (tips.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.tips_and_updates, size: 20, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Intelligence Updates',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...tips.map((tip) => _TipCard(
                  tip: tip,
                  formatTimestamp: formatTimestamp,
                )),
            const SizedBox(height: 16),
          ],
          // Empty state when no tips and not loading
          if (!isLoading && tips.isEmpty)
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

/// A card widget that displays a single tip-off / intelligence update.
class _TipCard extends StatelessWidget {
  final Map<String, dynamic> tip;
  final String Function(dynamic) formatTimestamp;

  const _TipCard({
    required this.tip,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final tipType = tip['tipType'] ?? 'other';
    final description = tip['description'] as String? ?? 'No description';
    final threatScore = tip['threatScore'] as int? ?? 0;
    final status = tip['status'] as String? ?? 'pending';
    final createdAt = tip['createdAt'];

    // Determine icon and color based on tip type
    IconData typeIcon;
    Color typeColor;
    switch (tipType.toString()) {
      case 'planned_attack':
        typeIcon = Icons.groups;
        typeColor = Colors.red;
        break;
      case 'suspicious_person':
        typeIcon = Icons.person_search;
        typeColor = Colors.orange;
        break;
      case 'suspicious_vehicle':
        typeIcon = Icons.directions_car;
        typeColor = Colors.amber;
        break;
      case 'hidden_weapons':
        typeIcon = Icons.gavel;
        typeColor = Colors.deepOrange;
        break;
      case 'kidnapping_plot':
        typeIcon = Icons.people_outline;
        typeColor = Colors.red;
        break;
      case 'bombing_plot':
        typeIcon = Icons.warning;
        typeColor = Colors.deepPurple;
        break;
      default:
        typeIcon = Icons.info_outline;
        typeColor = Colors.blue;
    }

    // Threat score color
    Color scoreColor;
    if (threatScore >= 70) {
      scoreColor = Colors.red;
    } else if (threatScore >= 40) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(typeIcon, size: 20, color: typeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tipType.toString().replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: typeColor,
                    ),
                  ),
                ),
                // Threat score badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Score: $threatScore',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: _statusColor(status)),
                const SizedBox(width: 4),
                Text(
                  status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    formatTimestamp(createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'actionable':
        return Colors.red;
      case 'forwarded':
        return Colors.blue;
      case 'under_review':
        return Colors.orange;
      case 'dismissed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
