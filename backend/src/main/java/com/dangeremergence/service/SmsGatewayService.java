package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.repository.SOSAlertRepository;
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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;

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
 *
 * Abuse Prevention (all configurable via application.yml):
 * - Rate limit: max 1 SMS per user per rateLimitMinutes window
 * - Cooldown: no SMS if user has an active unresolved alert
 * - Daily cap: max dailyCap SMS per user per calendar day
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

    // --- Abuse Prevention Configuration ---

    @Value("${sms.abuse.rate-limit-minutes:5}")
    private int rateLimitMinutes;

    @Value("${sms.abuse.daily-cap:5}")
    private int dailyCap;

    // --- Dependencies ---

    private final SOSAlertRepository sosAlertRepository;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    // --- Rate Limiting State (in-memory, resets on restart) ---

    /** Tracks last SMS timestamp per userId (for rate limiting). */
    private final ConcurrentHashMap<String, Long> lastSmsTime = new ConcurrentHashMap<>();

    /** Tracks SMS count per userId per date (for daily cap). Format key: "userId|date". */
    private final ConcurrentHashMap<String, Integer> dailySmsCount = new ConcurrentHashMap<>();

    // ========================================================================
    // Public API
    // ========================================================================

    /**
     * Send an SMS alert for a critical SOS alert to a specific phone number.
     * This is the last-resort delivery mechanism when WebSocket and FCM are unavailable.
     *
     * Abuse prevention checks (in order):
     * 1. SMS gateway must be configured
     * 2. User must not have an active unresolved alert (cooldown)
     * 3. Rate limit: must not have sent SMS within the last rateLimitMinutes
     * 4. Daily cap: must not exceed dailyCap SMS for this user today
     */
    @Async
    public void sendAlertSms(SOSAlert alert, String toPhoneNumber) {
        if (!isConfigured()) {
            log.debug("SMS gateway not configured - skipping SMS for alert {}", alert.getId());
            return;
        }

        String userId = alert.getUser() != null ? alert.getUser().getId() : null;

        // --- Safeguard 1: Cooldown — skip SMS if user already has an active unresolved alert ---
        if (userId != null && hasActiveUnresolvedAlert(userId, alert.getId())) {
            log.info("COOLDOWN: User {} has active unresolved alert — skipping SMS for alert {}",
                    userId, alert.getId());
            return;
        }

        // --- Safeguard 2: Rate limit — max 1 SMS per rateLimitMinutes per user ---
        if (userId != null && isRateLimited(userId)) {
            log.info("RATE LIMITED: User {} exceeded rate limit — skipping SMS for alert {}",
                    userId, alert.getId());
            return;
        }

        // --- Safeguard 3: Daily cap — max dailyCap SMS per user per calendar day ---
        if (userId != null && isDailyCapExceeded(userId)) {
            log.info("DAILY CAP EXCEEDED: User {} hit daily SMS limit — skipping SMS for alert {}",
                    userId, alert.getId());
            return;
        }

        try {
            String message = buildSmsMessage(alert);
            sendSms(toPhoneNumber, message);
            // Record successful send for rate limiting and daily cap tracking
            if (userId != null) {
                recordSmsSent(userId);
            }
            log.info("SMS sent for alert {} to {}", alert.getId(), maskPhone(toPhoneNumber));
        } catch (Exception e) {
            log.error("Failed to send SMS for alert {}: {}", alert.getId(), e.getMessage());
        }
    }

    /**
     * Send a bulk SMS alert to all responders in an area.
     * Note: Bulk broadcasts are not subject to per-user rate limits since they
     * go to responders, not the alert creator.
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
     * Subject to rate limiting and daily cap by phone number (used as identifier).
     */
    @Async
    public void sendNotificationSms(String toPhoneNumber, String message) {
        if (!isConfigured()) return;

        // Apply rate limiting by phone number for notification SMS
        String phoneKey = "phone:" + formatPhoneNumber(toPhoneNumber);
        if (isRateLimited(phoneKey)) {
            log.info("RATE LIMITED: Notification SMS to {} skipped (rate limit)", maskPhone(toPhoneNumber));
            return;
        }
        if (isDailyCapExceeded(phoneKey)) {
            log.info("DAILY CAP: Notification SMS to {} skipped (daily cap)", maskPhone(toPhoneNumber));
            return;
        }

        try {
            sendSms(toPhoneNumber, message);
            recordSmsSent(phoneKey);
            log.info("Notification SMS sent to {}", maskPhone(toPhoneNumber));
        } catch (Exception e) {
            log.error("Failed to send notification SMS: {}", e.getMessage());
        }
    }

    // ========================================================================
    // Abuse Prevention Checks
    // ========================================================================

    /**
     * Check if the user has any active (non-resolved, non-expired) alert
     * other than the current one. This prevents sending SMS confirmations
     * when the user is already aware of an ongoing alert.
     */
    private boolean hasActiveUnresolvedAlert(String userId, String currentAlertId) {
        try {
            // Look for any active alert by this user that is NOT the current alert
            // If such an alert exists, the user is already in an emergency situation
            // and doesn't need another SMS confirmation
            return sosAlertRepository.findByUserIdAndStatusOrderByCreatedAtDesc(
                    userId, SOSAlert.AlertStatus.active)
                    .stream()
                    .anyMatch(a -> !a.getId().equals(currentAlertId));
        } catch (Exception e) {
            log.warn("Failed to check active alerts for user {}: {}", userId, e.getMessage());
            return false; // Allow SMS on error (fail open for safety)
        }
    }

    /**
     * Check if the user has exceeded the rate limit.
     * Returns true if an SMS was sent within the last rateLimitMinutes.
     */
    private boolean isRateLimited(String userId) {
        Long lastSent = lastSmsTime.get(userId);
        if (lastSent == null) {
            return false;
        }
        long elapsed = System.currentTimeMillis() - lastSent;
        long windowMs = rateLimitMinutes * 60_000L;
        return elapsed < windowMs;
    }

    /**
     * Check if the user has exceeded the daily SMS cap.
     * Returns true if dailySmsCount >= dailyCap for today.
     */
    private boolean isDailyCapExceeded(String userId) {
        String key = dailyKey(userId);
        Integer count = dailySmsCount.get(key);
        return count != null && count >= dailyCap;
    }

    /**
     * Record that an SMS was sent for rate limiting and daily cap tracking.
     */
    private void recordSmsSent(String userId) {
        // Update rate limit timestamp
        lastSmsTime.put(userId, System.currentTimeMillis());

        // Update daily count
        String key = dailyKey(userId);
        dailySmsCount.merge(key, 1, Integer::sum);
    }

    /**
     * Build the daily cap key: "userId|YYYY-MM-DD".
     * This ensures counts reset each calendar day.
     */
    private String dailyKey(String userId) {
        return userId + "|" + LocalDate.now().toString();
    }

    // ========================================================================
    // SMS Building & Sending
    // ========================================================================

    private String buildSmsMessage(SOSAlert alert) {
        // Include the user's name so the recipient knows who is in danger
        String userName = alert.getUser() != null && alert.getUser().getName() != null
                ? alert.getUser().getName()
                : "Someone";

        String alertType = alert.getAlertType() != null ? alert.getAlertType() : "EMERGENCY";
        String location = "";
        if (alert.getLatitude() != null && alert.getLongitude() != null) {
            location = String.format(" at %.4f,%.4f", alert.getLatitude(), alert.getLongitude());
        }
        String description = alert.getDescription() != null
                ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 100))
                : "";

        return String.format("🚨 %s needs help! %s ALERT%s. %s. Priority: %d/10.",
                userName, alertType.toUpperCase(), location, description, alert.getPriority());
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
