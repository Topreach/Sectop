package com.dangeremergence.controller;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.service.SOSAlertService;
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

@WebMvcTest(value = SOSAlertController.class, excludeAutoConfiguration = {org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration.class, org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration.class})
class SOSAlertControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private SOSAlertService alertService;

    private SOSAlert testAlert;
    private static final String ALERT_ID = "alert-123";
    private static final String USER_ID = "user-123";

    @BeforeEach
    void setUp() {
        testAlert = new SOSAlert();
        testAlert.setId(ALERT_ID);
        testAlert.setUser(null);
        testAlert.setAlertType("fire");
        testAlert.setDescription("Fire at market");
        testAlert.setLatitude(6.5244);
        testAlert.setLongitude(3.3792);
        testAlert.setPriority(5);
        testAlert.setStatus(SOSAlert.AlertStatus.active);
        testAlert.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class CreateAlert {

        @Test
        void shouldCreateAlertSuccessfully() throws Exception {
            when(alertService.createAlert(
                    eq(USER_ID), eq("fire"), eq("Fire at market"),
                    eq(6.5244), eq(3.3792), eq(10.0), eq(5),
                    eq(false), eq(false)
            )).thenReturn(testAlert);

            Map<String, Object> request = Map.of(
                    "user_id", USER_ID,
                    "alert_type", "fire",
                    "description", "Fire at market",
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "accuracy", 10.0,
                    "priority", 5
            );

            mockMvc.perform(post("/api/v1/alerts")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(ALERT_ID))
                    .andExpect(jsonPath("$.alertType").value("fire"))
                    .andExpect(jsonPath("$.status").value("active"));
        }

        @Test
        void shouldCreateCovertAlert() throws Exception {
            when(alertService.createAlert(
                    eq(USER_ID), eq("fire"), eq("Covert alert"),
                    eq(6.5244), eq(3.3792), isNull(), eq(3),
                    eq(false), eq(true)
            )).thenReturn(testAlert);

            Map<String, Object> request = Map.of(
                    "user_id", USER_ID,
                    "alert_type", "fire",
                    "description", "Covert alert",
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "is_covert", true
            );

            mockMvc.perform(post("/api/v1/alerts")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk());
        }

        @Test
        void shouldCreateSilentAlert() throws Exception {
            when(alertService.createAlert(
                    eq(USER_ID), eq("fire"), eq("Silent alert"),
                    eq(6.5244), eq(3.3792), isNull(), eq(3),
                    eq(true), eq(false)
            )).thenReturn(testAlert);

            Map<String, Object> request = Map.of(
                    "user_id", USER_ID,
                    "alert_type", "fire",
                    "description", "Silent alert",
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "is_silent", true
            );

            mockMvc.perform(post("/api/v1/alerts")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class GetAlerts {

        @Test
        void shouldGetActiveAlerts() throws Exception {
            when(alertService.getActiveAlerts()).thenReturn(List.of(testAlert));

            mockMvc.perform(get("/api/v1/alerts/active"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts[0].id").value(ALERT_ID));
        }

        @Test
        void shouldGetAlertsForUser() throws Exception {
            when(alertService.getAlertsForUser(USER_ID)).thenReturn(List.of(testAlert));

            mockMvc.perform(get("/api/v1/alerts/user/{userId}", USER_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts[0].id").value(ALERT_ID));
        }

        @Test
        void shouldGetAlertsInArea() throws Exception {
            when(alertService.getAlertsInArea(eq(6.5), eq(3.3), eq(5.0)))
                    .thenReturn(List.of(testAlert));

            mockMvc.perform(get("/api/v1/alerts/nearby")
                            .param("latitude", "6.5")
                            .param("longitude", "3.3")
                            .param("radiusKm", "5.0"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts[0].id").value(ALERT_ID));
        }

        @Test
        void shouldGetAlertsSince() throws Exception {
            when(alertService.getAlertsSince(any(LocalDateTime.class)))
                    .thenReturn(List.of(testAlert));

            mockMvc.perform(get("/api/v1/alerts/sync")
                            .param("since", "2024-01-01T00:00:00"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.alerts[0].id").value(ALERT_ID));
        }

        @Test
        void shouldGetAlertCount() throws Exception {
            when(alertService.getActiveAlertCount()).thenReturn(5L);

            mockMvc.perform(get("/api/v1/alerts/count"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.count").value(5));
        }
    }

    @Nested
    class AcknowledgeAlert {

        @Test
        void shouldAcknowledgeAlert() throws Exception {
            when(alertService.acknowledgeAlert(ALERT_ID, "responder-1"))
                    .thenReturn(testAlert);

            Map<String, String> request = Map.of("responder_id", "responder-1");

            mockMvc.perform(post("/api/v1/alerts/{alertId}/acknowledge", ALERT_ID)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(ALERT_ID));
        }
    }

    @Nested
    class ResolveAlert {

        @Test
        void shouldResolveAlert() throws Exception {
            when(alertService.resolveAlert(ALERT_ID)).thenReturn(testAlert);

            mockMvc.perform(post("/api/v1/alerts/{alertId}/resolve", ALERT_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(ALERT_ID));
        }
    }
}
