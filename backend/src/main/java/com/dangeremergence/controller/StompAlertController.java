package com.dangeremergence.controller;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.service.SOSAlertService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP message controller for real-time SOS alert sending via WebSocket.
 *
 * Handles SOS alerts sent via STOMP SEND frames from the frontend WebSocket
 * connection. This is faster than HTTP POST because it reuses the existing
 * WebSocket connection and avoids HTTP overhead (handshake, headers, etc.).
 *
 * Destination: /app/alerts/send
 * Mapped from: SEND destination:/app/alerts/send
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompAlertController {

    private final SOSAlertService sosAlertService;

    /**
     * Handle an SOS alert sent via STOMP SEND frame.
     * This is the fast path for SOS delivery — reuses the existing
     * WebSocket connection instead of opening a new HTTP connection.
     */
    @MessageMapping("/alerts/send")
    public void handleAlertSend(@Payload Map<String, Object> payload) {
        try {
            String userId = (String) payload.get("user_id");
            String alertType = (String) payload.get("alert_type");
            String description = (String) payload.get("description");
            Number latNum = (Number) payload.get("latitude");
            Number lngNum = (Number) payload.get("longitude");
            Number accNum = (Number) payload.get("accuracy");
            Number priorityNum = (Number) payload.getOrDefault("priority", 5);
            Boolean isSilent = (Boolean) payload.getOrDefault("is_silent", false);
            Boolean isCovert = (Boolean) payload.getOrDefault("is_covert", false);

            Double latitude = latNum != null ? latNum.doubleValue() : null;
            Double longitude = lngNum != null ? lngNum.doubleValue() : null;
            Double accuracy = accNum != null ? accNum.doubleValue() : null;
            int priority = priorityNum != null ? priorityNum.intValue() : 5;

            if (userId == null || alertType == null) {
                log.warn("STOMP alert missing required fields: userId={}, alertType={}", userId, alertType);
                return;
            }
            // Delegate to SOSAlertService (creates alert, pushes via WebSocket, MQTT, FCM, etc.)
            sosAlertService.createAlert(
                    userId, alertType, description,
                    latitude, longitude, accuracy,
                    priority, isSilent != null && isSilent,
                    isCovert != null && isCovert
            );

            log.debug("STOMP SOS alert processed: userId={}, type={}, covert={}", userId, alertType, isCovert);
        } catch (Exception e) {
            log.error("STOMP SOS alert handling failed: {}", e.getMessage());
        }
    }
}
