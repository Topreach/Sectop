package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.redis.core.HashOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = MeshController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class MeshControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RedisTemplate<String, Object> redisTemplate;

    @MockBean
    private HashOperations<String, Object, Object> hashOperations;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private JwtUtil jwtUtil;

    @SuppressWarnings("unchecked")
    @Nested
    @DisplayName("POST /api/v1/mesh/route")
    class FindRoute {

        @Test
        @DisplayName("should find a route between two devices")
        void shouldFindRoute() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);

            String request = """
                    {
                        "sourceDeviceId": "device_001",
                        "targetDeviceId": "device_005",
                        "neighborMetrics": [
                            {"deviceId": "device_002", "signalStrength": -70, "linkQuality": 0.9},
                            {"deviceId": "device_003", "signalStrength": -80, "linkQuality": 0.7}
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/route")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.path").isArray())
                    .andExpect(jsonPath("$.strategy").isString());
        }

        @Test
        @DisplayName("should return 400 when sourceDeviceId is missing")
        void shouldReturn400WhenSourceMissing() throws Exception {
            String request = """
                    {
                        "targetDeviceId": "device_005"
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/route")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("sourceDeviceId and targetDeviceId are required"));
        }

        @Test
        @DisplayName("should return 400 when targetDeviceId is missing")
        void shouldReturn400WhenTargetMissing() throws Exception {
            String request = """
                    {
                        "sourceDeviceId": "device_001"
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/route")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("sourceDeviceId and targetDeviceId are required"));
        }
    }

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
    }

    @SuppressWarnings("unchecked")
    @Nested
    @DisplayName("POST /api/v1/mesh/broadcast")
    class BroadcastMessage {

        @Test
        @DisplayName("should broadcast a message to the mesh network")
        void shouldBroadcastMessage() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);

            String request = """
                    {
                        "senderDeviceId": "device_001",
                        "message": "Emergency! Need help at location A",
                        "ttl": 5,
                        "priority": 1
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/broadcast")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messageId").isString())
                    .andExpect(jsonPath("$.relayedTo").isArray())
                    .andExpect(jsonPath("$.hops").isNumber());
        }

        @Test
        @DisplayName("should return 400 when senderDeviceId is missing")
        void shouldReturn400WhenSenderMissing() throws Exception {
            String request = """
                    {
                        "message": "Emergency!"
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/broadcast")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("senderDeviceId and message are required"));
        }
    }

    @SuppressWarnings("unchecked")
    @Nested
    @DisplayName("GET /api/v1/mesh/peers")
    class GetPeers {

        @Test
        @DisplayName("should return connected peers")
        void shouldReturnPeers() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);

            mockMvc.perform(get("/api/v1/mesh/peers")
                            .param("deviceId", "device_001"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.peers").isArray())
                    .andExpect(jsonPath("$.count").isNumber());
        }
    }

    @SuppressWarnings("unchecked")
    @Nested
    @DisplayName("POST /api/v1/mesh/stats")
    class ReportStats {

        @Test
        @DisplayName("should report mesh network stats")
        void shouldReportStats() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);

            String request = """
                    {
                        "deviceId": "device_001",
                        "batteryLevel": 85,
                        "signalStrength": -65,
                        "connectedPeers": 3
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/stats")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("recorded"));
        }

        @Test
        @DisplayName("should return 400 when deviceId is missing")
        void shouldReturn400WhenDeviceIdMissing() throws Exception {
            String request = """
                    {
                        "batteryLevel": 85
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/stats")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("deviceId is required"));
        }
    }
}
