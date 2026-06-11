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
import java.util.Base64;

/**
 * SMS Gateway Service for last-resort delivery of critical alerts.
 *
 * When a user has no data connection (no WebSocket, no FCM), this service
 * sends an SMS alert via Twilio API as a fallback. This ensures that
 * even in areas with poor internet connectivity, critical SOS alerts
 * are delivered via the cellular network (SMS).
 *
 * Delivery chain:
 *   SOSAlertService -> SmsGatewayService.sendAlertSms()
 *   -> Twilio REST API -> SMS to responder/citizen phone
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SmsGatewayService {

    @Value("${sms.twilio.account-sid:}")
    private String twilioAccountSid;

    @Value("${sms.twilio.auth-token:}")
    private String twilioAuthToken;

    @Value("${sms.twilio.from-number:}")
    private String twilioFromNumber;

    @Value("${sms.twilio.api-url:https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json}")
    private String twilioApiUrl;

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

        return String.format("🚨 DANGER EMERGENCE: %s ALERT%s. %s. Priority: %d/10. Reply STOP to opt out.",
                alertType.toUpperCase(), location, description, alert.getPriority());
    }

    private void sendSms(String to, String body) throws Exception {
        String url = String.format(twilioApiUrl, twilioAccountSid);
        String auth = twilioAccountSid + ":" + twilioAuthToken;
        String encodedAuth = Base64.getEncoder().encodeToString(auth.getBytes());

        String formData = "To=" + java.net.URLEncoder.encode(to, "UTF-8")
                + "&From=" + java.net.URLEncoder.encode(twilioFromNumber, "UTF-8")
                + "&Body=" + java.net.URLEncoder.encode(body, "UTF-8");

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("Authorization", "Basic " + encodedAuth)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(formData))
                .timeout(Duration.ofSeconds(10))
                .build();

        httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                .thenAccept(response -> {
                    if (response.statusCode() == 201) {
                        log.debug("Twilio SMS sent successfully");
                    } else {
                        log.warn("Twilio SMS returned status: {}", response.statusCode());
                    }
                });
    }

    private boolean isConfigured() {
        return twilioAccountSid != null && !twilioAccountSid.isEmpty()
                && twilioAuthToken != null && !twilioAuthToken.isEmpty()
                && twilioFromNumber != null && !twilioFromNumber.isEmpty();
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 6) return "****";
        return phone.substring(0, 3) + "****" + phone.substring(phone.length() - 3);
    }
}
