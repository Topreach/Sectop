package com.dangeremergence.controller;

import com.dangeremergence.service.IncidentService;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.SOSAlertService;
import com.dangeremergence.service.ZoneService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ThreatController.class)
@AutoConfigureMockMvc(addFilters = false)
class ThreatControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private IncidentService incidentService;

    @MockBean
    private ZoneService zoneService;

    @MockBean
    private SOSAlertService sosAlertService;

    @MockBean
    private PredictiveService predictiveService;

    @Nested
    @DisplayName("POST /api/v1/threat/analyze-text")
    class AnalyzeText {

        @Test
        @DisplayName("should detect kidnapping threat from text")
        void shouldDetectKidnappingThreat() throws Exception {
            String request = """
                    {
                        "text": "There is a kidnapping happening at the market",
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.hasThreat").value(true))
                    .andExpect(jsonPath("$.severity").value("critical"))
                    .andExpect(jsonPath("$.label").value("kidnapping"))
                    .andExpect(jsonPath("$.matchedKeywords").isArray());
        }

        @Test
        @DisplayName("should detect no threat for normal text")
        void shouldDetectNoThreatForNormalText() throws Exception {
            String request = """
                    {
                        "text": "The weather is nice today",
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.hasThreat").value(false))
                    .andExpect(jsonPath("$.severity").value("low"));
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }

        @Test
        @DisplayName("should return 400 when text is missing")
        void shouldReturn400WhenTextMissing() throws Exception {
            String request = """
                    {
                        "latitude": 6.5244
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }

        @Test
        @DisplayName("should detect bomb threat")
        void shouldDetectBombThreat() throws Exception {
            String request = """
                    {
                        "text": "There is a bomb at the train station"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.hasThreat").value(true))
                    .andExpect(jsonPath("$.severity").value("critical"))
                    .andExpect(jsonPath("$.label").value("terrorism"));
        }

        @Test
        @DisplayName("should detect banditry threat")
        void shouldDetectBanditryThreat() throws Exception {
            String request = """
                    {
                        "text": "Armed robbers are attacking the village"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.hasThreat").value(true))
                    .andExpect(jsonPath("$.severity").value("high"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/threat/level")
    class GetThreatLevel {

        @Test
        @DisplayName("should return threat level for a location")
        void shouldReturnThreatLevel() throws Exception {
            mockMvc.perform(get("/api/v1/threat/level")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.latitude").value(6.5244))
                    .andExpect(jsonPath("$.longitude").value(3.3792))
                    .andExpect(jsonPath("$.threatLevel").isString())
                    .andExpect(jsonPath("$.threatScore").isNumber());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/threat/alerts")
    class GetThreatAlerts {

        @Test
        @DisplayName("should return threat alerts for a location")
        void shouldReturnThreatAlerts() throws Exception {
            mockMvc.perform(get("/api/v1/threat/alerts")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts").isArray())
                    .andExpect(jsonPath("$.total").isNumber());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/threat/audio-result")
    class AudioResult {

        @Test
        @DisplayName("should process audio analysis result")
        void shouldProcessAudioResult() throws Exception {
            String request = """
                    {
                        "sessionId": "session_001",
                        "text": "gunshots detected",
                        "threatDetected": true,
                        "threatType": "gunshot",
                        "confidence": 0.85,
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/audio-result")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("processed"))
                    .andExpect(jsonPath("$.sessionId").value("session_001"));
        }
    }
}
