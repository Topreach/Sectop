import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';

/// Screen to submit an anonymous tip-off / intelligence report.
class TipOffScreen extends StatefulWidget {
  const TipOffScreen({Key? key}) : super(key: key);

  @override
  State<TipOffScreen> createState() => _TipOffScreenState();
}

class _TipOffScreenState extends State<TipOffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _suspectController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  String _tipType = 'suspicious_person';
  bool _isAnonymous = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _targetController.dispose();
    _suspectController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await BackendApi().submitTip({
        'tipType': _tipType,
        'description': _descriptionController.text.trim(),
        'targetDescription': _targetController.text.trim().isEmpty
            ? null : _targetController.text.trim(),
        'suspectDescription': _suspectController.text.trim().isEmpty
            ? null : _suspectController.text.trim(),
        'latitude': double.tryParse(_latController.text),
        'longitude': double.tryParse(_lngController.text),
        'anonymous': _isAnonymous,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tip submitted anonymously. Thank you.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit tip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Tip-Off'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).pushNamed('/tip-review'),
            tooltip: 'Review Tips',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Anonymous notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield, color: Colors.indigo[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your identity is protected. Anonymous tips help keep communities safe.',
                        style: TextStyle(fontSize: 12, color: Colors.indigo[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _tipType,
                decoration: const InputDecoration(
                  labelText: 'Tip Type *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 'suspicious_person', child: Text('Suspicious Person')),
                  DropdownMenuItem(value: 'suspicious_vehicle', child: Text('Suspicious Vehicle')),
                  DropdownMenuItem(value: 'planned_attack', child: Text('Planned Attack')),
                  DropdownMenuItem(value: 'hidden_weapons', child: Text('Hidden Weapons')),
                  DropdownMenuItem(value: 'kidnapping_plot', child: Text('Kidnapping Plot')),
                  DropdownMenuItem(value: 'bombing_plot', child: Text('Bombing Plot')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _tipType = v!),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 5,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(
                  labelText: 'Target Description (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_search),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _suspectController,
                decoration: const InputDecoration(
                  labelText: 'Suspect Description (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.face),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              const Text('Location (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                        hintText: '9.0765',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                        hintText: '7.3986',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('Submit Anonymously'),
                subtitle: const Text('Your identity will not be shared'),
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                secondary: Icon(
                  _isAnonymous ? Icons.shield : Icons.person,
                  color: _isAnonymous ? Colors.indigo : Colors.grey,
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
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Tip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
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
