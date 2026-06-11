package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
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
            log.debug("FCM not configured - skipping push notification");
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

            for (User user : nearbyUsers) {
                if (user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                    sendPushNotification(user.getFcmToken(), alert);
                }
            }
            log.info("FCM: Notified {} nearby users for alert {}", nearbyUsers.size(), alert.getId());
        } catch (Exception e) {
            log.error("FCM push failed for alert {}: {}", alert.getId(), e.getMessage());
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
