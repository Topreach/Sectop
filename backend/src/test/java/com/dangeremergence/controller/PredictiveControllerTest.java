package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.config.SecurityConfig;
import com.dangeremergence.repository.UserRepository;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.ZoneService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = PredictiveController.class)
@Import(SecurityConfig.class)
class PredictiveControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ZoneService zoneService;

    @MockBean
    private PredictiveService predictiveService;

    @MockBean
    private JwtUtil jwtUtil;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());

        doAnswer(invocation -> {
            jakarta.servlet.FilterChain chain = (jakarta.servlet.FilterChain) invocation.getArguments()[2];
            chain.doFilter((jakarta.servlet.ServletRequest) invocation.getArguments()[0],
                           (jakarta.servlet.ServletResponse) invocation.getArguments()[1]);
            return null;
        }).when(jwtAuthenticationFilter).doFilterInternal(any(), any(), any());
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/ml-forecast")
    class MlForecast {

        @Test
        @DisplayName("should return forecast for an area")
        void shouldReturnForecast() throws Exception {
            when(predictiveService.getForecast(anyDouble(), anyDouble(), anyDouble(), anyInt()))
                    .thenReturn(Map.of("forecast", List.of(), "area", "Lagos"));

            String request = """
                    {
                        "latitude": 9.08,
                        "longitude": 7.48,
                        "radius_km": 50,
                        "hours": 48
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.area").value("Lagos"));
        }

        @Test
        @DisplayName("should return 400 when lat/lng are zero")
        void shouldReturn400WhenLatLngZero() throws Exception {
            String request = """
                    {
                        "latitude": 0,
                        "longitude": 0
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("latitude and longitude are required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/ml-forecast/batch")
    class MlBatchForecast {

        @Test
        @DisplayName("should return batch forecasts")
        void shouldReturnBatchForecast() throws Exception {
            when(predictiveService.getBatchForecast(anyList()))
                    .thenReturn(Map.of("areas", List.of(), "total", 0));

            String request = """
                    {
                        "areas": [
                            {"latitude": 9.08, "longitude": 7.48, "radius_km": 50, "hours": 48}
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast/batch")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.total").isNumber());
        }

        @Test
        @DisplayName("should return 400 when areas list is empty")
        void shouldReturn400WhenAreasEmpty() throws Exception {
            String request = """
                    {
                        "areas": []
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast/batch")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("areas list is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/hotspots")
    class Hotspots {

        @Test
        @DisplayName("should detect hotspots")
        void shouldDetectHotspots() throws Exception {
            when(predictiveService.detectHotspots(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(Map.of("hotspots", List.of(), "count", 0));

            String request = """
                    {
                        "latitude": 9.08,
                        "longitude": 7.48,
                        "radius_km": 100
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/hotspots")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.count").isNumber());
        }

        @Test
        @DisplayName("should return 400 when lat/lng are zero")
        void shouldReturn400WhenLatLngZero() throws Exception {
            String request = """
                    {
                        "latitude": 0,
                        "longitude": 0
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/hotspots")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("latitude and longitude are required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/train")
    class Train {

        @Test
        @DisplayName("should trigger model training")
        void shouldTriggerTraining() throws Exception {
            when(predictiveService.triggerTraining(anyBoolean()))
                    .thenReturn(Map.of("status", "training_started", "forceRetrain", false));

            String request = """
                    {
                        "force_retrain": false
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/train")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("training_started"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/predictive/training-status")
    class TrainingStatus {

        @Test
        @DisplayName("should return training status")
        void shouldReturnTrainingStatus() throws Exception {
            when(predictiveService.getTrainingStatus())
                    .thenReturn(Map.of("status", "idle", "lastTraining", "2024-01-01T00:00:00Z"));

            mockMvc.perform(get("/api/v1/predictive/training-status")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("idle"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/predictive/model-info")
    class ModelInfo {

        @Test
        @DisplayName("should return model info")
        void shouldReturnModelInfo() throws Exception {
            when(predictiveService.getModelInfo())
                    .thenReturn(Map.of("model", "Prophet+XGBoost", "version", "2.0"));

            mockMvc.perform(get("/api/v1/predictive/model-info")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.model").value("Prophet+XGBoost"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/forecast/all-states")
    class ForecastAllStates {

        @Test
        @DisplayName("should return forecast for all states")
        void shouldReturnAllStatesForecast() throws Exception {
            when(predictiveService.getAllStatesForecast())
                    .thenReturn(Map.of("states", List.of(), "generatedAt", "2024-01-01T00:00:00Z"));

            mockMvc.perform(post("/api/v1/predictive/forecast/all-states")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.generatedAt").isString());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/predictive/health")
    class Health {

        @Test
        @DisplayName("should return health check")
        void shouldReturnHealth() throws Exception {
            when(predictiveService.healthCheck())
                    .thenReturn(Map.of("status", "healthy", "mlService", "connected"));

            mockMvc.perform(get("/api/v1/predictive/health")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("healthy"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/forecast (legacy)")
    class LegacyForecast {

        @Test
        @DisplayName("should return legacy forecast")
        void shouldReturnLegacyForecast() throws Exception {
            String request = """
                    {
                        "zoneIds": ["zone-1", "zone-2"],
                        "historyHours": 72,
                        "forecastHours": 6
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.forecasts").exists());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/anomaly")
    class Anomaly {

        @Test
        @DisplayName("should detect anomalies")
        void shouldDetectAnomalies() throws Exception {
            String request = """
                    {
                        "values": [10, 12, 15, 100, 11, 13]
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/anomaly")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.anomalies").exists())
                    .andExpect(jsonPath("$.mean").exists())
                    .andExpect(jsonPath("$.stdDev").exists());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/optimize-resources")
    class OptimizeResources {

        @Test
        @DisplayName("should optimize resource allocation")
        void shouldOptimizeResources() throws Exception {
            String request = """
                    {
                        "zones": [
                            {
                                "id": "z1",
                                "latitude": 6.5244,
                                "longitude": 3.3792,
                                "priority": 1,
                                "requiredSkill": "general"
                            }
                        ],
                        "responders": [
                            {
                                "id": "r1",
                                "latitude": 6.5244,
                                "longitude": 3.3792,
                                "skill": "general",
                                "availability": 100,
                                "name": "Responder 1"
                            }
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/optimize-resources")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").exists());
        }
    }
}
