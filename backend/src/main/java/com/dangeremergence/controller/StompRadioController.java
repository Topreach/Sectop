package com.dangeremergence.controller;

import com.dangeremergence.service.RadioBroadcastService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP message controller for real-time radio broadcast creation via WebSocket.
 *
 * Handles radio broadcasts sent via STOMP SEND frames from the frontend WebSocket
 * connection. This is faster than HTTP POST because it reuses the existing
 * WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * Destination: /app/radio/broadcast
 * Mapped from: SEND destination:/app/radio/broadcast
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompRadioController {

    private final RadioBroadcastService radioBroadcastService;

    /**
     * Handle a radio broadcast creation via STOMP SEND frame.
     * This is the fast path for radio broadcast delivery — reuses the existing
     * WebSocket connection instead of opening a new HTTP connection.
     */
    @MessageMapping("/radio/broadcast")
    public void handleRadioBroadcast(@Payload Map<String, Object> payload) {
        try {
            String title = (String) payload.get("title");
            String message = (String) payload.get("message");
            String language = (String) payload.get("language");
            String severity = (String) payload.get("severity");
            String broadcastType = (String) payload.get("broadcastType");
            Number targetFrequencyNum = (Number) payload.get("targetFrequency");
            String targetState = (String) payload.get("targetState");
            String targetLga = (String) payload.get("targetLga");
            String ttsVoice = (String) payload.get("ttsVoice");
            Boolean isAnonymous = (Boolean) payload.getOrDefault("isAnonymous", false);
            String createdById = (String) payload.get("createdById");

            Double targetFrequency = targetFrequencyNum != null ? targetFrequencyNum.doubleValue() : null;

            if (title == null || message == null || message.isBlank()) {
                log.warn("STOMP radio broadcast missing required fields: title={}, message={}", title, message);
                return;
            }

            // Delegate to RadioBroadcastService (validates, saves, generates TTS audio, publishes via MQTT)
            radioBroadcastService.createRadioBroadcast(
                    title, message, language, severity, broadcastType,
                    targetFrequency, targetState, targetLga,
                    ttsVoice, isAnonymous != null && isAnonymous, createdById
            );

            log.debug("STOMP radio broadcast created: title={}, target={}/{}", title, targetState, targetLga);
        } catch (Exception e) {
            log.error("STOMP radio broadcast creation failed: {}", e.getMessage());
        }
    }
}
