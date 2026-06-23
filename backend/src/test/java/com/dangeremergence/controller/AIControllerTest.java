package com.dangeremergence.controller;

import com.dangeremergence.config.JwtAuthenticationFilter;
import com.dangeremergence.service.MessageService;
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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = AIController.class, excludeAutoConfiguration = SecurityAutoConfiguration.class)
@AutoConfigureMockMvc(addFilters = false)
class AIControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private MessageService messageService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @Nested
    @DisplayName("POST /api/v1/ai/analyze-message")
    class AnalyzeMessage {

        @Test
        @DisplayName("should analyze text with rule-based fallback when ML service unavailable")
        void shouldAnalyzeTextWithRuleBasedFallback() throws Exception {
            String request = """
                    {
                        "text": "Help! There is an emergency kidnapping happening right now!",
                        "userId": "user_001"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/analyze-message")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.priority").isString())
                    .andExpect(jsonPath("$.confidence").isNumber())
                    .andExpect(jsonPath("$.method").value("rule_based"));
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": "",
                        "userId": "user_001"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/analyze-message")
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
                        "userId": "user_001"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/analyze-message")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/prioritize")
    class Prioritize {

        @Test
        @DisplayName("should prioritize text with rule-based fallback")
        void shouldPrioritizeTextWithRuleBasedFallback() throws Exception {
            String request = """
                    {
                        "text": "bomb threat at the market"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/prioritize")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.priority").isString())
                    .andExpect(jsonPath("$.method").value("rule_based"));
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/prioritize")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/prioritize-batch")
    class PrioritizeBatch {

        @Test
        @DisplayName("should prioritize multiple texts")
        void shouldPrioritizeBatch() throws Exception {
            String request = """
                    {
                        "texts": ["Help me please", "Normal conversation"]
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/prioritize-batch")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.results").isArray());
        }
    }
}
