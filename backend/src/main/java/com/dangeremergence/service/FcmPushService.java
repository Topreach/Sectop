package com.dangeremergence.service;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.UserRepository;
import com.google.auth.oauth2.GoogleCredentials;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
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
 * Uses FCM HTTP v1 API with OAuth2 authentication via a Firebase Admin SDK
 * service account JSON file.
 *
 * Sends instant push notifications to offline users when an SOS alert
 * is created in their area. This ensures delivery even when the user
 * is not connected to WebSocket.
 *
 * Requires:
 *   - FCM_SERVICE_ACCOUNT_PATH: path to Firebase Admin SDK JSON file
 *   - FCM_PROJECT_ID: your Firebase project ID (e.g., "volunteercoin")
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FcmPushService {

    private final UserRepository userRepository;

    @Value("${fcm.service-account-path:/etc/secrets/firebase-service-account.json}")
    private String serviceAccountPath;

    @Value("${fcm.api-url:https://fcm.googleapis.com/v1/projects/volunteercoin/messages:send}")
    private String fcmApiUrl;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    /** Cache the access token to avoid re-authenticating on every request */
    private volatile String cachedAccessToken;
    private volatile long tokenExpiryTime;

    /**
     * Obtains a valid OAuth2 access token using the Firebase service account JSON file.
     * The token is cached and auto-refreshed when expired.
     */
    private synchronized String getAccessToken() {
        long now = System.currentTimeMillis();
        if (cachedAccessToken != null && now < tokenExpiryTime - 60000) {
            return cachedAccessToken;
        }

        try {
            GoogleCredentials credentials;
            try (FileInputStream fis = new FileInputStream(serviceAccountPath)) {
                credentials = GoogleCredentials.fromStream(fis)
                        .createScoped(List.of("https://www.googleapis.com/auth/firebase.messaging"));
            }

            credentials.refreshIfExpired();
            cachedAccessToken = credentials.getAccessToken().getTokenValue();
            // Tokens typically last 1 hour (3600 seconds), refresh 5 min early
            tokenExpiryTime = now + 3300_000L;
            log.info("FCM: Obtained new OAuth2 access token");
            return cachedAccessToken;
        } catch (Exception e) {
            log.error("FCM: Failed to obtain OAuth2 access token from service account: {}", e.getMessage());
            return null;
        }
    }

    /**
     * Send push notification for a new SOS alert to all nearby users.
     */
    @Async
    public void notifyAlertToNearbyUsers(SOSAlert alert, double radiusKm) {
        String accessToken = getAccessToken();
        if (accessToken == null) {
            log.warn("FCM: No access token available - SKIPPING ALL push notifications for alert {}. "
                    + "Set FCM_SERVICE_ACCOUNT_PATH and FCM_PROJECT_ID environment variables.", alert.getId());
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
                    sendPushNotification(user.getFcmToken(), alert, accessToken);
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
        String accessToken = getAccessToken();
        if (accessToken == null) return;

        try {
            User user = userRepository.findById(userId).orElse(null);
            if (user != null && user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                sendPushNotification(user.getFcmToken(), alert, accessToken);
            }
        } catch (Exception e) {
            log.error("FCM notify user failed: {}", e.getMessage());
        }
    }

    /**
     * Send a discreet FCM push notification for a covert SOS alert.
     * Uses a silent/private notification style so the alert is not obvious
     * to anyone else who might see the recipient's phone screen.
     */
    @Async
    public void sendCovertNotification(User user, SOSAlert alert) {
        String accessToken = getAccessToken();
        if (accessToken == null) return;

        try {
            if (user.getFcmToken() != null && !user.getFcmToken().isEmpty()) {
                String priority = alert.getPriority() >= 9 ? "high" : "normal";
                String body = alert.getDescription() != null
                        ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 200))
                        : "Covert SOS Alert: " + alert.getAlertType();

                String json = String.format("""
                    {
                      "message": {
                        "token": "%s",
                        "notification": {
                          "title": "🔇 Covert SOS - %s",
                          "body": "%s"
                        },
                        "android": {
                          "priority": "%s",
                          "notification": {
                            "sound": "default",
                            "channel_id": "covert_alerts",
                            "priority": "%s",
                            "visibility": "private"
                          }
                        },
                        "apns": {
                          "payload": {
                            "aps": {
                              "sound": "default",
                              "priority": %d,
                              "content-available": 1
                            }
                          }
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
                    }
                    """,
                    escapeJson(user.getFcmToken()),
                    escapeJson(alert.getAlertType()),
                    escapeJson(body),
                    priority,
                    priority,
                    "high".equals(priority) ? 10 : 5,
                    escapeJson(alert.getId()),
                    escapeJson(alert.getAlertType()),
                    alert.getLatitude(),
                    alert.getLongitude(),
                    alert.getPriority(),
                    System.currentTimeMillis()
                );

                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(fcmApiUrl))
                        .header("Authorization", "Bearer " + accessToken)
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(json))
                        .timeout(Duration.ofSeconds(5))
                        .build();

                httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                        .thenAccept(response -> {
                            if (response.statusCode() == 200) {
                                log.debug("FCM covert notification sent to user {}", user.getId());
                            } else {
                                log.warn("FCM covert notification returned status {}: {}", response.statusCode(), response.body());
                            }
                        });
            }
        } catch (Exception e) {
            log.warn("FCM covert notification failed for user {}: {}", user.getId(), e.getMessage());
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
        String accessToken = getAccessToken();
        if (accessToken == null) {
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
                            latitude, longitude, extraData, accessToken);
                }
            }
            log.info("FCM: Notified {} nearby users for threat alert '{}'", nearbyUsers.size(), title);
        } catch (Exception e) {
            log.error("FCM threat notification failed: {}", e.getMessage(), e);
        }
    }

    /**
     * Build and send an FCM HTTP v1 message for an SOS alert.
     *
     * Uses the FCM v1 API format: { "message": { "token": "...", "notification": {...}, "data": {...} } }
     */
    private void sendPushNotification(String fcmToken, SOSAlert alert, String accessToken) {
        try {
            String priority = alert.getPriority() >= 9 ? "high" : "normal";
            String body = alert.getDescription() != null
                    ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 200))
                    : "SOS Alert: " + alert.getAlertType();

            String json = String.format("""
                {
                  "message": {
                    "token": "%s",
                    "notification": {
                      "title": "🚨 SOS Alert - %s",
                      "body": "%s"
                    },
                    "android": {
                      "priority": "%s",
                      "notification": {
                        "sound": "alarm",
                        "channel_id": "sos_alerts",
                        "priority": "%s"
                      }
                    },
                    "apns": {
                      "payload": {
                        "aps": {
                          "sound": "alarm",
                          "priority": %d
                        }
                      }
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
                }
                """,
                escapeJson(fcmToken),
                escapeJson(alert.getAlertType()),
                escapeJson(body),
                priority,
                priority,
                "high".equals(priority) ? 10 : 5,
                escapeJson(alert.getId()),
                escapeJson(alert.getAlertType()),
                alert.getLatitude(),
                alert.getLongitude(),
                alert.getPriority(),
                System.currentTimeMillis()
            );

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(fcmApiUrl))
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .timeout(Duration.ofSeconds(5))
                    .build();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                    .thenAccept(response -> {
                        if (response.statusCode() == 200) {
                            log.debug("FCM v1 push sent successfully");
                        } else {
                            log.warn("FCM v1 push returned status {}: {}", response.statusCode(), response.body());
                        }
                    });
        } catch (Exception e) {
            log.warn("FCM v1 send failed: {}", e.getMessage());
        }
    }

    /**
     * Build and send an FCM HTTP v1 message for a threat alert.
     */
    private void sendThreatPushNotification(
            String fcmToken, String title, String body, String type,
            String severity, double latitude, double longitude,
            Map<String, String> extraData, String accessToken) {
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
                  "message": {
                    "token": "%s",
                    "notification": {
                      "title": "%s",
                      "body": "%s"
                    },
                    "android": {
                      "priority": "%s",
                      "notification": {
                        "sound": "default",
                        "channel_id": "threat_alerts",
                        "priority": "%s"
                      }
                    },
                    "data": %s
                  }
                }
                """,
                escapeJson(fcmToken),
                escapeJson(title),
                escapeJson(body),
                priority,
                priority,
                dataJson.toString()
            );

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(fcmApiUrl))
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json))
                    .timeout(Duration.ofSeconds(5))
                    .build();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                    .thenAccept(response -> {
                        if (response.statusCode() == 200) {
                            log.debug("FCM v1 threat push sent successfully");
                        } else {
                            log.warn("FCM v1 threat push returned status {}: {}", response.statusCode(), response.body());
                        }
                    });
        } catch (Exception e) {
            log.warn("FCM v1 threat send failed: {}", e.getMessage());
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
