package com.dangeremergence.sos.controller;

import com.dangeremergence.sos.service.SOSAlertService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;

import java.util.Map;

/**
 * STOMP message controller for real-time SOS alert sending via WebSocket.
 * <p>
 * Connected via the dedicated /ws-sos WebSocket endpoint on port 8081.
 * Destination: /app/alerts/send
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class StompAlertController {

    private final SOSAlertService sosAlertService;

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
