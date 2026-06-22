import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../models/community_post.dart';
import '../models/community_comment.dart';

/// Service for all Community section API calls.
///
/// Uses [BackendApi] for standard JSON requests and raw [http] for
/// multipart media uploads (since BackendApi doesn't expose multipart).
class CommunityService {
  final BackendApi _api = BackendApi();
  final OfflineStorageService _storage = OfflineStorageService();

  // -----------------------------------------------------------------------
  // Media Upload
  // -----------------------------------------------------------------------

  /// Upload a media file and return the media URL and type.
  Future<Map<String, String>> uploadMedia(File file) async {
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/community/upload',
    );
    final request = http.MultipartRequest('POST', uri);

    // Add auth header — BackendApi doesn't expose getToken(), so read directly
    final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return {
        'mediaUrl': data['mediaUrl'] as String,
        'mediaType': data['mediaType'] as String,
      };
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to upload media');
    }
  }

  // -----------------------------------------------------------------------
  // Posts
  // -----------------------------------------------------------------------

  /// Create a new community post.
  Future<CommunityPost> createPost({
    required String mediaUrl,
    required String mediaType,
    String? caption,
    double? latitude,
    double? longitude,
    String? locationName,
    bool isAnonymous = false,
  }) async {
    final body = {
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationName != null && locationName.isNotEmpty) 'locationName': locationName,
      'isAnonymous': isAnonymous,
    };

    final response = await _api.post('/community/posts', body: body);
    return CommunityPost.fromJson(response);
  }

  /// Get paginated feed of community posts.
  Future<Map<String, dynamic>> getFeed({int page = 0, int size = 20}) async {
    final response = await _api.get(
      '/community/feed?page=$page&size=$size',
    );

    final postsList = (response['posts'] as List)
        .map((p) => CommunityPost.fromJson(p as Map<String, dynamic>))
        .toList();

    return {
      'posts': postsList,
      'currentPage': response['currentPage'],
      'totalPages': response['totalPages'],
      'totalElements': response['totalElements'],
    };
  }

  /// Get nearby posts based on location.
  Future<Map<String, dynamic>> getNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
    int page = 0,
    int size = 20,
  }) async {
    final response = await _api.get(
      '/community/nearby?latitude=$latitude&longitude=$longitude'
      '&radiusKm=$radiusKm&page=$page&size=$size',
    );

    final postsList = (response['posts'] as List)
        .map((p) => CommunityPost.fromJson(p as Map<String, dynamic>))
        .toList();

    return {
      'posts': postsList,
      'currentPage': response['currentPage'],
      'totalPages': response['totalPages'],
      'totalElements': response['totalElements'],
    };
  }

  /// Get a single post by ID.
  Future<CommunityPost> getPostById(String postId) async {
    final response = await _api.get('/community/posts/$postId');
    return CommunityPost.fromJson(response);
  }

  /// Get current user's posts.
  Future<List<CommunityPost>> getMyPosts() async {
    final response = await _api.get('/community/my-posts');
    final data = response['data'] as List? ?? [];
    return data
        .map((p) => CommunityPost.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Delete a post.
  Future<void> deletePost(String postId) async {
    await _api.delete('/community/posts/$postId');
  }

  /// Flag a post as inappropriate.
  Future<void> flagPost(String postId) async {
    await _api.post('/community/posts/$postId/flag', body: {});
  }

  // -----------------------------------------------------------------------
  // Likes
  // -----------------------------------------------------------------------

  /// Toggle like on a post. Returns {liked: bool, likeCount: int}.
  Future<Map<String, dynamic>> toggleLike(String postId) async {
    final response = await _api.post(
      '/community/posts/$postId/like',
      body: {},
    );
    return response;
  }

  // -----------------------------------------------------------------------
  // Comments
  // -----------------------------------------------------------------------

  /// Add a comment to a post.
  Future<CommunityComment> addComment(String postId, String content) async {
    final response = await _api.post(
      '/community/posts/$postId/comments',
      body: {'content': content},
    );
    return CommunityComment.fromJson(response);
  }

  /// Get all comments for a post.
  Future<List<CommunityComment>> getComments(String postId) async {
    final response = await _api.get(
      '/community/posts/$postId/comments',
    );
    final data = response['data'] as List? ?? [];
    return data
        .map((c) => CommunityComment.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Delete a comment.
  Future<void> deleteComment(String commentId) async {
    await _api.delete('/community/comments/$commentId');
  }

  // -----------------------------------------------------------------------
  // Favorites
  // -----------------------------------------------------------------------

  /// Toggle favorite on a post. Returns {favorited: bool}.
  Future<Map<String, dynamic>> toggleFavorite(String postId) async {
    final response = await _api.post(
      '/community/posts/$postId/favorite',
      body: {},
    );
    return response;
  }

  /// Get current user's favorited posts.
  Future<List<CommunityPost>> getMyFavorites() async {
    final response = await _api.get('/community/my-favorites');
    final data = response['data'] as List? ?? [];
    return data
        .map((p) => CommunityPost.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // -----------------------------------------------------------------------
  // Shares
  // -----------------------------------------------------------------------

  /// Record a share action.
  Future<void> sharePost(String postId, {String platform = 'internal'}) async {
    await _api.post(
      '/community/posts/$postId/share',
      body: {'platform': platform},
    );
  }
}
