package com.dangeremergence.sos.service;

import com.dangeremergence.sos.model.SOSAlert;
import com.dangeremergence.sos.model.User;
import com.dangeremergence.sos.repository.UserRepository;
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
 * Firebase Cloud Messaging (FCM) push notification service for the SOS microservice.
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

    @Async
    public void notifyAlertToNearbyUsers(SOSAlert alert, double radiusKm) {
        if (fcmServerKey == null || fcmServerKey.isEmpty()) {
            log.debug("FCM not configured - skipping push notification");
            return;
        }

        try {
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

            String json = "{" +
                "\"to\":\"" + fcmToken + "\"," +
                "\"priority\":\"normal\"," +
                "\"notification\":{" +
                    "\"title\":\"Alert from Emergency Contact\"," +
                    "\"body\":\"A contact needs your assistance. Open the app for details.\"," +
                    "\"sound\":\"default\"," +
                    "\"priority\":\"low\"," +
                    "\"channelId\":\"covert_alerts\"" +
                "}," +
                "\"data\":{" +
                    "\"type\":\"covert_sos\"," +
                    "\"alertId\":\"" + alert.getId() + "\"," +
                    "\"alertType\":\"" + alert.getAlertType() + "\"," +
                    "\"latitude\":\"" + alert.getLatitude() + "\"," +
                    "\"longitude\":\"" + alert.getLongitude() + "\"," +
                    "\"priority\":\"" + alert.getPriority() + "\"," +
                    "\"covert\":\"true\"" +
                "}" +
            "}";

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
                            log.debug("Covert FCM sent to user {}", recipient.getId());
                        } else {
                            log.warn("Covert FCM returned status: {}", response.statusCode());
                        }
                    });
        } catch (Exception e) {
            log.error("Failed to send covert notification: {}", e.getMessage());
        }
    }

    private void sendPushNotification(String fcmToken, SOSAlert alert) {
        try {
            String alertType = alert.getAlertType() != null ? alert.getAlertType() : "Emergency";
            String title = "\uD83D\uDEA8 " + alertType.substring(0, 1).toUpperCase()
                    + alertType.substring(1) + " Alert";
            String body = alert.getDescription() != null
                    ? alert.getDescription().substring(0, Math.min(alert.getDescription().length(), 150))
                    : "An emergency alert has been triggered in your area";

            String json = "{" +
                "\"to\":\"" + fcmToken + "\"," +
                "\"priority\":\"high\"," +
                "\"notification\":{" +
                    "\"title\":\"" + jsonEscape(title) + "\"," +
                    "\"body\":\"" + jsonEscape(body) + "\"," +
                    "\"sound\":\"default\"," +
                    "\"priority\":\"high\"," +
                    "\"channelId\":\"sos_alerts\"" +
                "}," +
                "\"data\":{" +
                    "\"type\":\"sos_alert\"," +
                    "\"alertId\":\"" + alert.getId() + "\"," +
                    "\"alertType\":\"" + alert.getAlertType() + "\"," +
                    "\"latitude\":\"" + alert.getLatitude() + "\"," +
                    "\"longitude\":\"" + alert.getLongitude() + "\"," +
                    "\"priority\":\"" + alert.getPriority() + "\"," +
                    "\"covert\":\"false\"" +
                "}" +
            "}";

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
                            log.debug("FCM push sent for alert {}", alert.getId());
                        } else {
                            log.warn("FCM push returned status: {}", response.statusCode());
                        }
                    });
        } catch (Exception e) {
            log.error("Failed to send FCM push: {}", e.getMessage());
        }
    }

    private String jsonEscape(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
