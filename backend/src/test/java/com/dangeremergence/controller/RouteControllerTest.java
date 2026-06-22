package com.dangeremergence.controller;

import com.dangeremergence.service.RouteService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = RouteController.class, excludeAutoConfiguration = {org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration.class, org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration.class})
class RouteControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RouteService routeService;

    @Nested
    @DisplayName("POST /api/v1/routes/plan")
    class PlanSafeRoute {

        @Test
        @DisplayName("should plan a safe route between two points")
        void shouldPlanSafeRoute() throws Exception {
            Map<String, Object> route = Map.of(
                    "fromLat", 6.5244,
                    "fromLng", 3.3792,
                    "toLat", 6.6018,
                    "toLng", 3.3515,
                    "totalDistance", 12.5,
                    "estimatedDuration", 25,
                    "waypoints", java.util.List.of()
            );
            when(routeService.planSafeRoute(anyDouble(), anyDouble(), anyDouble(), anyDouble(), anyBoolean(), anyBoolean()))
                    .thenReturn(route);

            String request = """
                    {
                        "fromLat": 6.5244,
                        "fromLng": 3.3792,
                        "toLat": 6.6018,
                        "toLng": 3.3515,
                        "avoidHighways": false,
                        "preferLitRoads": true
                    }
                    """;

            mockMvc.perform(post("/api/v1/routes/plan")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.fromLat").value(6.5244))
                    .andExpect(jsonPath("$.toLat").value(6.6018));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/routes/danger-score")
    class GetDangerScore {

        @Test
        @DisplayName("should return danger score for a location")
        void shouldReturnDangerScore() throws Exception {
            Map<String, Object> score = Map.of(
                    "latitude", 6.5244,
                    "longitude", 3.3792,
                    "dangerScore", 0.35,
                    "dangerLevel", "medium",
                    "nearbyIncidents", 3
            );
            when(routeService.getDangerScore(anyDouble(), anyDouble(), anyDouble())).thenReturn(score);

            mockMvc.perform(get("/api/v1/routes/danger-score")
                            .param("latitude", "6.5244")
                            .param("longitude", "3.3792")
                            .param("radiusKm", "5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.dangerScore").value(0.35))
                    .andExpect(jsonPath("$.dangerLevel").value("medium"));
        }
    }
}
