package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.model.CommunityComment;
import com.dangeremergence.model.CommunityPost;
import com.dangeremergence.service.CommunityService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = CommunityController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class CommunityControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private CommunityService communityService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private JwtUtil jwtUtil;

    private CommunityPost testPost;
    private CommunityComment testComment;
    private static final String POST_ID = "post-123";
    private static final String USER_ID = "user-123";
    private static final String COMMENT_ID = "comment-123";
    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken(USER_ID, null, List.of());
        SecurityContextHolder.getContext().setAuthentication(testAuth);

        testPost = new CommunityPost();
        testPost.setId(POST_ID);
        testPost.setUser(null);
        testPost.setCaption("Test post caption");
        testPost.setMediaUrl("/uploads/test.jpg");
        testPost.setMediaType(CommunityPost.MediaType.image);
        testPost.setLatitude(6.5244);
        testPost.setLongitude(3.3792);
        testPost.setCreatedAt(LocalDateTime.now());

        testComment = new CommunityComment();
        testComment.setId(COMMENT_ID);
        testComment.setPost(null);
        testComment.setUser(null);
        testComment.setContent("Great post!");
        testComment.setCreatedAt(LocalDateTime.now());
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Nested
    class CreatePost {

        @Test
        void shouldCreatePost() throws Exception {
            when(communityService.createPost(anyString(), anyString(), anyString(), anyString(),
                    anyDouble(), anyDouble(), anyString(), anyBoolean()))
                    .thenReturn(testPost);

            String request = """
                    {
                        "caption": "Test post caption",
                        "mediaUrl": "/uploads/test.jpg",
                        "mediaType": "image",
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/community/posts")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(POST_ID));
        }

        @Test
        void shouldReturn400WhenCaptionMissing() throws Exception {
            String request = """
                    {
                        "mediaUrl": "/uploads/test.jpg"
                    }
                    """;

            mockMvc.perform(post("/api/v1/community/posts")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    class GetFeed {

        @Test
        void shouldReturnFeed() throws Exception {
            when(communityService.getFeed(anyInt(), anyInt(), nullable(String.class)))
                    .thenReturn(Map.of("posts", List.of(testPost), "total", 1, "page", 0, "size", 20));

            mockMvc.perform(get("/api/v1/community/feed")
                            .with(authentication(testAuth))
                            .param("page", "0")
                            .param("size", "20"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.posts").isArray())
                    .andExpect(jsonPath("$.total").value(1));
        }

        @Test
        void shouldReturnFeedWithDefaultPagination() throws Exception {
            when(communityService.getFeed(anyInt(), anyInt(), nullable(String.class)))
                    .thenReturn(Map.of("posts", List.of(), "total", 0, "page", 0, "size", 20));

            mockMvc.perform(get("/api/v1/community/feed")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.posts").isArray());
        }
    }

    @Nested
    class GetNearby {

        @Test
        void shouldReturnNearbyPosts() throws Exception {
            when(communityService.getNearbyFeed(anyDouble(), anyDouble(), anyDouble(), anyInt(), anyInt(), nullable(String.class)))
                    .thenReturn(Map.of("posts", List.of(testPost), "total", 1));

            mockMvc.perform(get("/api/v1/community/nearby")
                            .with(authentication(testAuth))
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.posts").isArray());
        }
    }

    @Nested
    class GetPost {

        @Test
        void shouldReturnPostById() throws Exception {
            when(communityService.getPostById(POST_ID, nullable(String.class)))
                    .thenReturn(Map.of("id", POST_ID, "caption", "Test post caption"));

            mockMvc.perform(get("/api/v1/community/posts/" + POST_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(POST_ID));
        }

        @Test
        void shouldReturn400WhenPostNotFound() throws Exception {
            when(communityService.getPostById("nonexistent", nullable(String.class)))
                    .thenThrow(new IllegalArgumentException("Post not found"));

            mockMvc.perform(get("/api/v1/community/posts/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    class DeletePost {

        @Test
        void shouldDeleteOwnPost() throws Exception {
            mockMvc.perform(delete("/api/v1/community/posts/" + POST_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Post deleted successfully"));
        }

        @Test
        void shouldReturn400WhenPostNotFound() throws Exception {
            doThrow(new IllegalArgumentException("Post not found: nonexistent"))
                    .when(communityService).deletePost(eq("nonexistent"), anyString());

            mockMvc.perform(delete("/api/v1/community/posts/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    class FlagPost {

        @Test
        void shouldFlagPost() throws Exception {
            mockMvc.perform(post("/api/v1/community/posts/" + POST_ID + "/flag")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class ToggleLike {

        @Test
        void shouldToggleLike() throws Exception {
            when(communityService.toggleLike(POST_ID, USER_ID)).thenReturn(Map.of("liked", true, "likeCount", 1));

            mockMvc.perform(post("/api/v1/community/posts/" + POST_ID + "/like")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.liked").value(true));
        }
    }

    @Nested
    class Comments {

        @Test
        void shouldAddComment() throws Exception {
            when(communityService.addComment(anyString(), anyString(), anyString()))
                    .thenReturn(testComment);

            String request = """
                    {
                        "content": "Great post!"
                    }
                    """;

            mockMvc.perform(post("/api/v1/community/posts/" + POST_ID + "/comments")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(COMMENT_ID));
        }

        @Test
        void shouldGetComments() throws Exception {
            when(communityService.getComments(POST_ID))
                    .thenReturn(List.of());

            mockMvc.perform(get("/api/v1/community/posts/" + POST_ID + "/comments"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").isArray());
        }

        @Test
        void shouldDeleteComment() throws Exception {
            mockMvc.perform(delete("/api/v1/community/comments/" + COMMENT_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Comment deleted successfully"));
        }
    }

    @Nested
    class Favorites {

        @Test
        void shouldToggleFavorite() throws Exception {
            when(communityService.toggleFavorite(POST_ID, USER_ID)).thenReturn(Map.of("favorited", true));

            mockMvc.perform(post("/api/v1/community/posts/" + POST_ID + "/favorite")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.favorited").value(true));
        }

        @Test
        void shouldGetFavorites() throws Exception {
            when(communityService.getUserFavorites(USER_ID, USER_ID))
                    .thenReturn(List.of(Map.of("id", POST_ID)));

            mockMvc.perform(get("/api/v1/community/my-favorites")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(POST_ID));
        }
    }

    @Nested
    class Share {

        @Test
        void shouldSharePost() throws Exception {
            doNothing().when(communityService).recordShare(eq(POST_ID), eq(USER_ID), anyString());

            String request = """
                    {
                        "platform": "twitter"
                    }
                    """;

            mockMvc.perform(post("/api/v1/community/posts/" + POST_ID + "/share")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
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
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(POST_ID));
        }

        @Test
        void shouldGetUserPosts() throws Exception {
            when(communityService.getUserPosts("other-user", nullable(String.class)))
                    .thenReturn(List.of());

            mockMvc.perform(get("/api/v1/community/users/other-user/posts")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").isArray());
        }
    }
}
