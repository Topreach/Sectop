/// Model representing a community post from the feed.
class CommunityPost {
  final String id;
  final String? caption;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final bool isAnonymous;
  final String createdAt;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final bool likedByMe;
  final bool favoritedByMe;
  final Map<String, dynamic> user;

  CommunityPost({
    required this.id,
    this.caption,
    required this.mediaUrl,
    required this.mediaType,
    this.latitude,
    this.longitude,
    this.locationName,
    this.isAnonymous = false,
    required this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.likedByMe = false,
    this.favoritedByMe = false,
    required this.user,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    return CommunityPost(
      id: json['id'] as String,
      caption: json['caption'] as String?,
      mediaUrl: json['mediaUrl'] as String,
      mediaType: json['mediaType'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationName: json['locationName'] as String?,
      isAnonymous: json['isAnonymous'] as bool? ?? false,
      createdAt: json['createdAt'] as String,
      likeCount: json['likeCount'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      shareCount: json['shareCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      favoritedByMe: json['favoritedByMe'] as bool? ?? false,
      user: json['user'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caption': caption,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'isAnonymous': isAnonymous,
      'createdAt': createdAt,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'shareCount': shareCount,
      'likedByMe': likedByMe,
      'favoritedByMe': favoritedByMe,
      'user': user,
    };
  }
}
