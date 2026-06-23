package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = DroneController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class DroneControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());
    }

    @Nested
    @DisplayName("GET /api/v1/drones/available")
    class GetAvailableDrones {

        @Test
        @DisplayName("should return available drones without location filter")
        void shouldReturnAvailableDronesWithoutLocation() throws Exception {
            mockMvc.perform(get("/api/v1/drones/available")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.drones").isArray())
                    .andExpect(jsonPath("$.count").isNumber());
        }

        @Test
        @DisplayName("should return available drones with location filter")
        void shouldReturnAvailableDronesWithLocation() throws Exception {
            mockMvc.perform(get("/api/v1/drones/available")
                            .with(authentication(testAuth))
                            .param("latitude", "40.7128")
                            .param("longitude", "-74.0060"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.drones").isArray())
                    .andExpect(jsonPath("$.count").isNumber());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/drones/deploy-relay")
    class DeployRelayDrone {

        @Test
        @DisplayName("should deploy a LoRa-capable drone successfully")
        void shouldDeployRelayDrone() throws Exception {
            String request = """
                    {
                        "droneId": "drone_0",
                        "latitude": 40.7200,
                        "longitude": -74.0000
                    }
                    """;

            mockMvc.perform(post("/api/v1/drones/deploy-relay")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.droneId").value("drone_0"))
                    .andExpect(jsonPath("$.status").value("deploying"))
                    .andExpect(jsonPath("$.estimatedFlightTimeMinutes").isNumber());
        }

        @Test
        @DisplayName("should return 400 for non-existent drone")
        void shouldReturn400ForNonExistentDrone() throws Exception {
            String request = """
                    {
                        "droneId": "nonexistent",
                        "latitude": 40.7200,
                        "longitude": -74.0000
                    }
                    """;

            mockMvc.perform(post("/api/v1/drones/deploy-relay")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Drone not found: nonexistent"));
        }

        @Test
        @DisplayName("should return 400 for drone without LoRa capability")
        void shouldReturn400ForDroneWithoutLoRa() throws Exception {
            String request = """
                    {
                        "droneId": "drone_5",
                        "latitude": 40.7200,
                        "longitude": -74.0000
                    }
                    """;

            mockMvc.perform(post("/api/v1/drones/deploy-relay")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Drone does not have LoRa capability"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/drones/assess-damage")
    class AssessDamage {

        @Test
        @DisplayName("should return damage assessment for a zone")
        void shouldReturnDamageAssessment() throws Exception {
            String request = """
                    {
                        "zoneId": "zone_1",
                        "centerLat": 40.7128,
                        "centerLng": -74.0060,
                        "radiusKm": 1.0
                    }
                    """;

            mockMvc.perform(post("/api/v1/drones/assess-damage")
                            .with(authentication(testAuth))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zoneId").value("zone_1"))
                    .andExpect(jsonPath("$.damagedBuildings").isArray())
                    .andExpect(jsonPath("$.fireHotspots").isArray())
                    .andExpect(jsonPath("$.blockedRoads").isArray())
                    .andExpect(jsonPath("$.assessmentComplete").value(true))
                    .andExpect(jsonPath("$.estimatedCasualties").isNumber());
        }
    }
}
