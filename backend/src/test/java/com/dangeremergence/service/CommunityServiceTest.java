package com.dangeremergence.service;

import com.dangeremergence.model.*;
import com.dangeremergence.model.CommunityPost.MediaType;
import com.dangeremergence.model.CommunityPost.PostStatus;
import com.dangeremergence.repository.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("CommunityService Unit Tests")
class CommunityServiceTest {

    @Mock
    private CommunityPostRepository postRepository;

    @Mock
    private CommunityLikeRepository likeRepository;

    @Mock
    private CommunityCommentRepository commentRepository;

    @Mock
    private CommunityFavoriteRepository favoriteRepository;

    @Mock
    private CommunityShareRepository shareRepository;

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private CommunityService communityService;

    @Captor
    private ArgumentCaptor<CommunityPost> postCaptor;

    private User testUser;
    private CommunityPost testPost;
    private final String userId = "user-123";
    private final String postId = "post-456";

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .id(userId)
                .name("Test User")
                .email("test@example.com")
                .phone("+2348012345678")
                .role(User.UserRole.citizen)
                .active(true)
                .build();

        testPost = CommunityPost.builder()
                .id(postId)
                .user(testUser)
                .caption("Test caption")
                .mediaUrl("https://example.com/media.jpg")
                .mediaType(MediaType.image)
                .latitude(6.5244)
                .longitude(3.3792)
                .locationName("Ikeja, Lagos")
                .isAnonymous(false)
                .status(PostStatus.active)
                .createdAt(LocalDateTime.now())
                .build();
    }

    @Nested
    @DisplayName("createPost()")
    class CreatePost {

        @Test
        @DisplayName("should create post successfully")
        void shouldCreatePost() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(postRepository.save(any(CommunityPost.class))).thenAnswer(invocation -> invocation.getArgument(0));

            CommunityPost result = communityService.createPost(
                    userId, "Test caption", "https://example.com/media.jpg",
                    "image", 6.5244, 3.3792, "Ikeja, Lagos", false);

            assertThat(result.getCaption()).isEqualTo("Test caption");
            assertThat(result.getMediaUrl()).isEqualTo("https://example.com/media.jpg");
            assertThat(result.getMediaType()).isEqualTo(MediaType.image);
            assertThat(result.getStatus()).isEqualTo(PostStatus.active);
            assertThat(result.isAnonymous()).isFalse();
        }

        @Test
        @DisplayName("should throw when user not found")
        void shouldThrowWhenUserNotFound() {
            when(userRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> communityService.createPost(
                    "unknown", "caption", "url", "image", null, null, null, false))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("User not found");
        }

        @Test
        @DisplayName("should throw when media URL is null or empty")
        void shouldThrowWhenMediaUrlMissing() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            assertThatThrownBy(() -> communityService.createPost(
                    userId, "caption", null, "image", null, null, null, false))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Media URL is required");

            assertThatThrownBy(() -> communityService.createPost(
                    userId, "caption", "   ", "image", null, null, null, false))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Media URL is required");
        }

        @Test
        @DisplayName("should throw when media type is invalid")
        void shouldThrowWhenInvalidMediaType() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

            assertThatThrownBy(() -> communityService.createPost(
                    userId, "caption", "url", "audio", null, null, null, false))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Invalid media type");
        }

        @Test
        @DisplayName("should default to image media type when null")
        void shouldDefaultToImageMediaType() {
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(postRepository.save(any(CommunityPost.class))).thenAnswer(invocation -> invocation.getArgument(0));

            CommunityPost result = communityService.createPost(
                    userId, "caption", "url", null, null, null, null, false);

            assertThat(result.getMediaType()).isEqualTo(MediaType.image);
        }
    }

    @Nested
    @DisplayName("getFeed()")
    class GetFeed {

        @Test
        @DisplayName("should return paginated feed")
        void shouldReturnPaginatedFeed() {
            Page<CommunityPost> postPage = new PageImpl<>(List.of(testPost));
            when(postRepository.findByStatusOrderByCreatedAtDesc(eq(PostStatus.active), any(Pageable.class)))
                    .thenReturn(postPage);
            when(likeRepository.countByPostId(postId)).thenReturn(0L);
            when(commentRepository.countByPostId(postId)).thenReturn(0L);
            when(shareRepository.countByPostId(postId)).thenReturn(0L);
            when(likeRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(false);
            when(favoriteRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(false);

            Map<String, Object> result = communityService.getFeed(0, 10, userId);

            assertThat(result.get("currentPage")).isEqualTo(0);
            assertThat(result.get("totalPages")).isEqualTo(1);
            assertThat(result.get("totalElements")).isEqualTo(1L);
            assertThat(result.get("posts")).isInstanceOf(List.class);
        }
    }

    @Nested
    @DisplayName("getPostById()")
    class GetPostById {

        @Test
        @DisplayName("should return post when found and active")
        void shouldReturnActivePost() {
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));
            when(likeRepository.countByPostId(postId)).thenReturn(5L);
            when(commentRepository.countByPostId(postId)).thenReturn(3L);
            when(shareRepository.countByPostId(postId)).thenReturn(1L);
            when(likeRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(true);
            when(favoriteRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(false);

            Map<String, Object> result = communityService.getPostById(postId, userId);

            assertThat(result.get("id")).isEqualTo(postId);
            assertThat(result.get("likeCount")).isEqualTo(5L);
            assertThat(result.get("commentCount")).isEqualTo(3L);
            assertThat(result.get("shareCount")).isEqualTo(1L);
            assertThat(result.get("likedByMe")).isEqualTo(true);
            assertThat(result.get("favoritedByMe")).isEqualTo(false);
        }

        @Test
        @DisplayName("should throw when post not found")
        void shouldThrowWhenNotFound() {
            when(postRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> communityService.getPostById("unknown", userId))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found");
        }

        @Test
        @DisplayName("should throw when post is not active")
        void shouldThrowWhenNotActive() {
            testPost.setStatus(PostStatus.removed);
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));

            assertThatThrownBy(() -> communityService.getPostById(postId, userId))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found or has been removed");
        }

        @Test
        @DisplayName("should hide user info when post is anonymous")
        void shouldHideUserForAnonymousPost() {
            testPost.setAnonymous(true);
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));
            when(likeRepository.countByPostId(postId)).thenReturn(0L);
            when(commentRepository.countByPostId(postId)).thenReturn(0L);
            when(shareRepository.countByPostId(postId)).thenReturn(0L);
            when(likeRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(false);
            when(favoriteRepository.existsByPostIdAndUserId(postId, userId)).thenReturn(false);

            Map<String, Object> result = communityService.getPostById(postId, userId);

            @SuppressWarnings("unchecked")
            Map<String, Object> userMap = (Map<String, Object>) result.get("user");
            assertThat(userMap.get("id")).isEqualTo("anonymous");
            assertThat(userMap.get("name")).isEqualTo("Anonymous");
            assertThat(userMap.get("isAnonymous")).isEqualTo(true);
        }
    }

    @Nested
    @DisplayName("deletePost()")
    class DeletePost {

        @Test
        @DisplayName("should soft-delete post when user is owner")
        void shouldSoftDeleteOwnPost() {
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));
            when(postRepository.save(any(CommunityPost.class))).thenAnswer(invocation -> invocation.getArgument(0));

            communityService.deletePost(postId, userId);

            verify(postRepository).save(postCaptor.capture());
            assertThat(postCaptor.getValue().getStatus()).isEqualTo(PostStatus.removed);
        }

        @Test
        @DisplayName("should throw when user is not the owner")
        void shouldThrowWhenNotOwner() {
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));

            assertThatThrownBy(() -> communityService.deletePost(postId, "other-user"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("You can only delete your own posts");
        }

        @Test
        @DisplayName("should throw when post not found")
        void shouldThrowWhenNotFound() {
            when(postRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> communityService.deletePost("unknown", userId))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found");
        }
    }

    @Nested
    @DisplayName("flagPost()")
    class FlagPost {

        @Test
        @DisplayName("should set status to flagged")
        void shouldFlagPost() {
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));
            when(postRepository.save(any(CommunityPost.class))).thenAnswer(invocation -> invocation.getArgument(0));

            communityService.flagPost(postId, userId);

            verify(postRepository).save(postCaptor.capture());
            assertThat(postCaptor.getValue().getStatus()).isEqualTo(PostStatus.flagged);
        }
    }

    @Nested
    @DisplayName("toggleLike()")
    class ToggleLike {

        @Test
        @DisplayName("should add like when not already liked")
        void shouldAddLike() {
            when(postRepository.existsById(postId)).thenReturn(true);
            when(likeRepository.findByPostIdAndUserId(postId, userId)).thenReturn(Optional.empty());
            when(postRepository.getReferenceById(postId)).thenReturn(testPost);
            when(userRepository.getReferenceById(userId)).thenReturn(testUser);
            when(likeRepository.countByPostId(postId)).thenReturn(1L);

            Map<String, Object> result = communityService.toggleLike(postId, userId);

            assertThat(result.get("liked")).isEqualTo(true);
            assertThat(result.get("likeCount")).isEqualTo(1L);
            verify(likeRepository).save(any(CommunityLike.class));
        }

        @Test
        @DisplayName("should remove like when already liked")
        void shouldRemoveLike() {
            CommunityLike existingLike = CommunityLike.builder()
                    .post(testPost)
                    .user(testUser)
                    .build();

            when(postRepository.existsById(postId)).thenReturn(true);
            when(likeRepository.findByPostIdAndUserId(postId, userId)).thenReturn(Optional.of(existingLike));
            when(likeRepository.countByPostId(postId)).thenReturn(0L);

            Map<String, Object> result = communityService.toggleLike(postId, userId);

            assertThat(result.get("liked")).isEqualTo(false);
            assertThat(result.get("likeCount")).isEqualTo(0L);
            verify(likeRepository).delete(existingLike);
        }

        @Test
        @DisplayName("should throw when post not found")
        void shouldThrowWhenPostNotFound() {
            when(postRepository.existsById("unknown")).thenReturn(false);

            assertThatThrownBy(() -> communityService.toggleLike("unknown", userId))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found");
        }
    }

    @Nested
    @DisplayName("addComment()")
    class AddComment {

        @Test
        @DisplayName("should add comment successfully")
        void shouldAddComment() {
            when(postRepository.findById(postId)).thenReturn(Optional.of(testPost));
            when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
            when(commentRepository.save(any(CommunityComment.class))).thenAnswer(invocation -> invocation.getArgument(0));

            CommunityComment result = communityService.addComment(postId, userId, "Great post!");

            assertThat(result.getContent()).isEqualTo("Great post!");
            assertThat(result.getPost().getId()).isEqualTo(postId);
            assertThat(result.getUser().getId()).isEqualTo(userId);
        }

        @Test
        @DisplayName("should throw when content is empty")
        void shouldThrowWhenContentEmpty() {
            assertThatThrownBy(() -> communityService.addComment(postId, userId, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Comment content is required");

            assertThatThrownBy(() -> communityService.addComment(postId, userId, "   "))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Comment content is required");
        }

        @Test
        @DisplayName("should throw when content exceeds 1000 characters")
        void shouldThrowWhenContentTooLong() {
            String longContent = "a".repeat(1001);

            assertThatThrownBy(() -> communityService.addComment(postId, userId, longContent))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Comment must be 1000 characters or less");
        }

        @Test
        @DisplayName("should throw when post not found")
        void shouldThrowWhenPostNotFound() {
            when(postRepository.findById("unknown")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> communityService.addComment("unknown", userId, "Nice!"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found");
        }
    }

    @Nested
    @DisplayName("deleteComment()")
    class DeleteComment {

        @Test
        @DisplayName("should delete comment when user is author")
        void shouldDeleteOwnComment() {
            CommunityComment comment = CommunityComment.builder()
                    .id("comment-1")
                    .post(testPost)
                    .user(testUser)
                    .content("Test comment")
                    .build();

            when(commentRepository.findById("comment-1")).thenReturn(Optional.of(comment));

            communityService.deleteComment("comment-1", userId);

            verify(commentRepository).delete(comment);
        }

        @Test
        @DisplayName("should throw when user is not the author")
        void shouldThrowWhenNotAuthor() {
            User otherUser = User.builder().id("other-user").build();
            CommunityComment comment = CommunityComment.builder()
                    .id("comment-1")
                    .post(testPost)
                    .user(otherUser)
                    .content("Test comment")
                    .build();

            when(commentRepository.findById("comment-1")).thenReturn(Optional.of(comment));

            assertThatThrownBy(() -> communityService.deleteComment("comment-1", userId))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("You can only delete your own comments");
        }
    }

    @Nested
    @DisplayName("toggleFavorite()")
    class ToggleFavorite {

        @Test
        @DisplayName("should add favorite when not already favorited")
        void shouldAddFavorite() {
            when(postRepository.existsById(postId)).thenReturn(true);
            when(favoriteRepository.findByPostIdAndUserId(postId, userId)).thenReturn(Optional.empty());
            when(postRepository.getReferenceById(postId)).thenReturn(testPost);
            when(userRepository.getReferenceById(userId)).thenReturn(testUser);

            Map<String, Object> result = communityService.toggleFavorite(postId, userId);

            assertThat(result.get("favorited")).isEqualTo(true);
            verify(favoriteRepository).save(any(CommunityFavorite.class));
        }

        @Test
        @DisplayName("should remove favorite when already favorited")
        void shouldRemoveFavorite() {
            CommunityFavorite existing = CommunityFavorite.builder()
                    .post(testPost)
                    .user(testUser)
                    .build();

            when(postRepository.existsById(postId)).thenReturn(true);
            when(favoriteRepository.findByPostIdAndUserId(postId, userId)).thenReturn(Optional.of(existing));

            Map<String, Object> result = communityService.toggleFavorite(postId, userId);

            assertThat(result.get("favorited")).isEqualTo(false);
            verify(favoriteRepository).delete(existing);
        }
    }

    @Nested
    @DisplayName("recordShare()")
    class RecordShare {

        @Test
        @DisplayName("should record share with platform")
        void shouldRecordShare() {
            when(postRepository.existsById(postId)).thenReturn(true);
            when(postRepository.getReferenceById(postId)).thenReturn(testPost);
            when(userRepository.getReferenceById(userId)).thenReturn(testUser);

            communityService.recordShare(postId, userId, "whatsapp");

            verify(shareRepository).save(argThat(share ->
                    share.getPlatform().equals("whatsapp") &&
                    share.getPost().getId().equals(postId) &&
                    share.getUser().getId().equals(userId)));
        }

        @Test
        @DisplayName("should default to internal platform when null")
        void shouldDefaultToInternal() {
            when(postRepository.existsById(postId)).thenReturn(true);
            when(postRepository.getReferenceById(postId)).thenReturn(testPost);
            when(userRepository.getReferenceById(userId)).thenReturn(testUser);

            communityService.recordShare(postId, userId, null);

            verify(shareRepository).save(argThat(share ->
                    share.getPlatform().equals("internal")));
        }

        @Test
        @DisplayName("should throw when post not found")
        void shouldThrowWhenPostNotFound() {
            when(postRepository.existsById("unknown")).thenReturn(false);

            assertThatThrownBy(() -> communityService.recordShare("unknown", userId, "whatsapp"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("Post not found");
        }
    }
}
