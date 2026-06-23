package com.dangeremergence.controller;

import com.dangeremergence.model.Incident;
import com.dangeremergence.service.IncidentService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = IncidentController.class)
@AutoConfigureMockMvc(addFilters = false)
class IncidentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private IncidentService incidentService;

    private Incident testIncident;
    private static final String INCIDENT_ID = "inc-123";
    private static final String REPORTER_ID = "user-123";

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
        testIncident = new Incident();
        testIncident.setId(INCIDENT_ID);
        testIncident.setReporter(null);
        testIncident.setIncidentType("kidnapping");
        testIncident.setDescription("Suspicious activity reported");
        testIncident.setLatitude(6.5244);
        testIncident.setLongitude(3.3792);
        testIncident.setSeverity(Incident.IncidentSeverity.high);
        testIncident.setOccurredAt(LocalDateTime.now());
    }

    @Nested
    class ReportIncident {

        @Test
        void shouldReportIncident() throws Exception {
            when(incidentService.reportIncident(anyString(), anyString(), anyString(), anyDouble(),
                    anyDouble(), anyString(), any(), anyString()))
                    .thenReturn(testIncident);

            String request = """
                    {
                        "incidentType": "kidnapping",
                        "description": "Suspicious activity reported",
                        "latitude": 6.5244,
                        "longitude": 3.3792,
                        "severity": "high"
                    }
                    """;

            mockMvc.perform(post("/api/v1/incidents")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value(INCIDENT_ID))
                    .andExpect(jsonPath("$.incidentType").value("kidnapping"));
        }

        @Test
        void shouldReturn400WhenRequiredFieldsMissing() throws Exception {
            String request = """
                    {
                        "description": "Suspicious activity reported"
                    }
                    """;

            mockMvc.perform(post("/api/v1/incidents")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }

        @Test
        void shouldReturn400WhenCoordinatesInvalid() throws Exception {
            String request = """
                    {
                        "incidentType": "kidnapping",
                        "description": "Test",
                        "latitude": 100,
                        "longitude": 200,
                        "severity": "high"
                    }
                    """;

            mockMvc.perform(post("/api/v1/incidents")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    class GetIncidents {

        @Test
        void shouldReturnNearbyIncidents() throws Exception {
            when(incidentService.getIncidentsNearby(anyDouble(), anyDouble(), anyDouble()))
                    .thenReturn(List.of(testIncident));

            mockMvc.perform(get("/api/v1/incidents/nearby")
                            .with(authentication(testAuth))
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(INCIDENT_ID));
        }

        @Test
        void shouldReturnIncidentById() throws Exception {
            when(incidentService.getIncidentById(INCIDENT_ID)).thenReturn(testIncident);

            mockMvc.perform(get("/api/v1/incidents/" + INCIDENT_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(INCIDENT_ID));
        }

        @Test
        void shouldReturn404WhenIncidentNotFound() throws Exception {
            when(incidentService.getIncidentById("nonexistent")).thenThrow(new RuntimeException("Not found"));

            mockMvc.perform(get("/api/v1/incidents/nonexistent")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound());
        }

        @Test
        void shouldReturnIncidentStats() throws Exception {
            when(incidentService.getIncidentStats()).thenReturn(Map.of("total", 10, "active", 5));

            mockMvc.perform(get("/api/v1/incidents/stats")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.total").value(10));
        }
    }

    @Nested
    class VerifyIncident {

        @Test
        void shouldVerifyIncident() throws Exception {
            when(incidentService.verifyIncident(INCIDENT_ID, REPORTER_ID)).thenReturn(testIncident);

            mockMvc.perform(post("/api/v1/incidents/" + INCIDENT_ID + "/verify")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(INCIDENT_ID));
        }
    }

    @Nested
    class UpvoteIncident {

        @Test
        void shouldUpvoteIncident() throws Exception {
            when(incidentService.upvoteIncident(INCIDENT_ID, REPORTER_ID)).thenReturn(Map.of("upvotes", 5));

            mockMvc.perform(post("/api/v1/incidents/" + INCIDENT_ID + "/upvote")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.upvotes").value(5));
        }
    }
}
