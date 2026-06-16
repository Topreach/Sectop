package com.dangeremergence.controller;

import com.dangeremergence.service.BroadcastService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * STOMP message controller for real-time broadcast creation via WebSocket.
 *
 * Handles broadcasts sent via STOMP SEND frames from the frontend WebSocket
 * connection. This is faster than HTTP POST because it reuses the existing
 * WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * Destination: /app/broadcasts/create
 * Mapped from: SEND destination:/app/broadcasts/create
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompBroadcastController {

    private final BroadcastService broadcastService;

    /**
     * Handle a broadcast creation via STOMP SEND frame.
     * This is the fast path for broadcast delivery — reuses the existing
     * WebSocket connection instead of opening a new HTTP connection.
     */
    @MessageMapping("/broadcasts/create")
    public void handleBroadcastCreate(@Payload Map<String, Object> payload) {
        try {
            String title = (String) payload.get("title");
            String message = (String) payload.get("message");
            String severity = (String) payload.get("severity");
            String broadcastType = (String) payload.get("broadcastType");
            String targetState = (String) payload.get("targetState");
            String targetLga = (String) payload.get("targetLga");
            String createdById = (String) payload.get("createdById");
            Number latNum = (Number) payload.get("latitude");
            Number lngNum = (Number) payload.get("longitude");
            Number radiusNum = (Number) payload.get("radiusKm");

            Double latitude = latNum != null ? latNum.doubleValue() : null;
            Double longitude = lngNum != null ? lngNum.doubleValue() : null;
            Double radiusKm = radiusNum != null ? radiusNum.doubleValue() : null;

            if (title == null || message == null || severity == null || broadcastType == null) {
                log.warn("STOMP broadcast missing required fields");
                return;
            }

            // Delegate to BroadcastService (validates, saves, publishes via MQTT + WebSocket)
            broadcastService.createBroadcast(
                    title, message, severity, broadcastType,
                    targetState, targetLga, null,
                    latitude, longitude, radiusKm,
                    createdById, null
            );

            log.debug("STOMP broadcast created: title={}, severity={}", title, severity);
        } catch (Exception e) {
            log.error("STOMP broadcast creation failed: {}", e.getMessage());
        }
    }
}
