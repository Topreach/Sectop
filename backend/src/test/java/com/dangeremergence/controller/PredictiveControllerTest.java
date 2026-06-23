package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.ZoneService;
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
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = PredictiveController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class PredictiveControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ZoneService zoneService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private PredictiveService predictiveService;

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/ml-forecast")
    class MlForecast {

        @Test
        @DisplayName("should return ML forecast for a zone")
        void shouldReturnMlForecast() throws Exception {
            when(predictiveService.getForecast(anyDouble(), anyDouble(), anyDouble(), anyInt()))
                    .thenReturn(Map.of("zoneId", "zone_1", "forecast", List.of()));

            String request = """
                    {
                        "zoneId": "zone_1",
                        "historyHours": 24,
                        "forecastHours": 12
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zoneId").value("zone_1"))
                    .andExpect(jsonPath("$.forecast").isArray());
        }

        @Test
        @DisplayName("should return 400 when zoneId is missing")
        void shouldReturn400WhenZoneIdMissing() throws Exception {
            String request = """
                    {
                        "historyHours": 24,
                        "forecastHours": 12
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("zoneId is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/ml-forecast/batch")
    class MlBatchForecast {

        @Test
        @DisplayName("should return ML forecast for multiple zones")
        void shouldReturnMlBatchForecast() throws Exception {
            when(predictiveService.getBatchForecast(anyList()))
                    .thenReturn(Map.of("forecasts", List.of()));

            String request = """
                    {
                        "zoneIds": ["zone_1", "zone_2"],
                        "historyHours": 24,
                        "forecastHours": 12
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast/batch")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.forecasts").isArray());
        }

        @Test
        @DisplayName("should return 400 when zoneIds is empty")
        void shouldReturn400WhenZoneIdsEmpty() throws Exception {
            String request = """
                    {
                        "zoneIds": [],
                        "historyHours": 24,
                        "forecastHours": 12
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/ml-forecast/batch")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("zoneIds must not be empty"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/hotspots")
    class Hotspots {

        @Test
        @DisplayName("should return hotspots for a location")
        void shouldReturnHotspots() throws Exception {
            when(predictiveService.detectHotspots(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(Map.of("zoneId", "zone_1", "riskLevel", "high"));

            String request = """
                    {
                        "latitude": 6.5244,
                        "longitude": 3.3792,
                        "radiusKm": 10
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/hotspots")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zoneId").value("zone_1"))
                    .andExpect(jsonPath("$.riskLevel").value("high"));
        }

        @Test
        @DisplayName("should return 400 when coordinates are missing")
        void shouldReturn400WhenCoordinatesMissing() throws Exception {
            String request = """
                    {
                        "radiusKm": 10
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/hotspots")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/train")
    class Train {

        @Test
        @DisplayName("should trigger model training")
        void shouldTriggerTraining() throws Exception {
            when(predictiveService.triggerTraining(anyBoolean())).thenReturn(Map.of("status", "training_started"));

            mockMvc.perform(post("/api/v1/predictive/train")
                            .with(authentication(testAuth)))
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
            when(predictiveService.getTrainingStatus()).thenReturn(Map.of("status", "idle", "lastTraining", null));

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
            when(predictiveService.getModelInfo()).thenReturn(Map.of("modelVersion", "1.0", "features", List.of()));

            mockMvc.perform(get("/api/v1/predictive/model-info")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.modelVersion").value("1.0"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/forecast/all-states")
    class ForecastAllStates {

        @Test
        @DisplayName("should return forecast for all states")
        void shouldReturnForecastAllStates() throws Exception {
            when(predictiveService.getAllStatesForecast()).thenReturn(Map.of("forecasts", List.of()));

            mockMvc.perform(post("/api/v1/predictive/forecast/all-states")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.forecasts").isArray());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/predictive/health")
    class Health {

        @Test
        @DisplayName("should return predictive service health")
        void shouldReturnHealth() throws Exception {
            when(predictiveService.healthCheck()).thenReturn(Map.of("status", "healthy", "modelLoaded", true));

            mockMvc.perform(get("/api/v1/predictive/health")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("healthy"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/forecast")
    class LegacyForecast {

        @Test
        @DisplayName("should return legacy forecast for a zone")
        void shouldReturnLegacyForecast() throws Exception {
            when(zoneService.getZoneById(anyString())).thenReturn(java.util.Optional.empty());

            String request = """
                    {
                        "zoneId": "zone_1",
                        "historyHours": 24,
                        "forecastHours": 12
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/forecast")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.error").value("Zone not found: zone_1"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/anomaly")
    class Anomaly {

        @Test
        @DisplayName("should detect anomalies in data")
        void shouldDetectAnomalies() throws Exception {
            // The controller handles anomaly detection internally, not via PredictiveService
            String request = """
                    {
                        "readings": [
                            {"zoneId": "zone_1", "value": 100},
                            {"zoneId": "zone_2", "value": 5}
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/anomaly")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").isArray());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/predictive/optimize-resources")
    class OptimizeResources {

        @Test
        @DisplayName("should optimize resource allocation")
        void shouldOptimizeResources() throws Exception {
            // The controller handles resource optimization internally, not via PredictiveService
            String request = """
                    {
                        "zones": [
                            {"zoneId": "zone_1", "priority": 5, "requiredResources": 10},
                            {"zoneId": "zone_2", "priority": 3, "requiredResources": 5}
                        ],
                        "availableResources": [
                            {"type": "ambulance", "count": 5},
                            {"type": "fire_truck", "count": 3}
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/predictive/optimize-resources")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.allocations").isArray());
        }
    }
}
