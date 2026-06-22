package com.dangeremergence.service;

import com.dangeremergence.model.*;
import com.dangeremergence.model.CommunityPost.MediaType;
import com.dangeremergence.model.CommunityPost.PostStatus;
import com.dangeremergence.repository.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

/**
 * Service for the Community section — post, like, comment, favorite, share.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CommunityService {

    private final CommunityPostRepository postRepository;
    private final CommunityLikeRepository likeRepository;
    private final CommunityCommentRepository commentRepository;
    private final CommunityFavoriteRepository favoriteRepository;
    private final CommunityShareRepository shareRepository;
    private final UserRepository userRepository;

    // -----------------------------------------------------------------------
    // Posts
    // -----------------------------------------------------------------------

    /**
     * Create a new community post.
     */
    @Transactional
    public CommunityPost createPost(String userId, String caption, String mediaUrl,
                                     String mediaType, Double latitude, Double longitude,
                                     String locationName, boolean isAnonymous) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + userId));

        if (mediaUrl == null || mediaUrl.trim().isEmpty()) {
            throw new IllegalArgumentException("Media URL is required");
        }

        MediaType type;
        try {
            type = MediaType.valueOf(mediaType != null ? mediaType.toLowerCase() : "image");
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Invalid media type: '" + mediaType
                    + "'. Must be one of: image, video");
        }

        CommunityPost post = CommunityPost.builder()
                .user(user)
                .caption(caption)
                .mediaUrl(mediaUrl.trim())
                .mediaType(type)
                .latitude(latitude)
                .longitude(longitude)
                .locationName(locationName)
                .isAnonymous(isAnonymous)
                .status(PostStatus.active)
                .build();

        post = postRepository.save(post);
        log.info("Community post created: {} by user {}", post.getId(), userId);
        return post;
    }

    /**
     * Get paginated feed of active posts.
     */
    public Map<String, Object> getFeed(int page, int size, String currentUserId) {
        Pageable pageable = PageRequest.of(page, size);
        Page<CommunityPost> postPage = postRepository.findByStatusOrderByCreatedAtDesc(
                PostStatus.active, pageable);

        List<Map<String, Object>> posts = buildPostResponseList(postPage.getContent(), currentUserId);

        Map<String, Object> result = new HashMap<>();
        result.put("posts", posts);
        result.put("currentPage", postPage.getNumber());
        result.put("totalPages", postPage.getTotalPages());
        result.put("totalElements", postPage.getTotalElements());
        return result;
    }

    /**
     * Get nearby posts based on coordinates.
     */
    public Map<String, Object> getNearbyFeed(double latitude, double longitude,
                                              double radiusKm, int page, int size,
                                              String currentUserId) {
        Pageable pageable = PageRequest.of(page, size);
        Page<CommunityPost> postPage = postRepository.findNearby(
                latitude, longitude, radiusKm, pageable);

        List<Map<String, Object>> posts = buildPostResponseList(postPage.getContent(), currentUserId);

        Map<String, Object> result = new HashMap<>();
        result.put("posts", posts);
        result.put("currentPage", postPage.getNumber());
        result.put("totalPages", postPage.getTotalPages());
        result.put("totalElements", postPage.getTotalElements());
        return result;
    }

    /**
     * Get a single post by ID with interaction status for the current user.
     */
    public Map<String, Object> getPostById(String postId, String currentUserId) {
        CommunityPost post = postRepository.findById(postId)
                .orElseThrow(() -> new IllegalArgumentException("Post not found: " + postId));

        if (post.getStatus() != PostStatus.active) {
            throw new IllegalArgumentException("Post not found or has been removed");
        }

        return buildSinglePostResponse(post, currentUserId);
    }

    /**
     * Get all posts by a specific user.
     */
    public List<Map<String, Object>> getUserPosts(String userId, String currentUserId) {
        List<CommunityPost> posts = postRepository.findByUserIdAndStatusOrderByCreatedAtDesc(
                userId, PostStatus.active);
        return buildPostResponseList(posts, currentUserId);
    }

    /**
     * Soft-delete a post (set status to removed).
     */
    @Transactional
    public void deletePost(String postId, String userId) {
        CommunityPost post = postRepository.findById(postId)
                .orElseThrow(() -> new IllegalArgumentException("Post not found: " + postId));

        if (!post.getUser().getId().equals(userId)) {
            throw new IllegalArgumentException("You can only delete your own posts");
        }

        post.setStatus(PostStatus.removed);
        postRepository.save(post);
        log.info("Community post deleted (soft): {} by user {}", postId, userId);
    }

    /**
     * Flag a post as inappropriate.
     */
    @Transactional
    public void flagPost(String postId, String userId) {
        CommunityPost post = postRepository.findById(postId)
                .orElseThrow(() -> new IllegalArgumentException("Post not found: " + postId));

        post.setStatus(PostStatus.flagged);
        postRepository.save(post);
        log.info("Community post flagged: {} by user {}", postId, userId);
    }

    // -----------------------------------------------------------------------
    // Likes
    // -----------------------------------------------------------------------

    /**
     * Toggle like on a post. Returns the new like state and count.
     */
    @Transactional
    public Map<String, Object> toggleLike(String postId, String userId) {
        if (!postRepository.existsById(postId)) {
            throw new IllegalArgumentException("Post not found: " + postId);
        }

        Optional<CommunityLike> existing = likeRepository.findByPostIdAndUserId(postId, userId);
        boolean liked;

        if (existing.isPresent()) {
            likeRepository.delete(existing.get());
            liked = false;
            log.debug("Like removed: post {} by user {}", postId, userId);
        } else {
            CommunityPost post = postRepository.getReferenceById(postId);
            User user = userRepository.getReferenceById(userId);
            likeRepository.save(CommunityLike.builder().post(post).user(user).build());
            liked = true;
            log.debug("Like added: post {} by user {}", postId, userId);
        }

        long likeCount = likeRepository.countByPostId(postId);

        Map<String, Object> result = new HashMap<>();
        result.put("liked", liked);
        result.put("likeCount", likeCount);
        return result;
    }

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------

    /**
     * Add a comment to a post.
     */
    @Transactional
    public CommunityComment addComment(String postId, String userId, String content) {
        if (content == null || content.trim().isEmpty()) {
            throw new IllegalArgumentException("Comment content is required");
        }
        if (content.length() > 1000) {
            throw new IllegalArgumentException("Comment must be 1000 characters or less");
        }

        CommunityPost post = postRepository.findById(postId)
                .orElseThrow(() -> new IllegalArgumentException("Post not found: " + postId));

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + userId));

        CommunityComment comment = CommunityComment.builder()
                .post(post)
                .user(user)
                .content(content.trim())
                .build();

        comment = commentRepository.save(comment);
        log.info("Comment added: {} on post {} by user {}", comment.getId(), postId, userId);
        return comment;
    }

    /**
     * Get all comments for a post.
     */
    public List<CommunityComment> getComments(String postId) {
        return commentRepository.findByPostIdOrderByCreatedAtAsc(postId);
    }

    /**
     * Delete a comment (only the comment author can delete).
     */
    @Transactional
    public void deleteComment(String commentId, String userId) {
        CommunityComment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new IllegalArgumentException("Comment not found: " + commentId));

        if (!comment.getUser().getId().equals(userId)) {
            throw new IllegalArgumentException("You can only delete your own comments");
        }

        commentRepository.delete(comment);
        log.info("Comment deleted: {} by user {}", commentId, userId);
    }

    // -----------------------------------------------------------------------
    // Favorites
    // -----------------------------------------------------------------------

    /**
     * Toggle favorite on a post. Returns the new favorite state.
     */
    @Transactional
    public Map<String, Object> toggleFavorite(String postId, String userId) {
        if (!postRepository.existsById(postId)) {
            throw new IllegalArgumentException("Post not found: " + postId);
        }

        Optional<CommunityFavorite> existing = favoriteRepository.findByPostIdAndUserId(postId, userId);
        boolean favorited;

        if (existing.isPresent()) {
            favoriteRepository.delete(existing.get());
            favorited = false;
        } else {
            CommunityPost post = postRepository.getReferenceById(postId);
            User user = userRepository.getReferenceById(userId);
            favoriteRepository.save(CommunityFavorite.builder().post(post).user(user).build());
            favorited = true;
        }

        Map<String, Object> result = new HashMap<>();
        result.put("favorited", favorited);
        return result;
    }

    /**
     * Get all favorited posts for a user.
     */
    public List<Map<String, Object>> getUserFavorites(String userId, String currentUserId) {
        List<CommunityFavorite> favorites = favoriteRepository.findByUserIdOrderByCreatedAtDesc(userId);
        List<CommunityPost> posts = favorites.stream()
                .map(CommunityFavorite::getPost)
                .filter(p -> p.getStatus() == PostStatus.active)
                .toList();
        return buildPostResponseList(posts, currentUserId);
    }

    // -----------------------------------------------------------------------
    // Shares
    // -----------------------------------------------------------------------

    /**
     * Record a share action on a post.
     */
    @Transactional
    public void recordShare(String postId, String userId, String platform) {
        if (!postRepository.existsById(postId)) {
            throw new IllegalArgumentException("Post not found: " + postId);
        }

        CommunityPost post = postRepository.getReferenceById(postId);
        User user = userRepository.getReferenceById(userId);

        shareRepository.save(CommunityShare.builder()
                .post(post)
                .user(user)
                .platform(platform != null ? platform : "internal")
                .build());

        log.info("Share recorded: post {} by user {} on platform {}", postId, userId, platform);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private List<Map<String, Object>> buildPostResponseList(List<CommunityPost> posts, String currentUserId) {
        return posts.stream()
                .map(post -> buildSinglePostResponse(post, currentUserId))
                .toList();
    }

    private Map<String, Object> buildSinglePostResponse(CommunityPost post, String currentUserId) {
        String postId = post.getId();
        long likeCount = likeRepository.countByPostId(postId);
        long commentCount = commentRepository.countByPostId(postId);
        long shareCount = shareRepository.countByPostId(postId);

        boolean likedByMe = currentUserId != null
                && likeRepository.existsByPostIdAndUserId(postId, currentUserId);
        boolean favoritedByMe = currentUserId != null
                && favoriteRepository.existsByPostIdAndUserId(postId, currentUserId);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("id", post.getId());
        response.put("caption", post.getCaption());
        response.put("mediaUrl", post.getMediaUrl());
        response.put("mediaType", post.getMediaType().name());
        response.put("latitude", post.getLatitude());
        response.put("longitude", post.getLongitude());
        response.put("locationName", post.getLocationName());
        response.put("isAnonymous", post.isAnonymous());
        response.put("createdAt", post.getCreatedAt() != null ? post.getCreatedAt().toString() : null);
        response.put("likeCount", likeCount);
        response.put("commentCount", commentCount);
        response.put("shareCount", shareCount);
        response.put("likedByMe", likedByMe);
        response.put("favoritedByMe", favoritedByMe);

        // User info (hide if anonymous)
        if (post.isAnonymous()) {
            response.put("user", Map.of("id", "anonymous", "name", "Anonymous", "isAnonymous", true));
        } else {
            User u = post.getUser();
            response.put("user", Map.of(
                    "id", u.getId(),
                    "name", u.getName() != null ? u.getName() : "Unknown",
                    "isAnonymous", false
            ));
        }

        return response;
    }
}
