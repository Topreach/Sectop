package com.dangeremergence.sos.service;

import com.dangeremergence.sos.model.SOSAlert;
import com.dangeremergence.sos.model.User;
import com.dangeremergence.sos.repository.UserRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Service for processing covert SOS alerts.
 * Delivers alerts ONLY to trusted recipients — no public broadcast.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CovertAlertService {

    private final UserRepository userRepository;
    private final FcmPushService fcmPushService;
    private final SimpMessagingTemplate messagingTemplate;
    private final ObjectMapper objectMapper;

    public void processCovertAlert(SOSAlert alert) {
        log.info("Processing covert alert {} for user {}", alert.getId(), alert.getUserId());

        List<User> emergencyContacts = resolveEmergencyContacts(alert.getUserId());
        log.info("Covert alert {}: resolved {} emergency contacts", alert.getId(), emergencyContacts.size());

        double radiusKm = 50.0;
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(alert.getLatitude())));
        List<User> verifiedResponders = userRepository.findVerifiedRespondersInArea(
                alert.getLatitude() - latDelta,
                alert.getLatitude() + latDelta,
                alert.getLongitude() - lonDelta,
                alert.getLongitude() + lonDelta
        );
        log.info("Covert alert {}: found {} verified responders in area", alert.getId(), verifiedResponders.size());

        for (User contact : emergencyContacts) {
            if (contact.getFcmToken() != null && !contact.getFcmToken().isEmpty()) {
                fcmPushService.sendCovertNotification(contact, alert);
            }
        }

        for (User responder : verifiedResponders) {
            if (responder.getFcmToken() != null && !responder.getFcmToken().isEmpty()) {
                fcmPushService.sendCovertNotification(responder, alert);
            }
        }

        try {
            messagingTemplate.convertAndSendToUser(
                    alert.getUserId(), "/queue/covert-ack", alert);
            log.info("Covert alert {}: acknowledgment sent to user {}", alert.getId(), alert.getUserId());
        } catch (Exception e) {
            log.warn("Covert alert {}: failed to send acknowledgment: {}", alert.getId(), e.getMessage());
        }

        log.info("Covert alert {} processed: notified {} contacts and {} responders",
                alert.getId(), emergencyContacts.size(), verifiedResponders.size());
    }

    private List<User> resolveEmergencyContacts(String userId) {
        User user = userRepository.findById(userId).orElse(null);
        if (user == null || user.getEmergencyContacts() == null || user.getEmergencyContacts().isEmpty()) {
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
            log.warn("Failed to parse emergency contacts for user {}: {}", userId, e.getMessage());
            return List.of();
        }
    }
}
