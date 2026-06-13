import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../core/localization.dart';

/// Screen for emergency radio broadcasts.
/// When internet is cut, radio is the only way to reach rural communities.
class RadioBroadcastScreen extends StatefulWidget {
  const RadioBroadcastScreen({Key? key}) : super(key: key);

  @override
  State<RadioBroadcastScreen> createState() => _RadioBroadcastScreenState();
}

class _RadioBroadcastScreenState extends State<RadioBroadcastScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _targetStateController = TextEditingController();
  final _targetLgaController = TextEditingController();
  final _frequencyController = TextEditingController(text: '95.1');
  final BackendApi _api = BackendApi();

  String _severity = 'urgent';
  String _broadcastType = 'emergency';
  String _language = 'en';
  bool _isAnonymous = true;
  bool _isSubmitting = false;

  List<dynamic> _history = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _targetStateController.dispose();
    _targetLgaController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final result = await _api.getRadioBroadcasts();
      setState(() {
        _history = result['data'] as List<dynamic>? ?? [];
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('title_and_message_required'))),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _api.createRadioBroadcast({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'language': _language,
        'severity': _severity,
        'broadcastType': _broadcastType,
        'targetFrequency': double.tryParse(_frequencyController.text),
        'targetState': _targetStateController.text.trim().isEmpty
            ? null : _targetStateController.text.trim(),
        'targetLga': _targetLgaController.text.trim().isEmpty
            ? null : _targetLgaController.text.trim(),
        'anonymous': _isAnonymous,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('radio_broadcast_sent'))),
        );
        _titleController.clear();
        _messageController.clear();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('failed_text')} $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _retryBroadcast(String id) async {
    try {
      await _api.retryRadioBroadcast(id);
      _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('broadcast_retried'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('failed_text')} $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('emergency_radio')),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.brown[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.brown[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.radio, color: Colors.brown[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('radio_description'),
                      style: TextStyle(fontSize: 12, color: Colors.brown[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Create new broadcast
            Text(context.tr('new_broadcast'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: context.tr('title_required'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: context.tr('message_required'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.message),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _severity,
                    decoration: InputDecoration(
                      labelText: context.tr('severity'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'info', child: Text(context.tr('info'))),
                      DropdownMenuItem(value: 'warning', child: Text(context.tr('warning'))),
                      DropdownMenuItem(value: 'urgent', child: Text(context.tr('urgent'))),
                      DropdownMenuItem(value: 'critical', child: Text(context.tr('critical'))),
                    ],
                    onChanged: (v) => setState(() => _severity = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _language,
                    decoration: InputDecoration(
                      labelText: context.tr('language'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'en', child: Text(context.tr('english'))),
                      DropdownMenuItem(value: 'ha', child: Text(context.tr('hausa'))),
                      DropdownMenuItem(value: 'yo', child: Text(context.tr('yoruba'))),
                      DropdownMenuItem(value: 'ig', child: Text(context.tr('igbo'))),
                      DropdownMenuItem(value: 'pcm', child: Text(context.tr('pidgin'))),
                    ],
                    onChanged: (v) => setState(() => _language = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _frequencyController,
              decoration: InputDecoration(
                labelText: context.tr('target_frequency'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.settings_input_antenna),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetStateController,
                    decoration: InputDecoration(
                      labelText: context.tr('target_state'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _targetLgaController,
                    decoration: InputDecoration(
                      labelText: context.tr('target_lga'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              title: Text(context.tr('anonymous_broadcast')),
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
              secondary: Icon(_isAnonymous ? Icons.shield : Icons.person, color: Colors.brown),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.radio),
              label: Text(_isSubmitting ? context.tr('broadcasting') : context.tr('broadcast_over_radio')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 24),

            // History
            Text(context.tr('broadcast_history'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            if (_isLoadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (_history.isEmpty)
              Text(context.tr('no_previous_broadcasts'), style: const TextStyle(color: Colors.grey))
            else
              ...List.generate(_history.length, (index) {
                final b = _history[index] as Map<String, dynamic>;
                final status = (b['status'] as String?) ?? 'unknown';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      status == 'broadcasting' ? Icons.radio : Icons.check_circle,
                      color: status == 'broadcasting' ? Colors.green : Colors.grey,
                    ),
                    title: Text(b['title'] as String? ?? ''),
                    subtitle: Text('${b['language'] ?? 'en'} | ${b['severity'] ?? ''}'),
                    trailing: status == 'failed'
                        ? IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.red),
                            onPressed: () => _retryBroadcast(b['id']),
                          )
                        : Text(status, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
