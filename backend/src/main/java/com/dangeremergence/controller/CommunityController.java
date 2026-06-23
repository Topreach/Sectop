package com.dangeremergence.controller;

import com.dangeremergence.model.CommunityComment;
import com.dangeremergence.service.CommunityService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.*;

/**
 * REST controller for the Community section.
 * Users can post videos/images, like, comment, favorite, and share.
 */
@RestController
@RequestMapping("/api/v1/community")
@RequiredArgsConstructor
public class CommunityController {

    private final CommunityService communityService;

    // Configured upload directory — can be externalized to application.yml
    private static final String UPLOAD_DIR = "uploads/community/";

    // -----------------------------------------------------------------------
    // Media Upload
    // -----------------------------------------------------------------------

    /**
     * Upload a media file (image or video) for a community post.
     * Returns the URL/path to the uploaded file.
     */
    @PostMapping("/upload")
    public ResponseEntity<?> uploadMedia(@RequestParam("file") MultipartFile file,
                                          Authentication auth) {
        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "No file provided"));
        }

        try {
            // Validate file type
            String contentType = file.getContentType();
            if (contentType == null || (!contentType.startsWith("image/") && !contentType.startsWith("video/"))) {
                return ResponseEntity.badRequest().body(Map.of(
                        "error", "Invalid file type. Only images and videos are allowed."
                ));
            }

            // Create upload directory if it doesn't exist
            Path uploadPath = Paths.get(UPLOAD_DIR);
            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }

            // Generate unique filename
            String originalFilename = file.getOriginalFilename();
            String extension = "";
            if (originalFilename != null && originalFilename.contains(".")) {
                extension = originalFilename.substring(originalFilename.lastIndexOf("."));
            }
            String filename = UUID.randomUUID().toString() + extension;

            // Save file
            Path filePath = uploadPath.resolve(filename);
            Files.copy(file.getInputStream(), filePath, StandardCopyOption.REPLACE_EXISTING);

            String mediaType = contentType.startsWith("video/") ? "video" : "image";

            Map<String, Object> response = new HashMap<>();
            response.put("mediaUrl", "/uploads/community/" + filename);
            response.put("mediaType", mediaType);
            response.put("filename", filename);

            return ResponseEntity.ok(response);

        } catch (IOException e) {
            return ResponseEntity.internalServerError().body(Map.of("error", "Failed to upload file: " + e.getMessage()));
        }
    }

    // -----------------------------------------------------------------------
    // Posts
    // -----------------------------------------------------------------------

    /**
     * Create a new community post.
     */
    @PostMapping("/posts")
    public ResponseEntity<?> createPost(@RequestBody Map<String, Object> request,
                                         Authentication auth) {
        try {
            String userId = auth.getName();
            String caption = (String) request.get("caption");
            String mediaUrl = (String) request.get("mediaUrl");
            String mediaType = (String) request.get("mediaType");
            Double latitude = request.get("latitude") != null
                    ? ((Number) request.get("latitude")).doubleValue() : null;
            Double longitude = request.get("longitude") != null
                    ? ((Number) request.get("longitude")).doubleValue() : null;
            String locationName = (String) request.get("locationName");
            boolean isAnonymous = request.get("isAnonymous") != null
                    && Boolean.TRUE.equals(request.get("isAnonymous"));

            var post = communityService.createPost(userId, caption, mediaUrl, mediaType,
                    latitude, longitude, locationName, isAnonymous);
            return ResponseEntity.ok(post);

        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get paginated feed of community posts.
     */
    @GetMapping("/feed")
    public ResponseEntity<?> getFeed(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            Authentication auth) {
        String userId = auth != null ? auth.getName() : null;
        return ResponseEntity.ok(communityService.getFeed(page, size, userId));
    }

    /**
     * Get nearby posts based on location.
     */
    @GetMapping("/nearby")
    public ResponseEntity<?> getNearby(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "10") double radiusKm,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            Authentication auth) {
        String userId = auth != null ? auth.getName() : null;
        return ResponseEntity.ok(communityService.getNearbyFeed(
                latitude, longitude, radiusKm, page, size, userId));
    }

    /**
     * Get a single post by ID.
     */
    @GetMapping("/posts/{id}")
    public ResponseEntity<?> getPost(@PathVariable String id, Authentication auth) {
        try {
            String userId = auth != null ? auth.getName() : null;
            return ResponseEntity.ok(communityService.getPostById(id, userId));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get current user's own posts.
     */
    @GetMapping("/my-posts")
    public ResponseEntity<?> getMyPosts(Authentication auth) {
        String userId = auth.getName();
        return ResponseEntity.ok(communityService.getUserPosts(userId, userId));
    }

    /**
     * Get posts by a specific user (for viewing other users' profiles).
     */
    @GetMapping("/users/{userId}/posts")
    public ResponseEntity<?> getUserPosts(@PathVariable String userId, Authentication auth) {
        String currentUserId = auth != null ? auth.getName() : null;
        return ResponseEntity.ok(communityService.getUserPosts(userId, currentUserId));
    }

    /**
     * Delete a post (soft delete).
     */
    @DeleteMapping("/posts/{id}")
    public ResponseEntity<?> deletePost(@PathVariable String id, Authentication auth) {
        try {
            communityService.deletePost(id, auth.getName());
            return ResponseEntity.ok(Map.of("message", "Post deleted successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Flag a post as inappropriate.
     */
    @PostMapping("/posts/{id}/flag")
    public ResponseEntity<?> flagPost(@PathVariable String id, Authentication auth) {
        try {
            communityService.flagPost(id, auth.getName());
            return ResponseEntity.ok(Map.of("message", "Post flagged for review"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    // -----------------------------------------------------------------------
    // Likes
    // -----------------------------------------------------------------------

    /**
     * Toggle like on a post.
     */
    @PostMapping("/posts/{id}/like")
    public ResponseEntity<?> toggleLike(@PathVariable String id, Authentication auth) {
        try {
            return ResponseEntity.ok(communityService.toggleLike(id, auth.getName()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------

    /**
     * Add a comment to a post.
     */
    @PostMapping("/posts/{id}/comments")
    public ResponseEntity<?> addComment(@PathVariable String id,
                                         @RequestBody Map<String, String> body,
                                         Authentication auth) {
        try {
            String content = body.get("content");
            CommunityComment comment = communityService.addComment(id, auth.getName(), content);
            return ResponseEntity.ok(comment);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get all comments for a post.
     */
    @GetMapping("/posts/{id}/comments")
    public ResponseEntity<?> getComments(@PathVariable String id) {
        return ResponseEntity.ok(communityService.getComments(id));
    }

    /**
     * Delete a comment.
     */
    @DeleteMapping("/comments/{id}")
    public ResponseEntity<?> deleteComment(@PathVariable String id, Authentication auth) {
        try {
            communityService.deleteComment(id, auth.getName());
            return ResponseEntity.ok(Map.of("message", "Comment deleted successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    // -----------------------------------------------------------------------
    // Favorites
    // -----------------------------------------------------------------------

    /**
     * Toggle favorite on a post.
     */
    @PostMapping("/posts/{id}/favorite")
    public ResponseEntity<?> toggleFavorite(@PathVariable String id, Authentication auth) {
        try {
            return ResponseEntity.ok(communityService.toggleFavorite(id, auth.getName()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get current user's favorited posts.
     */
    @GetMapping("/my-favorites")
    public ResponseEntity<?> getMyFavorites(Authentication auth) {
        String userId = auth.getName();
        return ResponseEntity.ok(communityService.getUserFavorites(userId, userId));
    }

    // -----------------------------------------------------------------------
    // Shares
    // -----------------------------------------------------------------------

    /**
     * Record a share action on a post.
     */
    @PostMapping("/posts/{id}/share")
    public ResponseEntity<?> sharePost(@PathVariable String id,
                                        @RequestBody(required = false) Map<String, String> body,
                                        Authentication auth) {
        try {
            String platform = body != null ? body.get("platform") : "internal";
            communityService.recordShare(id, auth.getName(), platform);
            return ResponseEntity.ok(Map.of("message", "Share recorded"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }
}
