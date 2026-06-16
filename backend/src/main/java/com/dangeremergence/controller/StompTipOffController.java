package com.dangeremergence.controller;

import com.dangeremergence.service.TipOffService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * STOMP message controller for real-time tip-off submission via WebSocket.
 *
 * Handles tip-offs sent via STOMP SEND frames from the frontend WebSocket
 * connection. This is faster than HTTP POST because it reuses the existing
 * WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * Destination: /app/tip-offs/submit
 * Mapped from: SEND destination:/app/tip-offs/submit
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompTipOffController {

    private final TipOffService tipOffService;

    /**
     * Handle a tip-off submission via STOMP SEND frame.
     * This is the fast path for tip-off delivery — reuses the existing
     * WebSocket connection instead of opening a new HTTP connection.
     */
    @MessageMapping("/tip-offs/submit")
    public void handleTipOffSubmit(@Payload Map<String, Object> payload) {
        try {
            String tipType = (String) payload.get("tipType");
            String description = (String) payload.get("description");
            Number latNum = (Number) payload.get("latitude");
            Number lngNum = (Number) payload.get("longitude");
            Number accNum = (Number) payload.get("accuracy");
            String targetDescription = (String) payload.get("targetDescription");
            String suspectDescription = (String) payload.get("suspectDescription");
            Boolean isAnonymous = (Boolean) payload.getOrDefault("isAnonymous", false);
            String reporterId = (String) payload.get("reporterId");

            Double latitude = latNum != null ? latNum.doubleValue() : null;
            Double longitude = lngNum != null ? lngNum.doubleValue() : null;
            Double accuracy = accNum != null ? accNum.doubleValue() : null;

            if (description == null || description.isBlank()) {
                log.warn("STOMP tip-off missing required description");
                return;
            }

            // Delegate to TipOffService (validates, saves, runs AI threat analysis, publishes via MQTT)
            tipOffService.submitTip(
                    tipType, description,
                    latitude, longitude, accuracy,
                    LocalDateTime.now(), targetDescription,
                    suspectDescription, isAnonymous != null && isAnonymous,
                    reporterId
            );

            log.debug("STOMP tip-off submitted: type={}, anonymous={}", tipType, isAnonymous);
        } catch (Exception e) {
            log.error("STOMP tip-off submission failed: {}", e.getMessage());
        }
    }
}
