import 'package:flutter/material.dart';
import '../../../../core/themes.dart';
import '../services/community_service.dart';
import '../models/community_post.dart';
import '../widgets/post_card.dart';

/// Screen showing another user's profile and their community posts.
///
/// Navigated to when tapping a user's avatar/name on a post card.
/// Receives the user map (id, name, phone, email) as a route argument.
class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserProfileScreen({super.key, required this.userData});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final CommunityService _service = CommunityService();
  List<CommunityPost> _posts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserPosts();
  }

  Future<void> _loadUserPosts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = widget.userData['id'] as String;
      final posts = await _service.getUserPosts(userId);
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load user posts.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.userData;
    final userName = user['name'] as String? ?? 'Unknown User';
    final userPhone = user['phone'] as String? ?? '';
    final userEmail = user['email'] as String? ?? '';
    final userAvatar = userName[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(userName),
      ),
      body: Column(
        children: [
          // User profile header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.05),
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.infoColor.withOpacity(0.2),
                  child: Text(
                    userAvatar,
                    style: const TextStyle(
                      color: AppTheme.infoColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (userPhone.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        userPhone,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
                if (userEmail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.email_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        userEmail,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '${_posts.length} post${_posts.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          // Posts list
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadUserPosts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'This user hasn\'t posted anything yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUserPosts,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          return PostCard(
            post: _posts[index],
            onLikeChanged: () => setState(() {}),
            onFavoriteChanged: () => setState(() {}),
          );
        },
      ),
    );
  }
}
