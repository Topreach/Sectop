package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.config.JwtUtil;
import com.dangeremergence.config.SecurityConfig;
import com.dangeremergence.model.Incident;
import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.UserRepository;
import com.dangeremergence.service.IncidentService;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.SOSAlertService;
import com.dangeremergence.service.ZoneService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = ThreatController.class)
@Import(SecurityConfig.class)
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
    private JwtUtil jwtUtil;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @BeforeEach
    void setUp() {
        doAnswer(invocation -> {
            jakarta.servlet.FilterChain chain = (jakarta.servlet.FilterChain) invocation.getArguments()[2];
            chain.doFilter((jakarta.servlet.ServletRequest) invocation.getArguments()[0],
                           (jakarta.servlet.ServletResponse) invocation.getArguments()[1]);
            return null;
        }).when(jwtAuthenticationFilter).doFilterInternal(any(), any(), any());
    }

    private Incident createSampleIncident() {
        Incident incident = new Incident();
        incident.setId("inc-001");
        incident.setIncidentType("flood");
        incident.setDescription("Flood in Lagos");
        incident.setLatitude(6.5244);
        incident.setLongitude(3.3792);
        incident.setCreatedAt(LocalDateTime.now());
        return incident;
    }

    private SOSAlert createSampleAlert() {
        SOSAlert alert = new SOSAlert();
        alert.setId("alert-001");
        alert.setDescription("Help needed");
        alert.setLatitude(6.5244);
        alert.setLongitude(3.3792);
        alert.setCreatedAt(LocalDateTime.now());
        return alert;
    }

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
            when(incidentService.getNearbyIncidents(anyDouble(), anyDouble(), anyDouble(), any()))
                    .thenReturn(List.of());
            when(zoneService.getDangerZones()).thenReturn(List.of());
            when(sosAlertService.getAlertsInArea(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());
            when(predictiveService.detectHotspots(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(Map.of("hotspots", List.of()));

            mockMvc.perform(get("/api/v1/threat/level")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.threatLevel").isNumber())
                    .andExpect(jsonPath("$.incidentCount").isNumber())
                    .andExpect(jsonPath("$.dangerZoneCount").isNumber())
                    .andExpect(jsonPath("$.activeAlertCount").isNumber())
                    .andExpect(jsonPath("$.predictedHotspotCount").isNumber())
                    .andExpect(jsonPath("$.hasCritical").isBoolean())
                    .andExpect(jsonPath("$.levelLabel").isString());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/threat/alerts")
    class GetThreatAlerts {

        @Test
        @DisplayName("should return threat alerts for a location")
        void shouldReturnThreatAlerts() throws Exception {
            when(incidentService.getNearbyIncidents(anyDouble(), anyDouble(), anyDouble(), any()))
                    .thenReturn(List.of());
            when(zoneService.getDangerZones()).thenReturn(List.of());
            when(sosAlertService.getAlertsInArea(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of());

            mockMvc.perform(get("/api/v1/threat/alerts")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts").isArray())
                    .andExpect(jsonPath("$.totalCount").isNumber())
                    .andExpect(jsonPath("$.unreadCount").isNumber());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/threat/audio-result")
    class AudioResult {

        @Test
        @DisplayName("should process audio analysis result with distress detected")
        void shouldProcessAudioResultWithDistress() throws Exception {
            String request = """
                    {
                        "hasDistress": true,
                        "threatLevel": "high",
                        "confidence": 0.85,
                        "method": "ambient_audio_monitor"
                    }
                    """;

            mockMvc.perform(post("/api/v1/threat/audio-result")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.created").value(true))
                    .andExpect(jsonPath("$.alertId").isString())
                    .andExpect(jsonPath("$.alert.type").value("ambient_audio"))
                    .andExpect(jsonPath("$.alert.severity").value("high"));
        }

        @Test
        @DisplayName("should return created=false when no distress detected")
        void shouldReturnNotCreatedWhenNoDistress() throws Exception {
            String request = """
                    {
                        "hasDistress": false,
                        "threatLevel": "low",
                        "confidence": 0.0
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
