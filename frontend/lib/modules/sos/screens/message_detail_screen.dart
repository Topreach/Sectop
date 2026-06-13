import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../ai/services/distress_detector.dart';

class MessageDetailScreen extends StatefulWidget {
  const MessageDetailScreen({Key? key}) : super(key: key);

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  Map<String, dynamic> _messageData = {};
  bool _isDeleted = false;
  final DistressDetector _detector = DistressDetector();
  DistressResult? _aiResult;
  bool _isAnalyzing = false;


  Future<void> _markAsReadIfUnread() async {
    if (_messageData['read_at'] != null) return;
    try {
      final storage = OfflineStorageService();
      await storage.markMessageReadLocally(_messageData['id'] as String);
      setState(() {
        _messageData['read_at'] = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      debugPrint('MessageDetailScreen: Failed to mark as read: $e');
    }
  }

  Future<void> _analyzeMessageContent() async {
    final content = _messageData['content'] as String? ?? '';
    if (content.isEmpty) return;
    setState(() => _isAnalyzing = true);
    try {
      final result = await _detector.analyzeMessage(content);
      if (mounted) {
        setState(() {
          _aiResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      debugPrint('MessageDetailScreen: AI analysis failed: $e');
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _deleteMessage() async {
    final confirmed = await showDialog<bool>(
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final storage = OfflineStorageService();
        await storage.deleteMessage(_messageData['id'] as String);
        setState(() => _isDeleted = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message deleted')),
          );
          Navigator.of(context).pop(true); // Return true to indicate deletion
        }
      } catch (e) {
        debugPrint('MessageDetailScreen: Failed to delete message: $e');
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
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        setState(() {
          _messageData = args;
        });
        _markAsReadIfUnread();
        _analyzeMessageContent();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Message'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Message deleted',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final content = _messageData['content'] as String? ?? '';
    final senderId = _messageData['sender_id'] as String? ?? 'Unknown';
    final timestamp = _formatTimestamp(_messageData['created_at']);
    final priority = _messageData['priority'] as int? ?? 0;
    final messageType = _messageData['message_type'] as String? ?? 'text';
    final status = _messageData['status'] as String? ?? 'unknown';
    final isRead = _messageData['read_at'] != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteMessage,
            tooltip: 'Delete message',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sender info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    radius: 24,
                    child: const Icon(Icons.person, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timestamp,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Priority badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.getPriorityColor(priority).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.getPriorityColor(priority).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      'P$priority',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getPriorityColor(priority),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Message content
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message_outlined, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 8),
                      Text(
                        messageType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isRead
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isRead ? 'READ' : 'UNREAD',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isRead ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          // AI Analysis Panel
          _buildAiAnalysisPanel(content),
          const SizedBox(height: 24),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleteMessage,
              icon: const Icon(Icons.delete_outlined, color: Colors.red),
              label: const Text(
                'Delete Message',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAnalysisPanel(String content) {
    if (content.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'AI Distress Analysis',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (_isAnalyzing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isAnalyzing)
              const Text(
                'Analyzing message for distress signals...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              )
            else if (_aiResult == null || _aiResult!.label == 'error')
              Text(
                'AI analysis unavailable',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              )
            else ...[
              // Priority indicator
              Row(
                children: [
                  Icon(
                    _aiResult!.priority == 'critical' || _aiResult!.priority == 'high'
                        ? Icons.warning_amber_rounded
                        : _aiResult!.priority == 'medium'
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                    size: 20,
                    color: _aiPriorityColor(_aiResult!.priority),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Priority: ${_aiResult!.priority.toUpperCase()}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _aiPriorityColor(_aiResult!.priority),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(_aiResult!.confidence * 100).toStringAsFixed(0)}% confidence',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Confidence bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _aiResult!.confidence,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _aiPriorityColor(_aiResult!.priority),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),

              // Method
              Text(
                'Method: ${_aiResult!.method}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),

              // Detected signals
              if (_aiResult!.reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Detected Signals:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _aiResult!.reasons.map((reason) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _aiPriorityColor(_aiResult!.priority).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _aiPriorityColor(_aiResult!.priority).withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 11,
                          color: _aiPriorityColor(_aiResult!.priority),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Color _aiPriorityColor(String priority) {
    switch (priority) {
      case 'critical': return Colors.red;
      case 'high': return Colors.orange;
      case 'medium': return Colors.amber.shade700;
      case 'low': return Colors.green;
      default: return Colors.grey;
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
    return DateFormat('MMM dd, yyyy HH:mm').format(dt);
  }
}
