package com.dangeremergence.controller;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = DigitalTwinController.class, excludeAutoConfiguration = {org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration.class, org.springframework.boot.autoconfigure.security.servlet.SecurityFilterAutoConfiguration.class})
class DigitalTwinControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Nested
    @DisplayName("GET /api/v1/digital-twin/cities/{cityId}/tileset")
    class GetCityTileset {

        @Test
        @DisplayName("should return tileset for a city")
        void shouldReturnCityTileset() throws Exception {
            mockMvc.perform(get("/api/v1/digital-twin/cities/lagos/tileset"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.cityId").value("lagos"))
                    .andExpect(jsonPath("$.tilesetUrl").isString())
                    .andExpect(jsonPath("$.center").isMap())
                    .andExpect(jsonPath("$.zoom").isNumber());
        }
    }

    @Nested
    @DisplayName("GET /api/v1/digital-twin/cities/{cityId}/buildings")
    class GetBuildings {

        @Test
        @DisplayName("should return buildings for a city")
        void shouldReturnBuildings() throws Exception {
            mockMvc.perform(get("/api/v1/digital-twin/cities/lagos/buildings"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.cityId").value("lagos"))
                    .andExpect(jsonPath("$.buildings").isArray())
                    .andExpect(jsonPath("$.count").isNumber());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/digital-twin/predict-propagation")
    class PredictPropagation {

        @Test
        @DisplayName("should predict hazard propagation")
        void shouldPredictPropagation() throws Exception {
            String request = """
                    {
                        "cityId": "lagos",
                        "hazardType": "fire",
                        "originLat": 6.5244,
                        "originLng": 3.3792,
                        "windSpeed": 15,
                        "windDirection": 180
                    }
                    """;

            mockMvc.perform(post("/api/v1/digital-twin/predict-propagation")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.propagationCells").isArray())
                    .andExpect(jsonPath("$.buildingsAtRisk").isArray())
                    .andExpect(jsonPath("$.evacuationPlan").isMap())
                    .andExpect(jsonPath("$.hazardType").value("fire"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/digital-twin/evacuation-plan")
    class GetEvacuationPlan {

        @Test
        @DisplayName("should return evacuation plan for a location")
        void shouldReturnEvacuationPlan() throws Exception {
            String request = """
                    {
                        "latitude": 6.5244,
                        "longitude": 3.3792
                    }
                    """;

            mockMvc.perform(post("/api/v1/digital-twin/evacuation-plan")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.originLat").value(6.5244))
                    .andExpect(jsonPath("$.originLng").value(3.3792))
                    .andExpect(jsonPath("$.safeZones").isArray())
                    .andExpect(jsonPath("$.evacuationFeasible").isBoolean());
        }
    }
}
