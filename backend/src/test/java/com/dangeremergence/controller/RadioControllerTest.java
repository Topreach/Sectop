package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.model.RadioBroadcast;
import com.dangeremergence.service.RadioBroadcastService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
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

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = RadioController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class RadioControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RadioBroadcastService radioBroadcastService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private JwtUtil jwtUtil;

    private Authentication testAuth;
    private Authentication coordinatorAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
        coordinatorAuth = new UsernamePasswordAuthenticationToken("coordinator-123", null,
                List.of(new SimpleGrantedAuthority("coordinator")));
    }

    private RadioBroadcast createSampleBroadcast() {
        RadioBroadcast broadcast = new RadioBroadcast();
        broadcast.setId("radio_001");
        broadcast.setTitle("Emergency Alert");
        broadcast.setMessage("Flood warning in Lagos");
        broadcast.setLanguage("en");
        broadcast.setSeverity(RadioBroadcast.BroadcastSeverity.critical);
        broadcast.setTargetState("Lagos");
        broadcast.setTargetLga("Ikeja");
        return broadcast;
    }

    @Nested
    @DisplayName("POST /api/v1/radio/broadcast")
    class CreateRadioBroadcast {

        @Test
        @DisplayName("should create a radio broadcast")
        void shouldCreateRadioBroadcast() throws Exception {
            RadioBroadcast broadcast = createSampleBroadcast();
            when(radioBroadcastService.createRadioBroadcast(anyString(), anyString(), anyString(), anyString(),
                    nullable(String.class), nullable(Double.class), anyString(), anyString(),
                    nullable(String.class), anyBoolean(), nullable(String.class)))
                    .thenReturn(broadcast);

            String request = """
                    {
                        "title": "Emergency Alert",
                        "message": "Flood warning in Lagos",
                        "language": "en",
                        "severity": "critical",
                        "targetState": "Lagos",
                        "targetLga": "Ikeja"
                    }
                    """;

            mockMvc.perform(post("/api/v1/radio/broadcast")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value("radio_001"))
                    .andExpect(jsonPath("$.title").value("Emergency Alert"));
        }

        @Test
        @DisplayName("should return 400 when required fields are missing")
        void shouldReturn400WhenFieldsMissing() throws Exception {
            when(radioBroadcastService.createRadioBroadcast(any(), any(), any(), any(), any(), any(), any(), any(), any(), anyBoolean(), any()))
                    .thenThrow(new IllegalArgumentException("message is required"));

            String request = """
                    {
                        "title": "Emergency Alert"
                    }
                    """;

            mockMvc.perform(post("/api/v1/radio/broadcast")
                            .with(authentication(coordinatorAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/radio/broadcasts")
    class GetBroadcastHistory {

        @Test
        @DisplayName("should return broadcast history")
        void shouldReturnBroadcastHistory() throws Exception {
            when(radioBroadcastService.getBroadcastHistory())
                    .thenReturn(List.of(createSampleBroadcast()));

            mockMvc.perform(get("/api/v1/radio/broadcasts")
                            .with(authentication(testAuth))
                            .param("page", "0")
                            .param("size", "20"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value("radio_001"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/radio/broadcasts/{id}")
    class GetBroadcastById {

        @Test
        @DisplayName("should return broadcast by ID")
        void shouldReturnBroadcastById() throws Exception {
            when(radioBroadcastService.getBroadcastById("radio_001"))
                    .thenReturn(Optional.of(createSampleBroadcast()));

            mockMvc.perform(get("/api/v1/radio/broadcasts/radio_001")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value("radio_001"));
        }

        @Test
        @DisplayName("should return 404 when broadcast not found")
        void shouldReturn404WhenNotFound() throws Exception {
            when(radioBroadcastService.getBroadcastById("nonexistent")).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/radio/broadcasts/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/radio/broadcasts/{id}/retry")
    class RetryBroadcast {

        @Test
        @DisplayName("should retry a failed broadcast")
        void shouldRetryBroadcast() throws Exception {
            when(radioBroadcastService.retryBroadcast("radio_001"))
                    .thenReturn(createSampleBroadcast());

            mockMvc.perform(post("/api/v1/radio/broadcasts/radio_001/retry")
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value("radio_001"));
        }
    }
}
