package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.config.SecurityConfig;
import com.dangeremergence.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
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

@WebMvcTest(value = MeshController.class)
@Import(SecurityConfig.class)
class MeshControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RedisTemplate<String, Object> redisTemplate;

    @MockBean
    private HashOperations<String, Object, Object> hashOperations;

    @MockBean
    private JwtUtil jwtUtil;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

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
                            .content(request)
                            .with(authentication(testAuth)))
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
                            .content(request)
                            .with(authentication(testAuth)))
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
        @DisplayName("should broadcast a message through the mesh")
        void shouldBroadcastMessage() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);
            when(hashOperations.size(anyString())).thenReturn(5L);
            when(hashOperations.keys(anyString())).thenReturn(Set.of("dev_001", "dev_002", "dev_003"));

            String request = """
                    {
                        "sourceDeviceId": "device_001",
                        "messageType": "alert",
                        "priority": 2,
                        "payload": {"type": "flood_warning", "location": "Lagos"}
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/broadcast")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messageId").isString())
                    .andExpect(jsonPath("$.sourceDeviceId").value("device_001"))
                    .andExpect(jsonPath("$.estimatedReach").isNumber());
        }

        @Test
        @DisplayName("should return 400 when sourceDeviceId is missing")
        void shouldReturn400WhenSourceMissing() throws Exception {
            String request = """
                    {
                        "messageType": "alert"
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/broadcast")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request)
                            .with(authentication(testAuth)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("sourceDeviceId is required"));
        }
    }

    @SuppressWarnings("unchecked")
    @Nested
    @DisplayName("GET /api/v1/mesh/peers")
    class GetPeers {

        @Test
        @DisplayName("should return list of mesh peers")
        void shouldReturnPeers() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);
            Map<Object, Object> peerMap = new HashMap<>();
            peerMap.put("dev_001", Map.of("deviceId", "dev_001", "signalStrength", -70));
            when(hashOperations.entries(anyString())).thenReturn(peerMap);

            mockMvc.perform(get("/api/v1/mesh/peers")
                            .with(authentication(testAuth)))
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
        @DisplayName("should record peer stats")
        void shouldRecordStats() throws Exception {
            when(redisTemplate.opsForHash()).thenReturn(hashOperations);

            String request = """
                    {
                        "deviceId": "device_001",
                        "signalStrength": -65,
                        "batteryLevel": 85
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/stats")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("recorded"))
                    .andExpect(jsonPath("$.deviceId").value("device_001"));
        }

        @Test
        @DisplayName("should return 400 when deviceId is missing")
        void shouldReturn400WhenDeviceIdMissing() throws Exception {
            String request = """
                    {
                        "signalStrength": -65
                    }
                    """;

            mockMvc.perform(post("/api/v1/mesh/route")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request)
                            .with(authentication(testAuth)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("deviceId is required"));
        }
    }
}
