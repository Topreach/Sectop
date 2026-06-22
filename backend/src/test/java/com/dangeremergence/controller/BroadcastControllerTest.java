package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.config.SecurityConfig;
import com.dangeremergence.model.Broadcast;
import com.dangeremergence.repository.UserRepository;
import com.dangeremergence.service.BroadcastService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = BroadcastController.class)
@Import(SecurityConfig.class)
class BroadcastControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private BroadcastService broadcastService;

    @MockBean
    private JwtUtil jwtUtil;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    private Authentication testAuth;
    private Authentication coordinatorAuth;

    private Broadcast testBroadcast;
    private static final String BROADCAST_ID = "bcast-123";
    private static final String CREATOR_ID = "coordinator-123";

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
        coordinatorAuth = new UsernamePasswordAuthenticationToken(CREATOR_ID, null,
                List.of(new SimpleGrantedAuthority("coordinator")));

        testBroadcast = new Broadcast();
        testBroadcast.setId(BROADCAST_ID);
        testBroadcast.setTitle("Emergency Alert");
        testBroadcast.setMessage("Flood warning in Lagos");
        testBroadcast.setSeverity(Broadcast.BroadcastSeverity.critical);
        testBroadcast.setBroadcastType(Broadcast.BroadcastType.general);
        testBroadcast.setTargetState("Lagos");
        testBroadcast.setTargetLga("Ikeja");
        testBroadcast.setCreatedBy(null);
        testBroadcast.setActive(true);
        testBroadcast.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class CreateBroadcast {

        @Test
        void shouldCreateBroadcastSuccessfully() throws Exception {
            when(broadcastService.createBroadcast(
                    eq("Emergency Alert"), eq("Flood warning"),
                    eq("critical"), eq("general"),
                    eq("Lagos"), eq("Ikeja"), isNull(),
                    isNull(), isNull(), isNull(),
                    eq(CREATOR_ID), isNull()
            )).thenReturn(testBroadcast);

            Map<String, Object> request = Map.of(
                    "title", "Emergency Alert",
                    "message", "Flood warning",
                    "severity", "critical",
                    "broadcastType", "general",
                    "targetState", "Lagos",
                    "targetLga", "Ikeja",
                    "createdById", CREATOR_ID
            );

            mockMvc.perform(post("/api/v1/broadcasts")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(BROADCAST_ID))
                    .andExpect(jsonPath("$.title").value("Emergency Alert"));
        }

        @Test
        void shouldReturn400WhenServiceThrows() throws Exception {
            when(broadcastService.createBroadcast(
                    anyString(), anyString(), anyString(),
                    anyString(), anyString(), anyString(), anyString(),
                    any(), any(), any(), anyString(), any()
            )).thenThrow(new IllegalArgumentException("Title is required"));

            Map<String, Object> request = Map.of(
                    "message", "Flood warning",
                    "createdById", CREATOR_ID
            );

            mockMvc.perform(post("/api/v1/broadcasts")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Title is required"));
        }
    }

    @Nested
    class GetBroadcasts {

        @Test
        void shouldGetActiveBroadcasts() throws Exception {
            when(broadcastService.getActiveBroadcasts(null, null))
                    .thenReturn(List.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/active")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(BROADCAST_ID));
        }

        @Test
        void shouldGetActiveBroadcastsFilteredByState() throws Exception {
            when(broadcastService.getActiveBroadcasts(eq("Lagos"), isNull()))
                    .thenReturn(List.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/active")
                            .with(authentication(testAuth))
                            .param("state", "Lagos"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(BROADCAST_ID));
        }

        @Test
        void shouldGetActiveBroadcastsFilteredByStateAndLga() throws Exception {
            when(broadcastService.getActiveBroadcasts("Lagos", "Ikeja"))
                    .thenReturn(List.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/active")
                            .with(authentication(testAuth))
                            .param("state", "Lagos")
                            .param("lga", "Ikeja"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(BROADCAST_ID));
        }

        @Test
        void shouldGetBroadcastById() throws Exception {
            when(broadcastService.getBroadcastById(BROADCAST_ID))
                    .thenReturn(Optional.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/{id}", BROADCAST_ID)
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(BROADCAST_ID));
        }

        @Test
        void shouldReturn404WhenBroadcastNotFound() throws Exception {
            when(broadcastService.getBroadcastById("unknown"))
                    .thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/broadcasts/{id}", "unknown")
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isNotFound());
        }

        @Test
        void shouldGetBroadcastCount() throws Exception {
            when(broadcastService.getActiveBroadcastCount()).thenReturn(3L);

            mockMvc.perform(get("/api/v1/broadcasts/count")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.count").value(3));
        }
    }

    @Nested
    class ExpireBroadcast {

        @Test
        void shouldExpireBroadcast() throws Exception {
            mockMvc.perform(post("/api/v1/broadcasts/{id}/expire", BROADCAST_ID)
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk());
        }
    }
}
