package com.dangeremergence.service;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.UserRepository;
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
import java.util.List;
import java.util.Map;

/**
 * Firebase Cloud Messaging (FCM) push notification service.
 *
 * Sends instant push notifications to offline users when an SOS alert
 * is created in their area. This ensures delivery even when the user
 * is not connected to WebSocket.
 *
 * Requires FCM server key configured in environment variables.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FcmPushService {

    private final UserRepository userRepository;

    @Value("${fcm.server-key:}")
    private String fcmServerKey;

    @Value("${fcm.api-url:https://fcm.googleapis.com/fcm/send}")
    private String fcmApiUrl;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    /**
     * Send push notification for a new SOS alert to all nearby users.
     */
    @Async
    public void notifyAlertToNearbyUsers(SOSAlert alert, double radiusKm) {
        if (fcmServerKey == null || fcmServerKey.isEmpty()) {
            log.warn("FCM_SERVER_KEY not configured - SKIPPING ALL push notifications for alert {}. Set FCM_SERVER_KEY environment variable to enable push notifications.", alert.getId());
            return;
        }

        try {
            // Find users near the alert location
            double latDelta = radiusKm / 111.0;
            double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(alert.getLatitude())));
            List<User> nearbyUsers = userRepository.findUsersInArea(
                    alert.getLatitude() - latDelta,
                    alert.getLatitude() + latDelta,
                    alert.getLongitude() - lonDelta,
                    alert.getLongitude() + lonDelta
            );

            log.info("FCM: Found {} users with FCM tokens for alert {} (radius={}km)", nearbyUsers.size(), alert.getId(), radiusKm);

            int notifiedCount = 0;
            for (User user : nearbyUsers) {
                if (user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                    sendPushNotification(user.getFcmToken(), alert);
                    notifiedCount++;
                } else {
                    log.debug("FCM: User {} has no FCM token, skipping", user.getId());
                }
            }
            log.info("FCM: Successfully sent push to {} / {} nearby users for alert {}", notifiedCount, nearbyUsers.size(), alert.getId());
        } catch (Exception e) {
            log.error("FCM push failed for alert {}: {}", alert.getId(), e.getMessage(), e);
        }
    }

    /**
     * Send push notification to a specific user.
     */
    @Async
    public void notifyUser(SOSAlert alert, String userId) {
        if (fcmServerKey == null || fcmServerKey.isEmpty()) return;

        try {
            User user = userRepository.findById(userId).orElse(null);
            if (user != null && user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                sendPushNotification(user.getFcmToken(), alert);
            }
        } catch (Exception e) {
            log.error("FCM notify user failed: {}", e.getMessage());
        }
    }

    /**
     * Send push notification for a threat intelligence alert (incident, danger zone, etc.)
     * to all users near the given coordinates.
     */
    @Async
    public void notifyThreatAlertToNearbyUsers(
            double latitude, double longitude, double radiusKm,
            String title, String body, String type,
            String severity, Map<String, String> extraData) {
        if (fcmServerKey == null || fcmServerKey.isEmpty()) {
            log.debug("FCM not configured - skipping threat push notification");
            return;
        }

        try {
            double latDelta = radiusKm / 111.0;
            double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(latitude)));
            List<User> nearbyUsers = userRepository.findUsersInArea(
                    latitude - latDelta,
                    latitude + latDelta,
                    longitude - lonDelta,
                    longitude + lonDelta
            );

            for (User user : nearbyUsers) {
                if (user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                    sendThreatPushNotification(user.getFcmToken(), title, body, type, severity,
                            latitude, longitude, extraData);
                }
            }
            log.info("FCM: Notified {} nearby users for threat alert '{}'", nearbyUsers.size(), title);
        } catch (Exception e) {
            log.error("FCM threat push failed: {}", e.getMessage());
        }
    }

    /**
     * Send push notification for a new verified incident to nearby users.
     */
    @Async
    public void notifyIncidentToNearbyUsers(Incident incident) {
        String title = String.format("⚠️ %s Reported Nearby",
                incident.getIncidentType().substring(0, 1).toUpperCase()
                        + incident.getIncidentType().substring(1));
        String body = incident.getDescription() != null
                ? incident.getDescription().substring(0, Math.min(incident.getDescription().length(), 150))
                : "A " + incident.getIncidentType() + " incident has been reported in your area";
        String severity = incident.getSeverity() != null ? incident.getSeverity().name().toLowerCase() : "medium";

        Map<String, String> extraData = new java.util.HashMap<>();
        extraData.put("incidentId", incident.getId());
        extraData.put("incidentType", incident.getIncidentType());

        notifyThreatAlertToNearbyUsers(
                incident.getLatitude(), incident.getLongitude(), 20.0,
                title, body, "incident", severity, extraData);
    }

    /**
     * Send a discreet push notification for a covert SOS alert to a trusted recipient.
     *
     * Unlike standard SOS notifications, covert notifications:
     * - Use a neutral title (no "🚨 SOS" emoji)
     * - Have no sound/vibration
     * - Use a low-priority channel
     * - Only include essential data payload (no public broadcast indicators)
     *
     * This is used by CovertAlertService to notify emergency contacts and
     * verified responders without alerting the kidnapper who may also have the app.
     */
    @Async
    public void sendCovertNotification(User recipient, SOSAlert alert) {
        if (fcmServerKey == null || fcmServerKey.isEmpty()) {
            log.debug("FCM not configured - skipping covert notification");
            return;
        }

        try {
            String fcmToken = recipient.getFcmToken();
            if (fcmToken == null || fcmToken.isEmpty()) {
                log.debug("No FCM token for user {} - skipping covert notification", recipient.getId());
                return;
            }

            String json = String.format("""
                {
                  "to": "%s",
                  "priority": "normal",
                  "notification": {
                    "title": "Alert from Emergency Contact",
                    "body": "A contact needs your assistance. Open the app for details.",
                    "sound": "default",
                    "priority": "low",
                    "channelId": "covert_alerts"
                  },
                  "data": {
                    "type": "covert_sos",
                    "alertId": "%s",
                    "alertType": "%s",
                    "latitude": "%s",
                    "longitude": "%s",
                    "priority": "%d",
                    "timestamp": "%d",
                    "covert": "true"
                  }
                }
                """,
                escapeJson(fcmToken),
                escapeJson(alert.getId()),
                escapeJson(alert.getAlertType()),
                alert.getLatitude(),
                alert.getLongitude(),
                alert.getPriority(),
                System.currentTimeMillis()
            );

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(fcmApiUrl))
                    .header("Authorization", "key=" + fcmServerKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .timeout(Duration.ofSeconds(5))
                    .build();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                    .thenAccept(response -> {
                        if (response.statusCode() == 200) {
                            log.debug("Covert FCM notification sent to user {}", recipient.getId());
                        } else {
                            log.warn("Covert FCM push returned status: {} for user {}",
                                    response.statusCode(), recipient.getId());
                        }
                    });
        } catch (Exception e) {
            log.warn("Covert FCM send failed for user {}: {}", recipient.getId(), e.getMessage());
        }
    }

    /**
     * Send push notification for a new danger zone to nearby users.
     */
    @Async
    public void notifyDangerZoneToNearbyUsers(Zone zone) {
        String title = String.format("🚨 Danger Zone: %s", zone.getName());
        String body = zone.getDescription() != null
                ? zone.getDescription().substring(0, Math.min(zone.getDescription().length(), 150))
                : "A danger zone has been created in your area";
        String severity = zone.getSeverity() != null ? zone.getSeverity() : "medium";

        Map<String, String> extraData = new java.util.HashMap<>();
        extraData.put("zoneId", zone.getId());
        extraData.put("zoneName", zone.getName());

        notifyThreatAlertToNearbyUsers(
                zone.getLatitude(), zone.getLongitude(), zone.getRadius() != null ? zone.getRadius() : 5.0,
                title, body, "danger_zone", severity, extraData);
    }

    private void sendPushNotification(String fcmToken, SOSAlert alert) {
        try {
            String priority = alert.getPriority() >= 9 ? "high" : "normal";
            String body = alert.getDescription() != null
                    ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 200))
                    : "SOS Alert: " + alert.getAlertType();

            String json = String.format("""
                {
                  "to": "%s",
                  "priority": "%s",
                  "notification": {
                    "title": "🚨 SOS Alert - %s",
                    "body": "%s",
                    "sound": "alarm",
                    "priority": "%s",
                    "channelId": "sos_alerts"
                  },
                  "data": {
                    "type": "sos_alert",
                    "alertId": "%s",
                    "alertType": "%s",
                    "latitude": "%s",
                    "longitude": "%s",
                    "priority": "%d",
                    "timestamp": "%d"
                  }
                }
                """,
                escapeJson(fcmToken),
                priority,
                escapeJson(alert.getAlertType()),
                escapeJson(body),
                priority,
                escapeJson(alert.getId()),
                escapeJson(alert.getAlertType()),
                alert.getLatitude(),
                alert.getLongitude(),
                alert.getPriority(),
                System.currentTimeMillis()
            );

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(fcmApiUrl))
                    .header("Authorization", "key=" + fcmServerKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .timeout(Duration.ofSeconds(5))
                    .build();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                    .thenAccept(response -> {
                        if (response.statusCode() == 200) {
                            log.debug("FCM push sent successfully");
                        } else {
                            log.warn("FCM push returned status: {}", response.statusCode());
                        }
                    });
        } catch (Exception e) {
            log.warn("FCM send failed: {}", e.getMessage());
        }
    }

    private void sendThreatPushNotification(
            String fcmToken, String title, String body, String type,
            String severity, double latitude, double longitude,
            Map<String, String> extraData) {
        try {
            String priority = "high".equals(severity) || "critical".equals(severity) ? "high" : "normal";

            // Build data payload as a JSON string
            StringBuilder dataJson = new StringBuilder();
            dataJson.append("{");
            dataJson.append("\"type\":\"").append(escapeJson(type)).append("\"");
            dataJson.append(",\"severity\":\"").append(escapeJson(severity)).append("\"");
            dataJson.append(",\"latitude\":\"").append(latitude).append("\"");
            dataJson.append(",\"longitude\":\"").append(longitude).append("\"");
            dataJson.append(",\"timestamp\":\"").append(System.currentTimeMillis()).append("\"");
            if (extraData != null) {
                for (Map.Entry<String, String> entry : extraData.entrySet()) {
                    dataJson.append(",\"").append(escapeJson(entry.getKey())).append("\":\"")
                            .append(escapeJson(entry.getValue())).append("\"");
                }
            }
            dataJson.append("}");

            String json = String.format("""
                {
                  "to": "%s",
                  "priority": "%s",
                  "notification": {
                    "title": "%s",
                    "body": "%s",
                    "sound": "default",
                    "priority": "%s",
                    "channelId": "threat_alerts"
                  },
                  "data": %s
                }
                """,
                escapeJson(fcmToken),
                priority,
                escapeJson(title),
                escapeJson(body),
                priority,
                dataJson.toString()
            );

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(fcmApiUrl))
                    .header("Authorization", "key=" + fcmServerKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .timeout(Duration.ofSeconds(5))
                    .build();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                    .thenAccept(response -> {
                        if (response.statusCode() == 200) {
                            log.debug("FCM threat push sent successfully");
                        } else {
                            log.warn("FCM threat push returned status: {}", response.statusCode());
                        }
                    });
        } catch (Exception e) {
            log.warn("FCM threat send failed: {}", e.getMessage());
        }
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
