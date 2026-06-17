package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.UserRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Service for processing covert SOS alerts.
 *
 * When a covert alert is triggered, this service ensures the alert is ONLY
 * delivered to trusted recipients (emergency contacts + verified responders)
 * and is NOT broadcast to public WebSocket topics, MQTT channels, or
 * general FCM push notifications.
 *
 * This is the core protection against the "kidnapper scenario" where
 * a kidnapper who also has the app installed would otherwise receive
 * the victim's SOS alert and location broadcast.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CovertAlertService {

    private final UserRepository userRepository;
    private final FcmPushService fcmPushService;
    private final SimpMessagingTemplate messagingTemplate;
    private final ObjectMapper objectMapper;

    /**
     * Process a covert SOS alert by delivering it ONLY to trusted recipients:
     * 1. The victim's emergency contacts (stored as JSON in User.emergencyContacts)
     * 2. Verified responders (guardian/responder/coordinator roles) in the area
     *
     * No public broadcast is made — no MQTT, no WebSocket /topic/alerts/new,
     * no Redis pub/sub, no general FCM push.
     */
    public void processCovertAlert(SOSAlert alert) {
        log.info("Processing covert alert {} for user {}", alert.getId(), alert.getUser().getId());

        // 1. Resolve emergency contacts from the victim's profile
        List<User> emergencyContacts = resolveEmergencyContacts(alert.getUser());
        log.info("Covert alert {}: resolved {} emergency contacts", alert.getId(), emergencyContacts.size());

        // 2. Find verified responders near the alert location
        double radiusKm = 50.0; // 50km radius for responder coverage
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(alert.getLatitude())));
        List<User> verifiedResponders = userRepository.findVerifiedRespondersInArea(
                alert.getLatitude() - latDelta,
                alert.getLatitude() + latDelta,
                alert.getLongitude() - lonDelta,
                alert.getLongitude() + lonDelta
        );
        log.info("Covert alert {}: found {} verified responders in area", alert.getId(), verifiedResponders.size());

        // 3. Send discreet FCM push notifications to emergency contacts
        for (User contact : emergencyContacts) {
            if (contact.getFcmToken() != null && !contact.getFcmToken().isEmpty()) {
                fcmPushService.sendCovertNotification(contact, alert);
            }
        }

        // 4. Send discreet FCM push notifications to verified responders
        for (User responder : verifiedResponders) {
            if (responder.getFcmToken() != null && !responder.getFcmToken().isEmpty()) {
                fcmPushService.sendCovertNotification(responder, alert);
            }
        }

        // 5. Send acknowledgment to the victim via their private WebSocket queue
        try {
            messagingTemplate.convertAndSendToUser(
                    alert.getUser().getId(), "/queue/covert-ack", alert);
            log.info("Covert alert {}: acknowledgment sent to user {}", alert.getId(), alert.getUser().getId());
        } catch (Exception e) {
            log.warn("Covert alert {}: failed to send acknowledgment: {}", alert.getId(), e.getMessage());
        }

        log.info("Covert alert {} processed: notified {} contacts and {} responders",
                alert.getId(), emergencyContacts.size(), verifiedResponders.size());
    }

    /**
     * Resolve emergency contacts from the user's profile.
     * Emergency contacts are stored as a JSON array of user IDs in the
     * emergency_contacts column.
     */
    private List<User> resolveEmergencyContacts(User user) {
        if (user.getEmergencyContacts() == null || user.getEmergencyContacts().isEmpty()) {
            return List.of();
        }

        try {
            List<String> contactIds = objectMapper.readValue(
                    user.getEmergencyContacts(),
                    new TypeReference<List<String>>() {}
            );

            if (contactIds.isEmpty()) {
                return List.of();
            }

            return userRepository.findUsersByIds(contactIds);
        } catch (Exception e) {
            log.warn("Failed to parse emergency contacts for user {}: {}", user.getId(), e.getMessage());
            return List.of();
        }
    }
}
