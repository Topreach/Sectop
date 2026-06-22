package com.dangeremergence.controller;

import com.dangeremergence.model.Incident;
import com.dangeremergence.service.IncidentService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(IncidentController.class)
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

    @BeforeEach
    void setUp() {
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
        void shouldReportIncidentSuccessfully() throws Exception {
            when(incidentService.createIncident(
                    eq(REPORTER_ID), eq("kidnapping"), eq("Suspicious activity"),
                    eq(6.5244), eq(3.3792), isNull(),
                    any(LocalDateTime.class), eq("high"), eq(false)
            )).thenReturn(testIncident);

            Map<String, Object> request = Map.of(
                    "reporterId", REPORTER_ID,
                    "incidentType", "kidnapping",
                    "description", "Suspicious activity",
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "severity", "high"
            );

            mockMvc.perform(post("/api/v1/incidents")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.incident.id").value(INCIDENT_ID))
                    .andExpect(jsonPath("$.message").value("Incident reported successfully"));
        }

        @Test
        void shouldReturn400WhenIncidentTypeMissing() throws Exception {
            Map<String, Object> request = Map.of(
                    "latitude", 6.5244,
                    "longitude", 3.3792
            );

            mockMvc.perform(post("/api/v1/incidents")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("incidentType is required"));
        }

        @Test
        void shouldReturn400WhenCoordinatesMissing() throws Exception {
            Map<String, Object> request = Map.of(
                    "incidentType", "kidnapping"
            );

            mockMvc.perform(post("/api/v1/incidents")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("latitude and longitude are required"));
        }

        @Test
        void shouldReportAnonymousIncident() throws Exception {
            when(incidentService.createIncident(
                    isNull(), eq("suspicious"), eq("Anonymous report"),
                    eq(6.5), eq(3.3), eq(5.0),
                    any(LocalDateTime.class), eq("medium"), eq(true)
            )).thenReturn(testIncident);

            Map<String, Object> request = Map.of(
                    "incidentType", "suspicious",
                    "description", "Anonymous report",
                    "latitude", 6.5,
                    "longitude", 3.3,
                    "accuracy", 5.0,
                    "isAnonymous", true
            );

            mockMvc.perform(post("/api/v1/incidents")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class GetIncidents {

        @Test
        void shouldGetNearbyIncidents() throws Exception {
            when(incidentService.getNearbyIncidents(eq(6.5), eq(3.3), eq(10.0), isNull()))
                    .thenReturn(List.of(testIncident));

            mockMvc.perform(get("/api/v1/incidents/nearby")
                            .param("latitude", "6.5")
                            .param("longitude", "3.3")
                            .param("radiusKm", "10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.incidents[0].id").value(INCIDENT_ID))
                    .andExpect(jsonPath("$.count").value(1));
        }

        @Test
        void shouldGetHeatmapData() throws Exception {
            List<Map<String, Object>> heatmap = List.of(
                    Map.of("lat", 6.5, "lng", 3.3, "count", 5)
            );
            when(incidentService.getHeatmapData(
                    eq(6.5), eq(3.3), eq(20.0), any(LocalDateTime.class)
            )).thenReturn(heatmap);

            mockMvc.perform(get("/api/v1/incidents/heatmap")
                            .param("latitude", "6.5")
                            .param("longitude", "3.3")
                            .param("radiusKm", "20")
                            .param("since", "2024-01-01T00:00:00"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.heatmap[0].count").value(5));
        }

        @Test
        void shouldGetIncidentById() throws Exception {
            mockMvc.perform(get("/api/v1/incidents/{id}", INCIDENT_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.incidentId").value(INCIDENT_ID));
        }

        @Test
        void shouldGetStatistics() throws Exception {
            Map<String, Object> stats = Map.of(
                    "total", 100,
                    "active", 50,
                    "resolved", 50
            );
            when(incidentService.getStatistics()).thenReturn(stats);

            mockMvc.perform(get("/api/v1/incidents/stats"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.total").value(100));
        }
    }

    @Nested
    class VerifyIncident {

        @Test
        void shouldVerifyIncident() throws Exception {
            when(incidentService.verifyIncident(INCIDENT_ID, "authority-1"))
                    .thenReturn(testIncident);

            Map<String, Object> request = Map.of("verifiedBy", "authority-1");

            mockMvc.perform(post("/api/v1/incidents/{id}/verify", INCIDENT_ID)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.incident.id").value(INCIDENT_ID))
                    .andExpect(jsonPath("$.message").value("Incident verified successfully"));
        }
    }

    @Nested
    class UpvoteIncident {

        @Test
        void shouldUpvoteIncident() throws Exception {
            when(incidentService.upvoteIncident(INCIDENT_ID))
                    .thenReturn(testIncident);

            mockMvc.perform(post("/api/v1/incidents/{id}/upvote", INCIDENT_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.incident.id").value(INCIDENT_ID))
                    .andExpect(jsonPath("$.message").value("Incident upvoted"));
        }
    }
}
