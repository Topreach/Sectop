package com.dangeremergence.controller;

import com.dangeremergence.service.MessageService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;

@RestController
@RequestMapping("/api/v1/ai")
public class AIController {

    private static final Logger log = LoggerFactory.getLogger(AIController.class);

    @Autowired
    private MessageService messageService;

    @Value("${ml.service.url:http://ml-service:8000}")
    private String mlServiceUrl;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    @PostMapping("/analyze-message")
    public ResponseEntity<Map<String, Object>> analyzeMessage(@RequestBody Map<String, Object> request) {
        String text = (String) request.getOrDefault("text", "");
        String userId = (String) request.getOrDefault("userId", "anonymous");

        if (text.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "text is required"));
        }

        try {
            // Try ML service first
            Map<String, Object> mlRequest = new HashMap<>();
            mlRequest.put("text", text);
            mlRequest.put("user_id", userId);

            String mlJson = objectMapper.writeValueAsString(mlRequest);
            HttpRequest mlHttpRequest = HttpRequest.newBuilder()
                    .uri(URI.create(mlServiceUrl + "/api/v1/prioritize"))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(mlJson))
                    .timeout(Duration.ofSeconds(10))
                    .build();

            HttpResponse<String> mlResponse = httpClient.send(mlHttpRequest, HttpResponse.BodyHandlers.ofString());

            if (mlResponse.statusCode() == 200) {
                JsonNode mlResult = objectMapper.readTree(mlResponse.body());
                Map<String, Object> result = new HashMap<>();
                result.put("priority", mlResult.has("priority") ? mlResult.get("priority").asText() : "low");
                result.put("confidence", mlResult.has("confidence") ? mlResult.get("confidence").asDouble() : 0.0);
                result.put("label", mlResult.has("label") ? mlResult.get("label").asText() : "unknown");
                result.put("method", "ml_service");
                result.put("inferenceTimeMs", mlResult.has("inference_time_ms") ? mlResult.get("inference_time_ms").asLong() : 0);

                List<String> reasons = new ArrayList<>();
                if (mlResult.has("reasons")) {
                    mlResult.get("reasons").forEach(r -> reasons.add(r.asText()));
                }
                result.put("reasons", reasons);

                return ResponseEntity.ok(result);
            }
        } catch (Exception e) {
            log.warn("ML service unavailable, using rule-based fallback: {}", e.getMessage());
        }

        // Rule-based fallback
        Map<String, Object> fallback = ruleBasedAnalysis(text);
        return ResponseEntity.ok(fallback);
    }

    @PostMapping("/prioritize")
    public ResponseEntity<Map<String, Object>> prioritize(@RequestBody Map<String, Object> request) {
        String text = (String) request.getOrDefault("text", "");

        if (text.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "text is required"));
        }

        try {
            String mlJson = objectMapper.writeValueAsString(Map.of("text", text));
            HttpRequest mlHttpRequest = HttpRequest.newBuilder()
                    .uri(URI.create(mlServiceUrl + "/api/v1/prioritize"))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(mlJson))
                    .timeout(Duration.ofSeconds(10))
                    .build();

            HttpResponse<String> mlResponse = httpClient.send(mlHttpRequest, HttpResponse.BodyHandlers.ofString());

            if (mlResponse.statusCode() == 200) {
                JsonNode result = objectMapper.readTree(mlResponse.body());
                return ResponseEntity.ok(Map.of(
                        "priority", result.has("priority") ? result.get("priority").asInt(0) : 0,
                        "confidence", result.has("confidence") ? result.get("confidence").asDouble(0.0) : 0.0,
                        "method", "ml_service"
                ));
            }
        } catch (Exception e) {
            log.warn("ML service unavailable for prioritize: {}", e.getMessage());
        }

        Map<String, Object> fallback = ruleBasedAnalysis(text);
        return ResponseEntity.ok(Map.of(
                "priority", "critical".equals(fallback.get("priority")) ? 3 : "high".equals(fallback.get("priority")) ? 2 : 1,
                "confidence", fallback.get("confidence"),
                "method", "rule_based"
        ));
    }

    @PostMapping("/prioritize-batch")
    public ResponseEntity<Map<String, Object>> prioritizeBatch(@RequestBody Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        List<String> texts = (List<String>) request.getOrDefault("texts", List.of());

        List<Map<String, Object>> results = new ArrayList<>();
        for (String text : texts) {
            Map<String, Object> singleRequest = new HashMap<>();
            singleRequest.put("text", text);
            ResponseEntity<Map<String, Object>> response = prioritize(singleRequest);
            results.add(response.getBody());
        }

        return ResponseEntity.ok(Map.of("results", results));
    }

    @PostMapping("/analyze-audio")
    public ResponseEntity<Map<String, Object>> analyzeAudio(@RequestBody Map<String, Object> request) {
        String base64Audio = (String) request.getOrDefault("audio", "");

        if (base64Audio.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "audio data is required"));
        }

        try {
            // In a real scenario, we would use a library like TarsosDSP or a JNI bridge to a C++ ML model.
            // Here we perform a simple energy-based distress detection placeholder.
            byte[] audioData = Base64.getDecoder().decode(base64Audio);
            
            // Calculate RMS (Root Mean Square) energy of the audio signal
            double sum = 0;
            for (byte b : audioData) {
                sum += b * b;
            }
            double rms = Math.sqrt(sum / audioData.length);
            
            // Distress signals (screams, whistles) are typically high energy and high frequency.
            // This is a simplified heuristic:
            boolean possibleDistress = rms > 40.0; // Arbitrary threshold for "loud"
            double confidence = Math.min(rms / 100.0, 0.95);

            Map<String, Object> result = new HashMap<>();
            result.put("hasDistress", possibleDistress);
            result.put("confidence", possibleDistress ? confidence : 0.1);
            result.put("rmsEnergy", rms);
            result.put("method", "heuristic_energy_analysis");
            result.put("message", possibleDistress ? "High energy audio event detected" : "Ambient audio level");

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Audio analysis failed", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to process audio data"));
        }
    }

    /**
     * Rule-based distress analysis fallback when ML service is unavailable.
     * Includes localized keywords for Nigerian security context (Hausa, Yoruba, Igbo).
     */
    private Map<String, Object> ruleBasedAnalysis(String text) {
        String lower = text.toLowerCase();
        int score = 0;
        List<String> reasons = new ArrayList<>();

        // --- Regional Keywords (Nigeria Context) ---
        // Format: {Keyword, Description, Score}
        String[][] regionalKeywords = {
            // Hausa
            {"garkuwa", "kidnapping_ha", "4"},
            {"bindiga", "gun_ha", "3"},
            {"bom", "bomb_ha", "4"},
            {"ta'addanci", "terrorism_ha", "4"},
            {"yaki", "war_ha", "3"},
            {"fashi", "robbery_ha", "3"},
            {"taimako", "help_ha", "2"},
            // Yoruba
            {"gbigbe", "kidnapping_yo", "4"},
            {"ibon", "gun_yo", "3"},
            {"panumopa", "emergency_yo", "3"},
            {"iranlowo", "help_yo", "2"},
            // Igbo
            {"atogboro", "kidnapping_ig", "4"},
            {"nkwatogbo", "terrorism_ig", "4"},
            {"egbe", "gun_ig", "3"},
            {"enyemaka", "help_ig", "2"}
        };

        for (String[] kw : regionalKeywords) {
            if (lower.contains(kw[0])) {
                score += Integer.parseInt(kw[2]);
                reasons.add("regional_kw_" + kw[1]);
            }
        }

        // --- Standard English Keywords ---
        String[] criticalKeywords = {"help", "emergency", "sos", "fire", "flood", "earthquake",
                "collapse", "trapped", "injured", "bleeding", "heart attack", "gun",
                " hostage", "bomb", "tsunami", "hurricane", "tornado", "kidnap", "terrorist"};
        for (String kw : criticalKeywords) {
            if (lower.contains(kw)) {
                score += 3;
                reasons.add("keyword_" + kw.replace(" ", "_"));
            }
        }

        // High priority keywords
        String[] highKeywords = {"danger", "urgent", "accident", "medical", "unconscious",
                "burn", "fracture", "stroke", "overdose", "drowning"};
        for (String kw : highKeywords) {
            if (lower.contains(kw)) {
                score += 2;
                reasons.add("keyword_" + kw);
            }
        }

        // Medium priority keywords
        String[] mediumKeywords = {"need", "help me", "please", "stuck", "lost", "alone",
                "scared", "dark", "cold", "hungry"};
        for (String kw : mediumKeywords) {
            if (lower.contains(kw)) {
                score += 1;
                reasons.add("keyword_" + kw.replace(" ", "_"));
            }
        }

        // Exclamation marks indicate urgency
        long exclamationCount = text.chars().filter(c -> c == '!').count();
        if (exclamationCount > 0) {
            score += (int) Math.min(exclamationCount, 3);
            reasons.add("exclamation_x" + exclamationCount);
        }

        String priority;
        if (score >= 6) {
            priority = "critical";
        } else if (score >= 4) {
            priority = "high";
        } else if (score >= 2) {
            priority = "medium";
        } else {
            priority = "low";
        }

        double confidence = Math.min(score / 10.0, 1.0);

        Map<String, Object> result = new HashMap<>();
        result.put("priority", priority);
        result.put("confidence", confidence);
        result.put("label", score >= 4 ? "distress_detected" : "normal");
        result.put("reasons", reasons);
        result.put("method", "rule_based");
        result.put("inferenceTimeMs", 0);

        return result;
    }
}
