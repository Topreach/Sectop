package com.dangeremergence.controller;

import com.dangeremergence.service.MessageService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AIController.class)
@AutoConfigureMockMvc(addFilters = false)
class AIControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private MessageService messageService;

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
                        "messages": [
                            {"id": "msg_001", "text": "Help me please"},
                            {"id": "msg_002", "text": "Normal conversation"}
                        ]
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/prioritize-batch")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.results").isArray());
        }

        @Test
        @DisplayName("should return 400 when messages list is empty")
        void shouldReturn400WhenMessagesEmpty() throws Exception {
            String request = """
                    {
                        "messages": []
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/prioritize-batch")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("messages list is required"));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/ai/health")
    class Health {

        @Test
        @DisplayName("should return health status")
        void shouldReturnHealth() throws Exception {
            mockMvc.perform(get("/api/v1/ai/health"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("connected"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/classify")
    class Classify {

        @Test
        @DisplayName("should classify text")
        void shouldClassifyText() throws Exception {
            String request = """
                    {
                        "text": "flood in Lagos",
                        "categories": ["flood", "fire", "accident", "crime"]
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/classify")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.category").isString())
                    .andExpect(jsonPath("$.confidence").isNumber());
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/classify")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/summarize")
    class Summarize {

        @Test
        @DisplayName("should summarize text")
        void shouldSummarizeText() throws Exception {
            String request = """
                    {
                        "text": "There has been a major flood in Lagos affecting thousands of residents. Emergency services have been deployed to the affected areas. The government has issued a evacuation order for residents living close to the lagoon."
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/summarize")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.summary").isString());
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/summarize")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/translate")
    class Translate {

        @Test
        @DisplayName("should translate text")
        void shouldTranslateText() throws Exception {
            String request = """
                    {
                        "text": "Help! There is an emergency",
                        "targetLanguage": "ha",
                        "sourceLanguage": "en"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/translate")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.translatedText").isString())
                    .andExpect(jsonPath("$.targetLanguage").value("ha"));
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": "",
                        "targetLanguage": "ha"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/translate")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/extract-location")
    class ExtractLocation {

        @Test
        @DisplayName("should extract location from text")
        void shouldExtractLocation() throws Exception {
            String request = """
                    {
                        "text": "There is a fire at the market in Ikeja, Lagos"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/extract-location")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.locations").isArray());
        }

        @Test
        @DisplayName("should return 400 when text is blank")
        void shouldReturn400WhenTextBlank() throws Exception {
            String request = """
                    {
                        "text": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/extract-location")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("text is required"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/ai/suggest-response")
    class SuggestResponse {

        @Test
        @DisplayName("should suggest a response")
        void shouldSuggestResponse() throws Exception {
            String request = """
                    {
                        "message": "There is a flood in my area",
                        "context": "emergency"
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/suggest-response")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.suggestedResponse").isString());
        }

        @Test
        @DisplayName("should return 400 when message is blank")
        void shouldReturn400WhenMessageBlank() throws Exception {
            String request = """
                    {
                        "message": ""
                    }
                    """;

            mockMvc.perform(post("/api/v1/ai/suggest-response")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("message is required"));
        }
    }
}
