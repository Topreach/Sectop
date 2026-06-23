package com.dangeremergence.controller;

import com.dangeremergence.model.Broadcast;
import com.dangeremergence.service.BroadcastService;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = BroadcastController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class BroadcastControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private BroadcastService broadcastService;

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
        void shouldCreateBroadcast() throws Exception {
            when(broadcastService.createBroadcast(anyString(), anyString(), anyString(), anyString(),
                    anyString(), anyString(), anyString(), anyDouble(), anyDouble(), anyDouble(),
                    anyString(), any()))
                    .thenReturn(testBroadcast);

            String request = """
                    {
                        "title": "Emergency Alert",
                        "message": "Flood warning in Lagos",
                        "severity": "critical",
                        "broadcastType": "general",
                        "targetState": "Lagos",
                        "targetLga": "Ikeja"
                    }
                    """;

            mockMvc.perform(post("/api/v1/broadcasts")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value(BROADCAST_ID))
                    .andExpect(jsonPath("$.title").value("Emergency Alert"));
        }

        @Test
        void shouldReturn400WhenRequiredFieldsMissing() throws Exception {
            String request = """
                    {
                        "title": "Emergency Alert"
                    }
                    """;

            mockMvc.perform(post("/api/v1/broadcasts")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    class GetBroadcasts {

        @Test
        void shouldReturnActiveBroadcasts() throws Exception {
            when(broadcastService.getActiveBroadcasts(anyString(), anyString()))
                    .thenReturn(List.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/active")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(BROADCAST_ID));
        }

        @Test
        void shouldReturnBroadcastById() throws Exception {
            when(broadcastService.getBroadcastById(BROADCAST_ID)).thenReturn(Optional.of(testBroadcast));

            mockMvc.perform(get("/api/v1/broadcasts/" + BROADCAST_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(BROADCAST_ID));
        }

        @Test
        void shouldReturn404WhenBroadcastNotFound() throws Exception {
            when(broadcastService.getBroadcastById("nonexistent")).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/broadcasts/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound());
        }

        @Test
        void shouldReturnBroadcastCount() throws Exception {
            when(broadcastService.getActiveBroadcastCount()).thenReturn(5L);

            mockMvc.perform(get("/api/v1/broadcasts/count")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.count").value(5));
        }
    }

    @Nested
    class ExpireBroadcast {

        @Test
        void shouldExpireBroadcast() throws Exception {
            doAnswer(invocation -> {
                return null;
            }).when(broadcastService).expireBroadcast(BROADCAST_ID);

            mockMvc.perform(post("/api/v1/broadcasts/" + BROADCAST_ID + "/expire")
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk());
        }
    }
}
