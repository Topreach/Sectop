import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/themes.dart';
import '../../../../core/routes.dart';
import '../models/community_post.dart';
import '../services/community_service.dart';
import 'media_player_widget.dart';
import 'like_button.dart';

/// Card widget for a single community post in the feed.
///
/// Displays the user info, media (image/video), caption, location,
/// and action bar (like, comment, share, favorite).
class PostCard extends StatefulWidget {
  final CommunityPost post;
  final VoidCallback? onLikeChanged;
  final VoidCallback? onFavoriteChanged;
  final VoidCallback? onDeleted;

  const PostCard({
    super.key,
    required this.post,
    this.onLikeChanged,
    this.onFavoriteChanged,
    this.onDeleted,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final CommunityService _service = CommunityService();
  late bool _liked;
  late int _likeCount;
  late bool _favorited;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    _likeCount = widget.post.likeCount;
    _favorited = widget.post.favoritedByMe;
  }

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      await _service.toggleLike(widget.post.id);
      widget.onLikeChanged?.call();
    } catch (e) {
      // Revert on error
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favorited = !_favorited);
    try {
      await _service.toggleFavorite(widget.post.id);
      widget.onFavoriteChanged?.call();
    } catch (e) {
      setState(() => _favorited = !_favorited);
    }
  }

  void _navigateToDetail() {
    Navigator.pushNamed(
      context,
      AppRoutes.communityPostDetail,
      arguments: widget.post.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User header
          _buildUserHeader(post),
          // Media
          if (post.mediaUrl.isNotEmpty)
            MediaPlayerWidget(
              mediaUrl: post.mediaUrl,
              mediaType: post.mediaType,
              height: 300,
              onTap: _navigateToDetail,
            ),
          // Action bar
          _buildActionBar(post),
          // Caption
          if (post.caption != null && post.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                post.caption!,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          // Location
          if (post.locationName != null && post.locationName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    post.locationName!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          // Timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              _formatTime(post.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserHeader(CommunityPost post) {
    final userName = post.isAnonymous
        ? 'Anonymous'
        : (post.user['name'] as String? ?? 'Unknown User');
    final userAvatar = post.isAnonymous
        ? 'A'
        : (post.user['name'] as String? ?? 'U')[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: post.isAnonymous
                ? Colors.grey.withOpacity(0.3)
                : AppTheme.infoColor.withOpacity(0.2),
            child: Text(
              userAvatar,
              style: TextStyle(
                color: post.isAnonymous ? Colors.grey : AppTheme.infoColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (post.isAnonymous)
                  Text(
                    'Anonymous post',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(CommunityPost post) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          // Like
          LikeButton(
            liked: _liked,
            count: _likeCount,
            onTap: _toggleLike,
          ),
          const SizedBox(width: 16),
          // Comment
          GestureDetector(
            onTap: _navigateToDetail,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 22),
                const SizedBox(width: 4),
                Text(
                  post.commentCount.toString(),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Share
          GestureDetector(
            onTap: () => _sharePost(post),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share_outlined, color: Colors.grey, size: 22),
                SizedBox(width: 4),
                Text('Share', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
          const Spacer(),
          // Favorite
          GestureDetector(
            onTap: _toggleFavorite,
            child: Icon(
              _favorited ? Icons.bookmark : Icons.bookmark_border,
              color: _favorited ? AppTheme.secondaryColor : Colors.grey,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePost(CommunityPost post) async {
    try {
      await _service.sharePost(post.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post shared!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Silently fail — share is non-critical
    }
  }

  String _formatTime(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d, yyyy').format(date);
    } catch (_) {
      return '';
    }
  }
}
