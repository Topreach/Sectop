package com.dangeremergence.controller;

import com.dangeremergence.model.CommunityComment;
import com.dangeremergence.model.CommunityPost;
import com.dangeremergence.service.CommunityService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(CommunityController.class)
class CommunityControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private CommunityService communityService;

    private CommunityPost testPost;
    private CommunityComment testComment;
    private static final String POST_ID = "post-123";
    private static final String USER_ID = "user-123";
    private static final String COMMENT_ID = "comment-123";

    @BeforeEach
    void setUp() {
        testPost = new CommunityPost();
        testPost.setId(POST_ID);
        testPost.setUserId(USER_ID);
        testPost.setCaption("Test post caption");
        testPost.setMediaUrl("/uploads/test.jpg");
        testPost.setMediaType("image");
        testPost.setLatitude(6.5244);
        testPost.setLongitude(3.3792);
        testPost.setCreatedAt(LocalDateTime.now());

        testComment = new CommunityComment();
        testComment.setId(COMMENT_ID);
        testComment.setPostId(POST_ID);
        testComment.setUserId(USER_ID);
        testComment.setContent("Great post!");
        testComment.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class CreatePost {

        @Test
        void shouldCreatePostSuccessfully() throws Exception {
            Map<String, Object> postResponse = Map.of(
                    "id", POST_ID,
                    "caption", "Test post",
                    "mediaUrl", "/uploads/test.jpg"
            );
            when(communityService.createPost(
                    eq(USER_ID), eq("Test post"), eq("/uploads/test.jpg"),
                    eq("image"), eq(6.5244), eq(3.3792),
                    eq("Lagos"), eq(false)
            )).thenReturn(postResponse);

            Map<String, Object> request = Map.of(
                    "caption", "Test post",
                    "mediaUrl", "/uploads/test.jpg",
                    "mediaType", "image",
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "locationName", "Lagos"
            );

            mockMvc.perform(post("/api/v1/community/posts")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            })
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(POST_ID));
        }

        @Test
        void shouldReturn400WhenServiceThrows() throws Exception {
            when(communityService.createPost(
                    anyString(), anyString(), anyString(),
                    anyString(), any(), any(), anyString(), anyBoolean()
            )).thenThrow(new IllegalArgumentException("Media URL is required"));

            Map<String, Object> request = Map.of(
                    "caption", "Test post"
            );

            mockMvc.perform(post("/api/v1/community/posts")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            })
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Media URL is required"));
        }
    }

    @Nested
    class GetFeed {

        @Test
        void shouldGetFeed() throws Exception {
            Map<String, Object> feedResponse = Map.of(
                    "posts", List.of(Map.of("id", POST_ID)),
                    "totalPages", 1,
                    "currentPage", 0
            );
            when(communityService.getFeed(eq(0), eq(20), eq(USER_ID)))
                    .thenReturn(feedResponse);

            mockMvc.perform(get("/api/v1/community/feed")
                            .param("page", "0")
                            .param("size", "20")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.posts[0].id").value(POST_ID));
        }

        @Test
        void shouldGetFeedWithoutAuth() throws Exception {
            Map<String, Object> feedResponse = Map.of(
                    "posts", List.of(),
                    "totalPages", 0,
                    "currentPage", 0
            );
            when(communityService.getFeed(eq(0), eq(20), isNull()))
                    .thenReturn(feedResponse);

            mockMvc.perform(get("/api/v1/community/feed")
                            .param("page", "0")
                            .param("size", "20"))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class GetNearby {

        @Test
        void shouldGetNearbyPosts() throws Exception {
            Map<String, Object> nearbyResponse = Map.of(
                    "posts", List.of(Map.of("id", POST_ID)),
                    "totalPages", 1,
                    "currentPage", 0
            );
            when(communityService.getNearbyFeed(
                    eq(6.5), eq(3.3), eq(10.0), eq(0), eq(20), eq(USER_ID)
            )).thenReturn(nearbyResponse);

            mockMvc.perform(get("/api/v1/community/nearby")
                            .param("latitude", "6.5")
                            .param("longitude", "3.3")
                            .param("radiusKm", "10")
                            .param("page", "0")
                            .param("size", "20")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.posts[0].id").value(POST_ID));
        }
    }

    @Nested
    class GetPost {

        @Test
        void shouldGetPostById() throws Exception {
            Map<String, Object> postResponse = Map.of(
                    "id", POST_ID,
                    "caption", "Test post"
            );
            when(communityService.getPostById(POST_ID, USER_ID))
                    .thenReturn(postResponse);

            mockMvc.perform(get("/api/v1/community/posts/{id}", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(POST_ID));
        }

        @Test
        void shouldReturn400WhenPostNotFound() throws Exception {
            when(communityService.getPostById("unknown", USER_ID))
                    .thenThrow(new IllegalArgumentException("Post not found"));

            mockMvc.perform(get("/api/v1/community/posts/{id}", "unknown")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Post not found"));
        }
    }

    @Nested
    class DeletePost {

        @Test
        void shouldDeletePost() throws Exception {
            mockMvc.perform(delete("/api/v1/community/posts/{id}", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Post deleted successfully"));
        }

        @Test
        void shouldReturn400WhenDeleteFails() throws Exception {
            org.mockito.Mockito.doThrow(new IllegalArgumentException("Not authorized"))
                    .when(communityService).deletePost(POST_ID, USER_ID);

            mockMvc.perform(delete("/api/v1/community/posts/{id}", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Not authorized"));
        }
    }

    @Nested
    class FlagPost {

        @Test
        void shouldFlagPost() throws Exception {
            mockMvc.perform(post("/api/v1/community/posts/{id}/flag", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Post flagged for review"));
        }
    }

    @Nested
    class ToggleLike {

        @Test
        void shouldToggleLike() throws Exception {
            Map<String, Object> likeResponse = Map.of(
                    "liked", true,
                    "likeCount", 1
            );
            when(communityService.toggleLike(POST_ID, USER_ID))
                    .thenReturn(likeResponse);

            mockMvc.perform(post("/api/v1/community/posts/{id}/like", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.liked").value(true));
        }
    }

    @Nested
    class Comments {

        @Test
        void shouldAddComment() throws Exception {
            when(communityService.addComment(POST_ID, USER_ID, "Nice post!"))
                    .thenReturn(testComment);

            Map<String, String> request = Map.of("content", "Nice post!");

            mockMvc.perform(post("/api/v1/community/posts/{id}/comments", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            })
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(COMMENT_ID))
                    .andExpect(jsonPath("$.content").value("Great post!"));
        }

        @Test
        void shouldGetComments() throws Exception {
            when(communityService.getComments(POST_ID))
                    .thenReturn(List.of(testComment));

            mockMvc.perform(get("/api/v1/community/posts/{id}/comments", POST_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(COMMENT_ID));
        }

        @Test
        void shouldDeleteComment() throws Exception {
            mockMvc.perform(delete("/api/v1/community/comments/{id}", COMMENT_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Comment deleted successfully"));
        }
    }

    @Nested
    class Favorites {

        @Test
        void shouldToggleFavorite() throws Exception {
            Map<String, Object> favResponse = Map.of(
                    "favorited", true,
                    "favoriteCount", 1
            );
            when(communityService.toggleFavorite(POST_ID, USER_ID))
                    .thenReturn(favResponse);

            mockMvc.perform(post("/api/v1/community/posts/{id}/favorite", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.favorited").value(true));
        }

        @Test
        void shouldGetMyFavorites() throws Exception {
            when(communityService.getUserFavorites(USER_ID, USER_ID))
                    .thenReturn(List.of(Map.of("id", POST_ID)));

            mockMvc.perform(get("/api/v1/community/my-favorites")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class Share {

        @Test
        void shouldRecordShare() throws Exception {
            Map<String, String> request = Map.of("platform", "whatsapp");

            mockMvc.perform(post("/api/v1/community/posts/{id}/share", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            })
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Share recorded"));
        }

        @Test
        void shouldRecordShareWithDefaultPlatform() throws Exception {
            mockMvc.perform(post("/api/v1/community/posts/{id}/share", POST_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            })
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Share recorded"));
        }
    }

    @Nested
    class MyPosts {

        @Test
        void shouldGetMyPosts() throws Exception {
            when(communityService.getUserPosts(USER_ID, USER_ID))
                    .thenReturn(List.of(Map.of("id", POST_ID)));

            mockMvc.perform(get("/api/v1/community/my-posts")
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk());
        }

        @Test
        void shouldGetUserPosts() throws Exception {
            when(communityService.getUserPosts(USER_ID, USER_ID))
                    .thenReturn(List.of(Map.of("id", POST_ID)));

            mockMvc.perform(get("/api/v1/community/users/{userId}/posts", USER_ID)
                            .with(request -> {
                                request.setRemoteUser(USER_ID);
                                return request;
                            }))
                    .andExpect(status().isOk());
        }
    }
}
