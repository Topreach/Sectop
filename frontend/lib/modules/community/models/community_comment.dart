/// Model representing a comment on a community post.
class CommunityComment {
  final String id;
  final String postId;
  final String userId;
  final String userName;
  final String content;
  final String createdAt;

  CommunityComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: json['id'] as String,
      postId: json['post'] != null
          ? (json['post'] as Map<String, dynamic>)['id'] as String? ?? ''
          : (json['postId'] as String? ?? ''),
      userId: json['user'] != null
          ? (json['user'] as Map<String, dynamic>)['id'] as String? ?? ''
          : (json['userId'] as String? ?? ''),
      userName: json['user'] != null
          ? (json['user'] as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
          : (json['userName'] as String? ?? 'Unknown'),
      content: json['content'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}
