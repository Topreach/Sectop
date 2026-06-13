import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';

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
        SnackBar(content: Text('Title and message are required')),
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
          SnackBar(content: Text('Radio broadcast sent!')),
        );
        _titleController.clear();
        _messageController.clear();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Failed:'} $e')),
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
          SnackBar(content: Text('Broadcast retried')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Failed:'} $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency Radio'),
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
                      'Radio reaches communities when internet is cut. Messages are converted to speech and broadcast over FM.',
                      style: TextStyle(fontSize: 12, color: Colors.brown[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Create new broadcast
            Text('New Broadcast', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title *',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: 'Message *',
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
                      labelText: 'Severity',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'info', child: Text('Info')),
                      DropdownMenuItem(value: 'warning', child: Text('Warning')),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                      DropdownMenuItem(value: 'critical', child: Text('Critical')),
                    ],
                    onChanged: (v) => setState(() => _severity = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _language,
                    decoration: InputDecoration(
                      labelText: 'Language',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ha', child: Text('Hausa')),
                      DropdownMenuItem(value: 'yo', child: Text('Yorùbá')),
                      DropdownMenuItem(value: 'ig', child: Text('Igbo')),
                      DropdownMenuItem(value: 'pcm', child: Text('Pidgin')),
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
                labelText: 'Target Frequency (MHz)',
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
                      labelText: 'Target State',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _targetLgaController,
                    decoration: InputDecoration(
                      labelText: 'Target LGA',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              title: Text('Anonymous Broadcast'),
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
              label: Text(_isSubmitting ? 'Broadcasting...' : 'Broadcast Over Radio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 24),

            // History
            Text('Broadcast History', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            if (_isLoadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (_history.isEmpty)
              Text('No previous broadcasts', style: const TextStyle(color: Colors.grey))
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
