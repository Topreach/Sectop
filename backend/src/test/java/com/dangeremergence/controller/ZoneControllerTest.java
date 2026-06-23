import com.dangeremergence.model.Zone;
import com.dangeremergence.service.ZoneService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
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

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = ZoneController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class ZoneControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private ZoneService zoneService;

    private Zone testZone;
    private static final String ZONE_ID = "zone-123";

    private Authentication testAuth;

    @BeforeEach
    void setUp() {
        testAuth = new UsernamePasswordAuthenticationToken("user-123", null, List.of());

        testZone = new Zone();
        testZone.setId(ZONE_ID);
        testZone.setName("Lagos Danger Zone");
        testZone.setType(Zone.ZoneType.hazard);
        testZone.setDescription("High risk area in Lagos");
        testZone.setLatitude(6.5244);
        testZone.setLongitude(3.3792);
        testZone.setRadius(5.0);
        testZone.setSeverity("high");
        testZone.setStatus(Zone.ZoneStatus.active);
        testZone.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class CreateZone {

        @Test
        void shouldCreateZoneSuccessfully() throws Exception {
            when(zoneService.createZone(any(Zone.class))).thenReturn(testZone);

            mockMvc.perform(post("/api/v1/zones")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(testZone))
                            .with(authentication(testAuth)))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value(ZONE_ID))
                    .andExpect(jsonPath("$.name").value("Lagos Danger Zone"));
        }
    }

    @Nested
    class GetZones {

        @Test
        void shouldGetZoneById() throws Exception {
            when(zoneService.getZoneById(ZONE_ID)).thenReturn(Optional.of(testZone));

            mockMvc.perform(get("/api/v1/zones/{zoneId}", ZONE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(ZONE_ID));
        }

        @Test
        void shouldReturn404WhenZoneNotFound() throws Exception {
            when(zoneService.getZoneById("unknown")).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/zones/{zoneId}", "unknown")
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.error").value("Zone not found"));
        }

        @Test
        void shouldGetActiveZones() throws Exception {
            when(zoneService.getActiveZones()).thenReturn(List.of(testZone));

            mockMvc.perform(get("/api/v1/zones/active")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zones[0].id").value(ZONE_ID));
        }

        @Test
        void shouldGetDangerZones() throws Exception {
            when(zoneService.getDangerZones()).thenReturn(List.of(testZone));

            mockMvc.perform(get("/api/v1/zones/danger")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zones[0].id").value(ZONE_ID));
        }

        @Test
        void shouldGetRestrictedZones() throws Exception {
            when(zoneService.getRestrictedZones()).thenReturn(List.of(testZone));

            mockMvc.perform(get("/api/v1/zones/restricted")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zones[0].id").value(ZONE_ID));
        }

        @Test
        void shouldGetZonesNearby() throws Exception {
            when(zoneService.getZonesInArea(
                    eq(7.0), eq(6.0), eq(3.8), eq(2.8)
            )).thenReturn(List.of(testZone));

            mockMvc.perform(get("/api/v1/zones/nearby")
                            .param("latitude", "6.5")
                            .param("longitude", "3.3")
                            .param("radiusDegrees", "0.5")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zones[0].id").value(ZONE_ID));
        }

        @Test
        void shouldGetZonesSince() throws Exception {
            when(zoneService.getZonesSince(any(LocalDateTime.class)))
                    .thenReturn(List.of(testZone));

            mockMvc.perform(get("/api/v1/zones/sync")
                            .param("since", "2024-01-01T00:00:00")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zones[0].id").value(ZONE_ID));
        }

        @Test
        void shouldGetZoneCount() throws Exception {
            when(zoneService.getActiveZones()).thenReturn(List.of(testZone));
            when(zoneService.getDangerZones()).thenReturn(List.of(testZone));
            when(zoneService.getRestrictedZones()).thenReturn(List.of());

            mockMvc.perform(get("/api/v1/zones/count")
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.active").value(1))
                    .andExpect(jsonPath("$.danger").value(1))
                    .andExpect(jsonPath("$.restricted").value(0));
        }
    }

    @Nested
    class UpdateZone {

        @Test
        void shouldUpdateZoneSuccessfully() throws Exception {
            when(zoneService.getZoneById(ZONE_ID)).thenReturn(Optional.of(testZone));
            when(zoneService.updateZone(any(Zone.class))).thenReturn(testZone);

            Zone updateRequest = new Zone();
            updateRequest.setName("Updated Zone Name");

            mockMvc.perform(put("/api/v1/zones/{zoneId}", ZONE_ID)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(updateRequest))
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(ZONE_ID));
        }

        @Test
        void shouldReturn404WhenUpdatingNonExistentZone() throws Exception {
            when(zoneService.getZoneById("unknown")).thenReturn(Optional.empty());

            Zone updateRequest = new Zone();
            updateRequest.setName("Updated Name");

            mockMvc.perform(put("/api/v1/zones/{zoneId}", "unknown")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(updateRequest))
                            .with(authentication(testAuth)))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.error").value("Zone not found"));
        }
    }

    @Nested
    class ZoneActions {

        @Test
        void shouldActivateZone() throws Exception {
            mockMvc.perform(post("/api/v1/zones/{zoneId}/activate", ZONE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Zone activated successfully"));
        }

        @Test
        void shouldDeactivateZone() throws Exception {
            mockMvc.perform(post("/api/v1/zones/{zoneId}/deactivate", ZONE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Zone deactivated successfully"));
        }

        @Test
        void shouldExpireZone() throws Exception {
            mockMvc.perform(delete("/api/v1/zones/{zoneId}", ZONE_ID)
                            .with(authentication(testAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Zone expired successfully"));
        }
    }
}
