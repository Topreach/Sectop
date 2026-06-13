import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../core/localization.dart';

/// Screen for coordinators/responders to review tip-offs.
class TipReviewScreen extends StatefulWidget {
  const TipReviewScreen({Key? key}) : super(key: key);

  @override
  State<TipReviewScreen> createState() => _TipReviewScreenState();
}

class _TipReviewScreenState extends State<TipReviewScreen> {
  final BackendApi _api = BackendApi();
  List<dynamic> _tips = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTips();
  }

  Future<void> _loadTips() async {
    setState(() => _isLoading = true);
    try {
      final result = await _api.getPendingTips();
      setState(() {
        _tips = result['data'] as List<dynamic>? ?? [];
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load tips: $e';
      });
    }
  }

  Future<void> _reviewTip(String id, String status) async {
    try {
      await _api.reviewTip(id, {
        'reviewerId': 'coordinator',
        'status': status,
        'notes': 'Reviewed via mobile app',
      });
      _loadTips();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tip $status')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Color _threatColor(int score) {
    if (score >= 70) return Colors.red;
    if (score >= 40) return Colors.orange;
    if (score >= 20) return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Tip-Offs'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTips,
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
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadTips, child: Text(context.tr('retry'))),
                    ],
                  ),
                )
              : _tips.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                          SizedBox(height: 16),
                          Text('No pending tips', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTips,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tips.length,
                        itemBuilder: (context, index) {
                          final tip = _tips[index] as Map<String, dynamic>;
                          final score = (tip['threatScore'] as int?) ?? 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _threatColor(score).withOpacity(0.3),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _threatColor(score).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Threat: $score',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _threatColor(score),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        (tip['tipType'] as String?)?.replaceAll('_', ' ') ?? '',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                      const Spacer(),
                                      Text(
                                        (tip['status'] as String?) ?? '',
                                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    tip['description'] as String? ?? '',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  if (tip['state'] != null)
                                    Text(
                                      '📍 ${tip['state']}${tip['lga'] != null ? ' / ${tip['lga']}' : ''}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _reviewTip(tip['id'], 'dismissed'),
                                        icon: const Icon(Icons.close, size: 16),
                                        label: const Text('Dismiss'),
                                        style: TextButton.styleFrom(foregroundColor: Colors.grey),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () => _reviewTip(tip['id'], 'under_review'),
                                        icon: const Icon(Icons.visibility, size: 16),
                                        label: const Text('Review'),
                                        style: TextButton.styleFrom(foregroundColor: Colors.orange),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _reviewTip(tip['id'], 'actionable'),
                                        icon: const Icon(Icons.check, size: 16),
                                        label: const Text('Action'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
