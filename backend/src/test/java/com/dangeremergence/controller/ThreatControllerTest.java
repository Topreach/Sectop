package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.model.Incident;
import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.Zone;
import com.dangeremergence.service.IncidentService;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.SOSAlertService;
import com.dangeremergence.service.ZoneService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = ThreatController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
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

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private JwtUtil jwtUtil;

    private Incident createSampleIncident() {
        Incident incident = new Incident();
        incident.setId("inc-001");
        incident.setIncidentType("flood");
        incident.setDescription("Flood in Lagos");
        incident.setLatitude(6.5244);
        incident.setLongitude(3.3792);
        incident.setSeverity(Incident.IncidentSeverity.high);
        incident.setOccurredAt(LocalDateTime.now());
        return incident;
    }

    private SOSAlert createSampleAlert() {
        SOSAlert alert = new SOSAlert();
        alert.setId("alert-001");
        alert.setAlertType("fire");
        alert.setDescription("Fire at market");
        alert.setLatitude(6.5244);
        alert.setLongitude(3.3792);
        alert.setPriority(5);
        alert.setStatus(SOSAlert.AlertStatus.active);
        alert.setCreatedAt(LocalDateTime.now());
        return alert;
    }

    @Nested
    @DisplayName("POST /api/v1/threat/analyze-text")
    class AnalyzeText {

        @Test
        @DisplayName("should analyze text and return threat assessment")
        void shouldAnalyzeText() throws Exception {
            String request = """
                    {
                        "text": "There is a fire outbreak at the market with armed robbers and a bomb threat!",
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.severity").isString())
                    .andExpect(jsonPath("$.matchedKeywords").isArray())
                    .andExpect(jsonPath("$.label").isString())
                    .andExpect(jsonPath("$.confidence").isNumber());
        }

        @Test
        @DisplayName("should return 400 when text is empty")
        void shouldReturn400WhenTextEmpty() throws Exception {
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
        @DisplayName("should detect kidnapping keywords")
        void shouldDetectKidnappingKeywords() throws Exception {
            String request = """
                    {
                        "text": "Help! Someone is being kidnapped near the bank!"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.label").value("kidnapping"))
                    .andExpect(jsonPath("$.severity").value("critical"));
        }

        @Test
        @DisplayName("should detect bomb threat keywords")
        void shouldDetectBombKeywords() throws Exception {
            String request = """
                    {
                        "text": "There is a bomb at the stadium!"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/analyze-text")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.label").value("terrorism"))
                    .andExpect(jsonPath("$.severity").value("critical"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/threat/level")
    class GetThreatLevel {

        @Test
        @DisplayName("should return threat level for a location")
        void shouldReturnThreatLevel() throws Exception {
            when(incidentService.getNearbyIncidents(anyDouble(), anyDouble(), anyDouble(), anyList()))
                    .thenReturn(List.of(createSampleIncident()));
            when(sosAlertService.getAlertsInArea(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of(createSampleAlert()));
            when(zoneService.getDangerZones()).thenReturn(List.of());
            when(predictiveService.detectHotspots(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(Map.of("hotspots", List.of()));

            mockMvc.perform(get("/api/v1/threat/level")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.levelLabel").isString())
                    .andExpect(jsonPath("$.threatLevel").isNumber())
                    .andExpect(jsonPath("$.incidentCount").isNumber());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/threat/alerts")
    class GetThreatAlerts {

        @Test
        @DisplayName("should return threat alerts for a location")
        void shouldReturnThreatAlerts() throws Exception {
            when(incidentService.getNearbyIncidents(anyDouble(), anyDouble(), anyDouble(), anyList()))
                    .thenReturn(List.of(createSampleIncident()));
            when(sosAlertService.getAlertsInArea(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of(createSampleAlert()));
            when(zoneService.getDangerZones()).thenReturn(List.of());
            when(predictiveService.detectHotspots(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(Map.of("hotspots", List.of()));

            mockMvc.perform(get("/api/v1/threat/alerts")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts").isArray())
                    .andExpect(jsonPath("$.totalCount").isNumber());
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
                        "hasDistress": true,
                        "threatLevel": "critical",
                        "confidence": 0.95,
                        "incidentType": "shooting"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/audio-result")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.created").value(true))
                    .andExpect(jsonPath("$.alertId").isString())
                    .andExpect(jsonPath("$.alert.severity").value("critical"));
        }

        @Test
        @DisplayName("should return 200 when no distress detected")
        void shouldReturn200WhenNoDistress() throws Exception {
            String request = """
                    {
                        "threatLevel": "critical"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/audio-result")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.created").value(false))
                    .andExpect(jsonPath("$.message").value("No distress detected — no alert created"));
        }
    }
}
