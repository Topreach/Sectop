package com.dangeremergence.controller;

import com.dangeremergence.service.IncidentService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.util.*;

/**
 * STOMP message controller for real-time audio analysis via WebSocket.
 *
 * Handles audio analysis requests sent via STOMP SEND frames from the frontend
 * WebSocket connection. This is faster than HTTP POST because it reuses the
 * existing WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * The analysis result is sent back to the requesting user via their personal queue:
 *   /user/queue/analyze/audio/result
 *
 * Destination: /app/analyze/audio
 * Mapped from: SEND destination:/app/analyze/audio
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompAudioController {

    private final SimpMessagingTemplate messagingTemplate;

    /**
     * Handle an audio analysis request via STOMP SEND frame.
     * Performs on-server audio analysis (RMS energy, keyword spotting)
     * and sends the result back to the user's personal queue.
     */
    @MessageMapping("/analyze/audio")
    public void handleAudioAnalysis(@Payload Map<String, Object> payload,
                                     SimpMessageHeaderAccessor headerAccessor) {
        try {
            String userId = (String) payload.get("userId");
            String base64Audio = (String) payload.get("audio");
            String transcript = (String) payload.get("transcript"); // Optional speech-to-text transcript

            if (base64Audio == null || base64Audio.isBlank()) {
                log.warn("STOMP audio analysis missing audio data");
                if (userId != null) {
                    messagingTemplate.convertAndSendToUser(userId, "/queue/analyze/audio/result",
                            Map.of("error", "Missing audio data", "success", false));
                }
                return;
            }

            // Perform server-side audio analysis (same logic as AIController.analyzeAudio)
            Map<String, Object> result = analyzeAudioData(base64Audio, transcript);

            // Send result back to the requesting user via their personal queue
            if (userId != null) {
                messagingTemplate.convertAndSendToUser(userId, "/queue/analyze/audio/result",
                        Map.of("data", result, "success", true));
            }

            log.debug("STOMP audio analysis completed for userId={}", userId);
        } catch (Exception e) {
            log.error("STOMP audio analysis failed: {}", e.getMessage());
        }
    }

    /**
     * Analyze audio data for distress signals and threat keywords.
     * Mirrors the logic from AIController.analyzeAudio().
     */
    private Map<String, Object> analyzeAudioData(String base64Audio, String transcript) {
        try {
            byte[] audioData = Base64.getDecoder().decode(base64Audio);

            // Calculate RMS (Root Mean Square) energy of the audio signal
            double sum = 0;
            for (byte b : audioData) {
                sum += b * b;
            }
            double rms = Math.sqrt(sum / audioData.length);

            // Distress signals (screams, whistles) are typically high energy and high frequency
            boolean possibleDistress = rms > 40.0;
            double confidence = Math.min(rms / 100.0, 0.95);

            // Keyword spotting from transcript
            List<String> threatReasons = new ArrayList<>();
            int threatScore = 0;
            boolean fulaniDialectDetected = false;

            if (transcript != null && !transcript.isBlank()) {
                String lowerTranscript = transcript.toLowerCase();

                // Hausa/Fulani threat keywords
                String[][] hausaFulaniKeywords = {
                    {"fulani", "Fulani mention", "3"},
                    {"bindiga", "Gun detected (Hausa)", "3"},
                    {"harbi", "Shoot detected (Hausa)", "4"},
                    {"kashe", "Kill detected (Hausa)", "4"},
                    {"ta'addanci", "Terrorism detected (Hausa)", "4"},
                    {"yaki", "War detected (Hausa)", "3"},
                    {"garkuwa", "Kidnapping detected (Hausa)", "4"},
                    {"fashi", "Robbery detected (Hausa)", "3"},
                    {"bom", "Bomb detected", "4"},
                    {"wuta", "Fire detected (Hausa)", "3"},
                    {"makami", "Weapon detected (Hausa)", "3"},
                    {"maharbi", "Shooter detected (Hausa)", "4"},
                    {"'yan fashi", "Bandits detected (Hausa)", "4"},
                    {"'yan ta'adda", "Terrorists detected (Hausa)", "4"},
                    {"doki", "Horse detected (Hausa)", "2"},
                    {"dare", "Night detected (Hausa)", "2"},
                    {"taimako", "Help detected (Hausa)", "2"},
                    {"a gudu", "Run away detected (Hausa)", "2"},
                    // Fulfulde/Fulani specific
                    {"ballal", "Help detected (Fulfulde)", "2"},
                    {"fijo", "Attack detected (Fulfulde)", "4"},
                    {"nyifta", "Hide detected (Fulfulde)", "2"},
                    // English keywords
                    {"help", "Help keyword", "2"},
                    {"sos", "SOS keyword", "4"},
                    {"emergency", "Emergency keyword", "3"},
                    {"kidnap", "Kidnap keyword", "4"},
                    {"gun", "Gun keyword", "3"},
                    {"shoot", "Shoot keyword", "4"},
                    {"bomb", "Bomb keyword", "4"},
                    {"attack", "Attack keyword", "3"},
                    {"danger", "Danger keyword", "2"},
                    {"run", "Run keyword", "2"},
                    {"hide", "Hide keyword", "2"},
                    {"terrorist", "Terrorist keyword", "4"},
                    {"bandit", "Bandit keyword", "4"},
                };

                for (String[] keyword : hausaFulaniKeywords) {
                    if (lowerTranscript.contains(keyword[0])) {
                        threatReasons.add(keyword[1]);
                        threatScore += Integer.parseInt(keyword[2]);
                        if (keyword[0].equals("fulani")) {
                            fulaniDialectDetected = true;
                        }
                    }
                }
            }

            // Determine priority based on combined signals
            String priority;
            if (possibleDistress && threatScore >= 6) {
                priority = "critical";
            } else if (possibleDistress || threatScore >= 4) {
                priority = "high";
            } else if (threatScore >= 2) {
                priority = "medium";
            } else {
                priority = "low";
            }

            Map<String, Object> result = new HashMap<>();
            result.put("possibleDistress", possibleDistress);
            result.put("confidence", Math.round(confidence * 100.0) / 100.0);
            result.put("rmsEnergy", Math.round(rms * 100.0) / 100.0);
            result.put("priority", priority);
            result.put("threatScore", threatScore);
            result.put("threatReasons", threatReasons);
            result.put("fulaniDialectDetected", fulaniDialectDetected);
            result.put("method", "stomp_fast_path");

            return result;
        } catch (Exception e) {
            log.error("Audio analysis error: {}", e.getMessage());
            return Map.of(
                    "possibleDistress", false,
                    "confidence", 0.0,
                    "priority", "low",
                    "threatScore", 0,
                    "threatReasons", List.of(),
                    "error", e.getMessage(),
                    "method", "stomp_fast_path"
            );
        }
    }
}
