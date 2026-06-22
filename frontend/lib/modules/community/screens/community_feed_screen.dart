import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/themes.dart';
import '../../../../core/routes.dart';
import '../services/community_service.dart';
import '../models/community_post.dart';
import '../widgets/post_card.dart';

/// Main community feed screen showing posts from all users.
///
/// Supports pull-to-refresh, infinite scroll pagination, and a tab
/// toggle between "Latest" and "Nearby" feeds.
class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen>
    with SingleTickerProviderStateMixin {
  final CommunityService _service = CommunityService();
  final ScrollController _scrollController = ScrollController();

  List<CommunityPost> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 0;
  int _totalPages = 1;
  bool _useNearby = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _currentPage < _totalPages - 1) {
      _loadMore();
    }
  }

  Future<void> _loadFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
    });

    try {
      Map<String, dynamic> result;
      if (_useNearby) {
        final position = await _getCurrentPosition();
        if (position == null) {
          setState(() {
            _isLoading = false;
            _error = 'Unable to get your location. Enable GPS and try again.';
          });
          return;
        }
        result = await _service.getNearby(
          latitude: position.latitude,
          longitude: position.longitude,
          page: 0,
        );
      } else {
        result = await _service.getFeed(page: 0);
      }

      setState(() {
        _posts = result['posts'] as List<CommunityPost>;
        _currentPage = result['currentPage'] as int? ?? 0;
        _totalPages = result['totalPages'] as int? ?? 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load feed. Pull to retry.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      Map<String, dynamic> result;
      if (_useNearby && _currentPosition != null) {
        result = await _service.getNearby(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          page: nextPage,
        );
      } else {
        result = await _service.getFeed(page: nextPage);
      }

      final newPosts = result['posts'] as List<CommunityPost>;
      setState(() {
        _posts.addAll(newPosts);
        _currentPage = nextPage;
        _totalPages = result['totalPages'] as int? ?? 1;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      _currentPosition = position;
      return position;
    } catch (_) {
      return null;
    }
  }

  void _toggleFeedType() {
    setState(() => _useNearby = !_useNearby);
    _loadFeed();
  }

  void _navigateToCreatePost() async {
    final result = await Navigator.pushNamed(context, AppRoutes.communityCreatePost);
    if (result == true) {
      _loadFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          // Toggle feed type
          IconButton(
            icon: Icon(_useNearby ? Icons.explore : Icons.explore_outlined),
            tooltip: _useNearby ? 'Showing nearby posts' : 'Show nearby posts',
            onPressed: _toggleFeedType,
          ),
          // My posts
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My posts',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.communityMyPosts),
          ),
          // Favorites
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Favorites',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.communityFavorites),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadFeed,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _useNearby
                    ? 'No posts nearby yet.\nBe the first to share!'
                    : 'No posts yet.\nBe the first to share!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToCreatePost,
                icon: const Icon(Icons.add),
                label: const Text('Create Post'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
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
