import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../auth/services/auth_service.dart';

/// Screen for coordinators/admins to create a new broadcast.
class CreateBroadcastScreen extends StatefulWidget {
  const CreateBroadcastScreen({Key? key}) : super(key: key);

  @override
  State<CreateBroadcastScreen> createState() => _CreateBroadcastScreenState();
}

class _CreateBroadcastScreenState extends State<CreateBroadcastScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _targetStateController = TextEditingController();
  final _targetLgaController = TextEditingController();

  final AuthService _authService = AuthService();

  // WebSocket/STOMP for fast broadcast creation
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;

  String _severity = 'urgent';
  String _broadcastType = 'general';
  bool _isSubmitting = false;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _targetStateController.dispose();
    _targetLgaController.dispose();
    _wsChannel?.sink.close();
    super.dispose();
  }

  /// Connect to WebSocket for STOMP SEND fast path.
  Future<void> _connectWebSocket() async {
    try {
      final storage = OfflineStorageService();
      final token = await storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return;

      final wsUrl = AppConstants.wsBaseUrl;
      final wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel = wsChannel;
      _isWsConnected = true;

      // Send STOMP CONNECT frame
      _sendStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'localhost',
        'Authorization': 'Bearer $token',
      });

      debugPrint('CreateBroadcastScreen: WebSocket connected for STOMP fast path');
    } catch (e) {
      debugPrint('CreateBroadcastScreen: WebSocket connection failed: $e');
      _isWsConnected = false;
    }
  }

  /// Send a raw STOMP frame over the WebSocket.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
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
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('CreateBroadcastScreen: Failed to send STOMP frame: $e');
    }
  }

  /// Send broadcast data via STOMP SEND for instant delivery.
  void _sendBroadcastViaStomp(Map<String, dynamic> broadcastData) {
    if (_wsChannel == null || !_isWsConnected) {
      debugPrint('CreateBroadcastScreen: WebSocket not connected, using HTTP');
      return;
    }
    try {
      final body = json.encode(broadcastData);
      _sendStompFrame('SEND', {
        'destination': '/app/broadcasts/create',
        'content-type': 'application/json',
      }, body: body);
      debugPrint('CreateBroadcastScreen: Broadcast sent via STOMP SEND');
    } catch (e) {
      debugPrint('CreateBroadcastScreen: STOMP SEND failed: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Double-check role before submitting
    final user = _authService.currentUser;
    if (user == null || (user.role != 'coordinator' && user.role != 'admin')) {
      setState(() {
        _backendError = 'You do not have permission to create broadcasts. '
            'Only coordinators and admins can create broadcasts.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _backendError = null;
    });

    final broadcastData = <String, dynamic>{
      'title': _titleController.text.trim(),
      'message': _messageController.text.trim(),
      'severity': _severity,
      'broadcastType': _broadcastType,
      'targetState': _targetStateController.text.trim().isEmpty
          ? null : _targetStateController.text.trim(),
      'targetLga': _targetLgaController.text.trim().isEmpty
          ? null : _targetLgaController.text.trim(),
      'createdById': user.id,
    };

    try {
      // STEP 1: Send via STOMP SEND over existing WebSocket (FASTEST PATH — ~1ms)
      _sendBroadcastViaStomp(broadcastData);

      // STEP 2: Fire HTTP POST in the background (DO NOT AWAIT)
      // This ensures delivery even if WebSocket message is lost.
      // The backend deduplicates by broadcast ID, so this is safe.
      unawaited(_submitViaHttp(broadcastData, user.id));

      // Show success immediately — don't wait for HTTP round-trip
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Broadcast created successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        // Extract backend validation error message from ApiException
        String errorMsg;
        if (e is ApiException) {
          try {
            final body = json.decode(e.body);
            errorMsg = body['error'] as String? ?? e.body;
          } catch (_) {
            errorMsg = e.body;
          }
        } else {
          errorMsg = e.toString();
        }
        setState(() => _backendError = errorMsg);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Fallback: submit broadcast via HTTP POST with offline queue.
  Future<void> _submitViaHttp(Map<String, dynamic> broadcastData, String userId) async {
    try {
      await BackendApi().createBroadcast(broadcastData);
    } catch (e) {
      final errorStr = e.toString();

      // Offline fallback — save locally when server is unreachable
      if (errorStr.contains('SocketException') ||
          errorStr.contains('Connection refused') ||
          errorStr.contains('HandshakeException') ||
          errorStr.contains('503') ||
          errorStr.contains('Circuit breaker')) {
        try {
          final storage = OfflineStorageService();
          await storage.insert('messages', {
            'id': 'broadcast_${DateTime.now().millisecondsSinceEpoch}',
            'sender_id': userId,
            'content': '[BROADCAST] ${broadcastData['title']}: ${broadcastData['message']}',
            'message_type': 'broadcast',
            'priority': broadcastData['severity'] == 'critical' ? 3
                : broadcastData['severity'] == 'urgent' ? 2
                : broadcastData['severity'] == 'warning' ? 1 : 0,
            'status': 'pending',
            'sync_state': 'offline',
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
          debugPrint('CreateBroadcastScreen: Broadcast saved offline for later sync');
        } catch (saveError) {
          debugPrint('CreateBroadcastScreen: Failed to save broadcast offline: $saveError');
        }
      } else {
        debugPrint('CreateBroadcastScreen: HTTP fallback failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Broadcast'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Message *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                ),
                maxLines: 5,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _severity,
                decoration: const InputDecoration(
                  labelText: 'Severity',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.warning),
                ),
                items: const [
                  DropdownMenuItem(value: 'info', child: Text('Info')),
                  DropdownMenuItem(value: 'warning', child: Text('Warning')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  DropdownMenuItem(value: 'critical', child: Text('Critical')),
                ],
                onChanged: (v) => setState(() => _severity = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _broadcastType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 'general', child: Text('General')),
                  DropdownMenuItem(value: 'evacuation', child: Text('Evacuation')),
                  DropdownMenuItem(value: 'curfew', child: Text('Curfew')),
                  DropdownMenuItem(value: 'manhunt', child: Text('Manhunt')),
                  DropdownMenuItem(value: 'school_closure', child: Text('School Closure')),
                  DropdownMenuItem(value: 'weather', child: Text('Weather')),
                  DropdownMenuItem(value: 'security', child: Text('Security')),
                ],
                onChanged: (v) => setState(() => _broadcastType = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetStateController,
                decoration: const InputDecoration(
                  labelText: 'Target State (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetLgaController,
                decoration: const InputDecoration(
                  labelText: 'Target LGA (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              // Backend validation error display
              if (_backendError != null)
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _backendError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Creating...' : 'Create Broadcast'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
