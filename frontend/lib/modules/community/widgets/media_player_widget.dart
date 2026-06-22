import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/themes.dart';

/// Displays a community post's media (image or video thumbnail).
///
/// For images, uses [CachedNetworkImage] with a shimmer placeholder.
/// For videos, shows a thumbnail overlay with a play icon.
class MediaPlayerWidget extends StatefulWidget {
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final double? height;
  final BoxFit fit;
  final VoidCallback? onTap;

  const MediaPlayerWidget({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.height,
    this.fit = BoxFit.cover,
    this.onTap,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
    await _videoController!.initialize();
    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType == 'video') {
      return _buildVideoWidget();
    }
    return _buildImageWidget();
  }

  Widget _buildImageWidget() {
    return GestureDetector(
      onTap: widget.onTap,
      child: CachedNetworkImage(
        imageUrl: widget.mediaUrl,
        height: widget.height,
        width: double.infinity,
        fit: widget.fit,
        placeholder: (context, url) => Container(
          height: widget.height ?? 250,
          color: AppTheme.darkCard,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => Container(
          height: widget.height ?? 250,
          color: AppTheme.darkCard,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.grey, size: 48),
                SizedBox(height: 8),
                Text('Failed to load image', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoWidget() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isInitialized && _videoController != null)
            SizedBox(
              height: widget.height ?? 250,
              width: double.infinity,
              child: VideoPlayer(_videoController!),
            )
          else
            Container(
              height: widget.height ?? 250,
              color: AppTheme.darkCard,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          // Play button overlay
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }
}
