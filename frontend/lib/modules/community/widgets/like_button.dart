import 'package:flutter/material.dart';
import '../../../core/themes.dart';

/// Animated like button for community posts.
///
/// Shows a heart icon that fills when [liked] is true.
/// Displays [count] next to the icon.
class LikeButton extends StatefulWidget {
  final bool liked;
  final int count;
  final VoidCallback? onTap;

  const LikeButton({
    super.key,
    required this.liked,
    required this.count,
    this.onTap,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _animController.forward().then((_) => _animController.reverse());
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.liked ? Icons.favorite : Icons.favorite_border,
              color: widget.liked ? AppTheme.primaryColor : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 4),
            Text(
              _formatCount(widget.count),
              style: TextStyle(
                fontSize: 13,
                color: widget.liked ? AppTheme.primaryColor : Colors.grey[600],
                fontWeight: widget.liked ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
