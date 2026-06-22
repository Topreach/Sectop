import 'package:flutter/material.dart';
import '../../../../core/themes.dart';
import '../services/community_service.dart';
import '../models/community_post.dart';
import '../models/community_comment.dart';
import '../widgets/media_player_widget.dart';
import '../widgets/like_button.dart';
import '../widgets/comment_tile.dart';

/// Full-screen detail view for a single community post.
///
/// Shows the post media full-size, caption, action bar, and
/// a comment section where users can add and delete comments.
class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final CommunityService _service = CommunityService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  CommunityPost? _post;
  List<CommunityComment> _comments = [];
  bool _isLoading = true;
  bool _isLoadingComments = true;
  String? _error;
  String? _currentUserId;

  late bool _liked;
  late int _likeCount;
  late bool _favorited;

  @override
  void initState() {
    super.initState();
    _loadPost();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPost() async {
    try {
      final post = await _service.getPostById(widget.postId);
      if (mounted) {
        setState(() {
          _post = post;
          _liked = post.likedByMe;
          _likeCount = post.likeCount;
          _favorited = post.favoritedByMe;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load post.';
        });
      }
    }
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _service.getComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      await _service.toggleLike(widget.postId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likeCount += _liked ? 1 : -1;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favorited = !_favorited);
    try {
      await _service.toggleFavorite(widget.postId);
    } catch (e) {
      if (mounted) setState(() => _favorited = !_favorited);
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    _commentController.clear();
    // Optimistic add
    final tempComment = CommunityComment(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      postId: widget.postId,
      userId: _currentUserId ?? '',
      userName: 'You',
      content: text,
      createdAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      _comments.add(tempComment);
      _post?.commentCount++;
    });

    try {
      final comment = await _service.addComment(widget.postId, text);
      // Replace temp with real comment
      setState(() {
        final index = _comments.indexOf(tempComment);
        if (index >= 0) {
          _comments[index] = comment;
        }
      });
    } catch (e) {
      // Remove temp comment on failure
      setState(() {
        _comments.remove(tempComment);
        _post?.commentCount--;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add comment')),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _service.deleteComment(commentId);
      setState(() {
        _comments.removeWhere((c) => c.id == commentId);
        _post?.commentCount--;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete comment')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadPost, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final post = _post!;
    return Column(
      children: [
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Media
                if (post.mediaUrl.isNotEmpty)
                  MediaPlayerWidget(
                    mediaUrl: post.mediaUrl,
                    mediaType: post.mediaType,
                    height: 350,
                    fit: BoxFit.contain,
                  ),
                // Action bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      LikeButton(
                        liked: _liked,
                        count: _likeCount,
                        onTap: _toggleLike,
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _scrollToComments(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                color: Colors.grey, size: 22),
                            const SizedBox(width: 4),
                            Text(
                              '${post.commentCount}',
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
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
                ),
                // Caption
                if (post.caption != null && post.caption!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      post.caption!,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                // Location
                if (post.locationName != null && post.locationName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
                const Divider(),
                // Comments header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Comments (${post.commentCount})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Comments list
                if (_isLoadingComments)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No comments yet. Be the first!',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._comments.map((comment) => CommentTile(
                        comment: comment,
                        isOwnComment: comment.userId == _currentUserId,
                        onDelete: () => _deleteComment(comment.id),
                      )),
                const SizedBox(height: 80), // Space for input bar
              ],
            ),
          ),
        ),
        // Comment input bar
        _buildCommentInput(),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _addComment(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.primaryColor),
            onPressed: _addComment,
          ),
        ],
      ),
    );
  }

  void _scrollToComments() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
