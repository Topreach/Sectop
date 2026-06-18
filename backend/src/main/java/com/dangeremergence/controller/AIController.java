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

    @Value("${ml.service.api-key:}")
    private String mlApiKey;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    /** Priority label strings indexed by ML service integer priority (0-3). */
    private static final String[] PRIORITY_LABELS = {"low", "medium", "high", "critical"};

    /**
     * Build an HttpRequest with optional ML API key auth header.
     */
    private HttpRequest.Builder mlRequestBuilder(String path) {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(mlServiceUrl + path))
                .header("Content-Type", "application/json")
                .timeout(Duration.ofSeconds(10));
        if (mlApiKey != null && !mlApiKey.isBlank()) {
            builder.header("Authorization", "ApiKey " + mlApiKey);
        }
        return builder;
    }

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
            HttpRequest mlHttpRequest = mlRequestBuilder("/api/v1/prioritize")
                    .POST(HttpRequest.BodyPublishers.ofString(mlJson))
                    .build();

            HttpResponse<String> mlResponse = httpClient.send(mlHttpRequest, HttpResponse.BodyHandlers.ofString());

            if (mlResponse.statusCode() == 200) {
                JsonNode mlResult = objectMapper.readTree(mlResponse.body());
                Map<String, Object> result = new HashMap<>();

                // ML service returns priority as int (0-3), map to string label
                int priorityInt = mlResult.has("priority") ? mlResult.get("priority").asInt(0) : 0;
                String priorityStr = (priorityInt >= 0 && priorityInt < PRIORITY_LABELS.length)
                        ? PRIORITY_LABELS[priorityInt] : "low";
                result.put("priority", priorityStr);
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
            HttpRequest mlHttpRequest = mlRequestBuilder("/api/v1/prioritize")
                    .POST(HttpRequest.BodyPublishers.ofString(mlJson))
                    .build();

            HttpResponse<String> mlResponse = httpClient.send(mlHttpRequest, HttpResponse.BodyHandlers.ofString());

            if (mlResponse.statusCode() == 200) {
                JsonNode result = objectMapper.readTree(mlResponse.body());
                int priorityInt = result.has("priority") ? result.get("priority").asInt(0) : 0;
                String priorityStr = (priorityInt >= 0 && priorityInt < PRIORITY_LABELS.length)
                        ? PRIORITY_LABELS[priorityInt] : "low";
                return ResponseEntity.ok(Map.of(
                        "priority", priorityStr,
                        "confidence", result.has("confidence") ? result.get("confidence").asDouble(0.0) : 0.0,
                        "method", "ml_service"
                ));
            }
        } catch (Exception e) {
            log.warn("ML service unavailable for prioritize: {}", e.getMessage());
        }

        Map<String, Object> fallback = ruleBasedAnalysis(text);
        return ResponseEntity.ok(Map.of(
                "priority", fallback.get("priority"),
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
        String transcript = (String) request.getOrDefault("transcript", ""); // Optional speech-to-text transcript

        if (base64Audio.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "audio data is required"));
        }

        byte[] audioData;
        try {
            audioData = Base64.getDecoder().decode(base64Audio);
        } catch (IllegalArgumentException e) {
            log.warn("Audio analysis: Invalid Base64 audio data: {}", e.getMessage());
            // Graceful fallback — return a non-distress result instead of 500
            Map<String, Object> fallback = new HashMap<>();
            fallback.put("hasDistress", false);
            fallback.put("threatLevel", "low");
            fallback.put("confidence", 0.0);
            fallback.put("rmsEnergy", 0.0);
            fallback.put("method", "fallback_invalid_base64");
            fallback.put("message", "Unable to decode audio data");
            fallback.put("audioThreatScore", 0);
            fallback.put("audioThreatReasons", List.of());
            fallback.put("fulaniDialectDetected", false);
            fallback.put("hasTranscript", transcript != null && !transcript.isBlank());
            // If a transcript is provided, still run keyword analysis on it
            if (transcript != null && !transcript.isBlank()) {
                Map<String, Object> keywordResult = ruleBasedAnalysis(transcript);
                fallback.put("hasDistress", "high".equals(keywordResult.get("priority")) || "critical".equals(keywordResult.get("priority")));
                fallback.put("threatLevel", keywordResult.get("priority"));
                fallback.put("confidence", Math.max(0.0, (Double) keywordResult.getOrDefault("confidence", 0.0)));
                fallback.put("method", "transcript_keyword_fallback");
                fallback.put("message", "Transcript keyword analysis — audio decode failed");
            }
            return ResponseEntity.ok(fallback);
        }

        try {
            
            // Calculate RMS (Root Mean Square) energy of the audio signal
            double sum = 0;
            for (byte b : audioData) {
                sum += b * b;
            }
            double rms = Math.sqrt(sum / audioData.length);
            
            // Distress signals (screams, whistles) are typically high energy and high frequency.
            boolean possibleDistress = rms > 40.0;
            double confidence = Math.min(rms / 100.0, 0.95);

            // --- Hausa/Fulani Audio Keyword Spotting ---
            // If a transcript is provided (from on-device or server-side STT), scan it for threat keywords
            List<String> audioThreatReasons = new ArrayList<>();
            int audioThreatScore = 0;
            boolean fulaniDialectDetected = false;

            if (transcript != null && !transcript.isBlank()) {
                String lowerTranscript = transcript.toLowerCase();

                // Hausa/Fulani threat keywords commonly used by bandits/terrorists
                String[][] hausaFulaniKeywords = {
                    // Fulani/Hausa banditry & terrorism keywords
                    {"fulani", "fulani_mention", "3"},
                    {"bindiga", "gun_ha_audio", "3"},
                    {"harbi", "shoot_ha_audio", "4"},
                    {"kashe", "kill_ha_audio", "4"},
                    {"ta'addanci", "terrorism_ha_audio", "4"},
                    {"yaki", "war_ha_audio", "3"},
                    {"gani", "see_ha_audio", "1"},
                    {"garkuwa", "kidnapping_ha_audio", "4"},
                    {"fashi", "robbery_ha_audio", "3"},
                    {"bom", "bomb_ha_audio", "4"},
                    {"wuta", "fire_ha_audio", "3"},
                    {"makami", "weapon_ha_audio", "3"},
                    {"maharbi", "shooter_ha_audio", "4"},
                    {"barawon", "thief_ha_audio", "2"},
                    {"'yan fashi", "bandits_ha_audio", "4"},
                    {"'yan ta'adda", "terrorists_ha_audio", "4"},
                    {"doki", "horse_ha_audio", "2"},  // bandits often use horses
                    {"dare", "night_ha_audio", "2"},   // night attacks
                    {"mahaukata", "mad_ones_ha_audio", "3"},
                    {"suna zuwa", "they_are_coming_ha_audio", "3"},
                    {"a gudu", "run_away_ha_audio", "2"},
                    {"taimako", "help_ha_audio", "2"},
                    // Fulfulde/Fulani specific
                    {"ballal", "help_ful_audio", "2"},
                    {"war", "war_ful_audio", "3"},
                    {"maayo", "river_ful_audio", "1"},
                    {"nyifta", "hide_ful_audio", "2"},
                    {"dembal", "tomorrow_ful_audio", "1"},
                    {"fijo", "attack_ful_audio", "4"},
                    {"jam", "peace_ful_audio", "1"},
                    {"nyaw", "sickness_ful_audio", "2"},
                };

                for (String[] kw : hausaFulaniKeywords) {
                    if (lowerTranscript.contains(kw[0])) {
                        audioThreatScore += Integer.parseInt(kw[2]);
                        audioThreatReasons.add("audio_kw_" + kw[1]);
                        if (kw[0].equals("fulani") || kw[0].equals("'yan fashi") || kw[0].equals("'yan ta'adda")) {
                            fulaniDialectDetected = true;
                        }
                    }
                }

                // Also scan for English threat keywords in transcript
                String[] englishAudioThreats = {"help", "emergency", "gun", "shoot", "kill", "attack",
                        "terrorist", "kidnap", "hostage", "bomb", "run", "danger", "hide"};
                for (String kw : englishAudioThreats) {
                    if (lowerTranscript.contains(kw)) {
                        audioThreatScore += 2;
                        audioThreatReasons.add("audio_kw_en_" + kw);
                    }
                }
            }

            // Combine energy analysis with keyword analysis
            boolean hasThreat = possibleDistress || audioThreatScore >= 3;
            double combinedConfidence;
            if (audioThreatScore >= 6) {
                combinedConfidence = Math.min(0.98, 0.5 + (audioThreatScore / 10.0));
            } else if (possibleDistress) {
                combinedConfidence = confidence;
            } else {
                combinedConfidence = Math.min(0.5, audioThreatScore / 10.0);
            }

            String threatLevel;
            if (audioThreatScore >= 6 || (possibleDistress && audioThreatScore >= 3)) {
                threatLevel = "critical";
            } else if (audioThreatScore >= 3 || possibleDistress) {
                threatLevel = "high";
            } else if (audioThreatScore >= 1) {
                threatLevel = "medium";
            } else {
                threatLevel = "low";
            }

            Map<String, Object> result = new HashMap<>();
            result.put("hasDistress", hasThreat);
            result.put("threatLevel", threatLevel);
            result.put("confidence", combinedConfidence);
            result.put("rmsEnergy", rms);
            result.put("method", audioThreatScore > 0 ? "hybrid_energy_keyword_analysis" : "heuristic_energy_analysis");
            result.put("message", hasThreat ? "Threat detected in audio" : "No threat detected");
            result.put("audioThreatScore", audioThreatScore);
            result.put("audioThreatReasons", audioThreatReasons);
            result.put("fulaniDialectDetected", fulaniDialectDetected);
            result.put("hasTranscript", transcript != null && !transcript.isBlank());

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
            // Hausa (expanded with Fulani banditry/terrorism keywords)
            {"garkuwa", "kidnapping_ha", "4"},
            {"bindiga", "gun_ha", "3"},
            {"bom", "bomb_ha", "4"},
            {"ta'addanci", "terrorism_ha", "4"},
            {"yaki", "war_ha", "3"},
            {"fashi", "robbery_ha", "3"},
            {"taimako", "help_ha", "2"},
            {"harbi", "shoot_ha", "4"},
            {"kashe", "kill_ha", "4"},
            {"makami", "weapon_ha", "3"},
            {"maharbi", "shooter_ha", "4"},
            {"wuta", "fire_ha", "3"},
            {"'yan fashi", "bandits_ha", "4"},
            {"'yan ta'adda", "terrorists_ha", "4"},
            {"doki", "horse_ha", "2"},
            {"dare", "night_ha", "2"},
            {"suna zuwa", "they_are_coming_ha", "3"},
            {"a gudu", "run_away_ha", "2"},
            {"mahaukata", "mad_ones_ha", "3"},
            // Fulfulde (Fulani language) specific
            {"fulani", "fulani_mention", "3"},
            {"ballal", "help_ful", "2"},
            {"fijo", "attack_ful", "4"},
            {"nyifta", "hide_ful", "2"},
            {"war", "war_ful", "3"},
            {"nyaw", "sickness_ful", "2"},
            // Yoruba
            {"gbigbe", "kidnapping_yo", "4"},
            {"ibon", "gun_yo", "3"},
            {"panumopa", "emergency_yo", "3"},
            {"iranlowo", "help_yo", "2"},
            {"ikọlu", "attack_yo", "4"},
            {"apaniyan", "murder_yo", "4"},
            {"ina", "fire_yo", "3"},
            {"sare", "run_yo", "2"},
            {"ologun", "warrior_yo", "3"},
            {"ipalara", "injury_yo", "2"},
            // Igbo
            {"atogboro", "kidnapping_ig", "4"},
            {"nkwatogbo", "terrorism_ig", "4"},
            {"egbe", "gun_ig", "3"},
            {"enyemaka", "help_ig", "2"},
            {"ogu", "war_ig", "3"},
            {"igbu", "kill_ig", "4"},
            {"oku", "fire_ig", "3"},
            {"oso", "run_ig", "2"},
            {"nwakpọrọ", "kidnapper_ig", "4"},
            {"ndi ọjọọ", "evil_ones_ig", "3"}
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
