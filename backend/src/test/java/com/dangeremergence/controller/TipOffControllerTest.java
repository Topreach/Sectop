import com.dangeremergence.model.TipOff;
import com.dangeremergence.service.TipOffService;
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
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(value = TipOffController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
@WebMvcTest(value = TipOffController.class)
@AutoConfigureMockMvc(addFilters = false)
class TipOffControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private TipOffService tipOffService;

    private TipOff testTipOff;
    private static final String TIP_ID = "tip-123";

    private Authentication coordinatorAuth;

    @BeforeEach
    void setUp() {
        coordinatorAuth = new UsernamePasswordAuthenticationToken("coordinator-123", null,
                List.of(new SimpleGrantedAuthority("coordinator")));

        testTipOff = new TipOff();
        testTipOff.setId(TIP_ID);
        testTipOff.setTipType(TipOff.TipType.suspicious_person);
        testTipOff.setDescription("Suspicious package at market");
        testTipOff.setLatitude(6.5244);
        testTipOff.setLongitude(3.3792);
        testTipOff.setAnonymous(true);
        testTipOff.setStatus(TipOff.TipStatus.pending);
        testTipOff.setCreatedAt(LocalDateTime.now());
    }

    @Nested
    class SubmitTip {

        @Test
        void shouldSubmitTipSuccessfully() throws Exception {
            when(tipOffService.submitTip(
                    eq("suspicious_activity"), eq("Suspicious package"),
                    eq(6.5244), eq(3.3792), isNull(),
                    isNull(), isNull(), isNull(),
                    eq(true), isNull()
            )).thenReturn(testTipOff);

            Map<String, Object> request = Map.of(
                    "tipType", "suspicious_activity",
                    "description", "Suspicious package",
                    "latitude", 6.5244,
                    "longitude", 3.3792
            );

            mockMvc.perform(post("/api/v1/tips")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(TIP_ID))
                    .andExpect(jsonPath("$.tipType").value("suspicious_person"));
        }

        @Test
        void shouldSubmitTipWithReporterId() throws Exception {
            when(tipOffService.submitTip(
                    eq("theft"), eq("Stolen item"),
                    isNull(), isNull(), isNull(),
                    isNull(), isNull(), isNull(),
                    eq(false), eq("reporter-1")
            )).thenReturn(testTipOff);

            Map<String, Object> request = Map.of(
                    "tipType", "theft",
                    "description", "Stolen item",
                    "anonymous", false,
                    "reporterId", "reporter-1"
            );

            mockMvc.perform(post("/api/v1/tips")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request)))
                    .andExpect(status().isOk());
        }
    }

    @Nested
    class GetTips {

        @Test
        void shouldGetPendingTips() throws Exception {
            when(tipOffService.getPendingTips()).thenReturn(List.of(testTipOff));

            mockMvc.perform(get("/api/v1/tips/pending")
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(TIP_ID));
        }

        @Test
        void shouldGetRecentTips() throws Exception {
            when(tipOffService.getRecentTips()).thenReturn(List.of(testTipOff));

            mockMvc.perform(get("/api/v1/tips/recent"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].id").value(TIP_ID));
        }

        @Test
        void shouldGetTipById() throws Exception {
            when(tipOffService.getTipById(TIP_ID)).thenReturn(Optional.of(testTipOff));

            mockMvc.perform(get("/api/v1/tips/{id}", TIP_ID))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(TIP_ID));
        }

        @Test
        void shouldReturn404WhenTipNotFound() throws Exception {
            when(tipOffService.getTipById("unknown")).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/v1/tips/{id}", "unknown"))
                    .andExpect(status().isNotFound());
        }

        @Test
        void shouldGetStatistics() throws Exception {
            Map<String, Object> stats = Map.of(
                    "total", 50,
                    "pending", 20,
                    "reviewed", 30
            );
            when(tipOffService.getStatistics()).thenReturn(stats);

            mockMvc.perform(get("/api/v1/tips/stats")
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.total").value(50));
        }
    }

    @Nested
    class ReviewTip {

        @Test
        void shouldReviewTip() throws Exception {
            when(tipOffService.reviewTip(
                    eq(TIP_ID), eq("reviewer-1"), eq("verified"), eq("Tip confirmed")
            )).thenReturn(testTipOff);

            Map<String, Object> request = Map.of(
                    "reviewerId", "reviewer-1",
                    "status", "verified",
                    "notes", "Tip confirmed"
            );

            mockMvc.perform(post("/api/v1/tips/{id}/review", TIP_ID)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(request))
                            .with(authentication(coordinatorAuth)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(TIP_ID));
        }
    }
}
