package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * SMS Gateway Service for last-resort delivery of critical alerts.
 *
 * When a user has no data connection (no WebSocket, no FCM), this service
 * sends an SMS alert via Termii API as a fallback. This ensures that
 * even in areas with poor internet connectivity, critical SOS alerts
 * are delivered via the cellular network (SMS).
 *
 * Termii is a Nigerian SMS provider with competitive pricing (~₦2-4/SMS)
 * and no monthly fees. Sign up at https://termii.com
 *
 * Delivery chain:
 *   SOSAlertService -> SmsGatewayService.sendAlertSms()
 *   -> Termii REST API -> SMS to responder/citizen phone
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SmsGatewayService {

    @Value("${sms.termii.api-key:}")
    private String termiiApiKey;

    @Value("${sms.termii.sender-id:}")
    private String termiiSenderId;

    @Value("${sms.termii.api-url:https://api.termii.com/api/sms/send}")
    private String termiiApiUrl;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    /**
     * Send an SMS alert for a critical SOS alert to a specific phone number.
     * This is the last-resort delivery mechanism when WebSocket and FCM are unavailable.
     */
    @Async
    public void sendAlertSms(SOSAlert alert, String toPhoneNumber) {
        if (!isConfigured()) {
            log.debug("SMS gateway not configured - skipping SMS for alert {}", alert.getId());
            return;
        }

        try {
            String message = buildSmsMessage(alert);
            sendSms(toPhoneNumber, message);
            log.info("SMS sent for alert {} to {}", alert.getId(), maskPhone(toPhoneNumber));
        } catch (Exception e) {
            log.error("Failed to send SMS for alert {}: {}", alert.getId(), e.getMessage());
        }
    }

    /**
     * Send a bulk SMS alert to all responders in an area.
     */
    @Async
    public void broadcastAlertSms(SOSAlert alert, String[] phoneNumbers) {
        if (!isConfigured()) return;

        String message = buildSmsMessage(alert);
        for (String phone : phoneNumbers) {
            try {
                sendSms(phone, message);
                log.debug("Broadcast SMS sent to {}", maskPhone(phone));
            } catch (Exception e) {
                log.warn("Broadcast SMS failed for {}: {}", maskPhone(phone), e.getMessage());
            }
        }
    }

    /**
     * Send a general notification SMS (non-alert).
     */
    @Async
    public void sendNotificationSms(String toPhoneNumber, String message) {
        if (!isConfigured()) return;

        try {
            sendSms(toPhoneNumber, message);
            log.info("Notification SMS sent to {}", maskPhone(toPhoneNumber));
        } catch (Exception e) {
            log.error("Failed to send notification SMS: {}", e.getMessage());
        }
    }

    private String buildSmsMessage(SOSAlert alert) {
        String alertType = alert.getAlertType() != null ? alert.getAlertType() : "EMERGENCY";
        String location = "";
        if (alert.getLatitude() != null && alert.getLongitude() != null) {
            location = String.format(" at %.4f,%.4f", alert.getLatitude(), alert.getLongitude());
        }
        String description = alert.getDescription() != null
                ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 100))
                : "";

        return String.format("🚨 DANGER EMERGENCE: %s ALERT%s. %s. Priority: %d/10.",
                alertType.toUpperCase(), location, description, alert.getPriority());
    }

    private void sendSms(String to, String body) throws Exception {
        // Ensure phone number is in international format (remove leading 0, add 234)
        String formattedTo = formatPhoneNumber(to);

        // Build JSON payload for Termii API
        String jsonPayload = String.format(
                "{\"api_key\":\"%s\",\"to\":\"%s\",\"from\":\"%s\",\"sms\":\"%s\",\"type\":\"plain\",\"channel\":\"generic\"}",
                termiiApiKey,
                formattedTo,
                termiiSenderId,
                escapeJson(body)
        );

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(termiiApiUrl))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(jsonPayload))
                .timeout(Duration.ofSeconds(10))
                .build();

        httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                .thenAccept(response -> {
                    if (response.statusCode() == 200) {
                        log.debug("Termii SMS sent successfully");
                    } else {
                        log.warn("Termii SMS returned status: {} body: {}",
                                response.statusCode(), response.body());
                    }
                });
    }

    /**
     * Format phone number to international format for Termii.
     * Handles: 08012345678 -> 2348012345678, +2348012345678 -> 2348012345678
     */
    private String formatPhoneNumber(String phone) {
        if (phone == null) return "";
        String cleaned = phone.replaceAll("[^0-9]", "");
        if (cleaned.startsWith("234") && cleaned.length() == 13) {
            return cleaned;
        } else if (cleaned.startsWith("0") && cleaned.length() == 11) {
            return "234" + cleaned.substring(1);
        }
        return cleaned;
    }

    private boolean isConfigured() {
        return termiiApiKey != null && !termiiApiKey.isEmpty()
                && termiiSenderId != null && !termiiSenderId.isEmpty();
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 6) return "****";
        return phone.substring(0, 3) + "****" + phone.substring(phone.length() - 3);
    }

    private String escapeJson(String value) {
        if (value == null) return "";
        return value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
