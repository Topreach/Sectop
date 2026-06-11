package com.dangeremergence.service;

import com.dangeremergence.model.Broadcast;
import com.dangeremergence.model.Broadcast.BroadcastSeverity;
import com.dangeremergence.model.Broadcast.BroadcastType;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.BroadcastRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;

/**
 * Service for managing mass alert broadcasts.
 * All heavy logic runs on the backend; frontend is a thin client.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class BroadcastService {

    private final BroadcastRepository broadcastRepository;
    private final UserRepository userRepository;
    private final MqttService mqttService;
    private final SimpMessagingTemplate messagingTemplate;

    /**
     * Create a new broadcast and publish via MQTT + WebSocket.
     */
    @Transactional
    public Broadcast createBroadcast(String title, String message, String severity,
                                      String broadcastType, String targetState, String targetLga,
                                      String targetRoles, Double latitude, Double longitude,
                                      Double radiusKm, String createdById, LocalDateTime expiresAt) {
        User creator = createdById != null ?
                userRepository.findById(createdById).orElse(null) : null;

        BroadcastSeverity sev;
        try {
            sev = BroadcastSeverity.valueOf(severity != null ? severity.toLowerCase() : "urgent");
        } catch (IllegalArgumentException e) {
            sev = BroadcastSeverity.urgent;
        }

        BroadcastType type;
        try {
            type = BroadcastType.valueOf(broadcastType != null ? broadcastType.toLowerCase() : "general");
        } catch (IllegalArgumentException e) {
            type = BroadcastType.general;
        }

        Broadcast broadcast = Broadcast.builder()
                .id(UUID.randomUUID().toString())
                .title(title)
                .message(message)
                .severity(sev)
                .broadcastType(type)
                .targetState(targetState)
                .targetLga(targetLga)
                .targetRoles(targetRoles)
                .latitude(latitude)
                .longitude(longitude)
                .radiusKm(radiusKm)
                .createdBy(creator)
                .active(true)
                .expiresAt(expiresAt)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        Broadcast saved = broadcastRepository.save(broadcast);
        log.info("Broadcast created: {} severity={} type={} target={}/{}",
                saved.getId(), severity, broadcastType, targetState, targetLga);

        // Publish via MQTT for IoT/mesh devices
        publishToMqtt(saved);

        // Publish via WebSocket for connected clients
        publishToWebSocket(saved);

        return saved;
    }

    /**
     * Get active broadcasts filtered by location.
     */
    @Transactional(readOnly = true)
    public List<Broadcast> getActiveBroadcasts(String state, String lga) {
        LocalDateTime now = LocalDateTime.now();
        if (state != null || lga != null) {
            return broadcastRepository.findActiveBroadcastsForLocation(state, lga, now);
        }
        return broadcastRepository.findAllActiveBroadcasts(now);
    }

    /**
     * Get broadcast by ID.
     */
    @Transactional(readOnly = true)
    public Optional<Broadcast> getBroadcastById(String id) {
        return broadcastRepository.findById(id);
    }

    /**
     * Expire a broadcast (mark as inactive).
     */
    @Transactional
    public void expireBroadcast(String id) {
        broadcastRepository.findById(id).ifPresent(broadcast -> {
            broadcast.setActive(false);
            broadcast.setUpdatedAt(LocalDateTime.now());
            broadcastRepository.save(broadcast);
            log.info("Broadcast expired: {}", id);
        });
    }

    /**
     * Get active broadcast count.
     */
    @Transactional(readOnly = true)
    public long getActiveBroadcastCount() {
        return broadcastRepository.countByIsActiveTrue();
    }

    /**
     * Publish broadcast to MQTT for mesh/IoT devices.
     */
    private void publishToMqtt(Broadcast broadcast) {
        try {
            String stateSlug = broadcast.getTargetState() != null ?
                    broadcast.getTargetState().toLowerCase().replace(" ", "_") : "all";
            String lgaSlug = broadcast.getTargetLga() != null ?
                    broadcast.getTargetLga().toLowerCase().replace(" ", "_") : "all";

            // Publish to general topic
            mqttService.publish("broadcasts/new", broadcast);

            // Publish to location-specific topics
            mqttService.publish("broadcasts/state/" + stateSlug, broadcast);
            mqttService.publish("broadcasts/lga/" + lgaSlug, broadcast);

            log.debug("Broadcast published to MQTT topics");
        } catch (Exception e) {
            log.warn("Failed to publish broadcast to MQTT: {}", e.getMessage());
        }
    }

    /**
     * Publish broadcast to WebSocket for real-time frontend delivery.
     */
    private void publishToWebSocket(Broadcast broadcast) {
        try {
            Map<String, Object> payload = new HashMap<>();
            payload.put("id", broadcast.getId());
            payload.put("title", broadcast.getTitle());
            payload.put("message", broadcast.getMessage());
            payload.put("severity", broadcast.getSeverity().name());
            payload.put("broadcastType", broadcast.getBroadcastType().name());
            payload.put("targetState", broadcast.getTargetState());
            payload.put("targetLga", broadcast.getTargetLga());
            payload.put("latitude", broadcast.getLatitude());
            payload.put("longitude", broadcast.getLongitude());
            payload.put("createdAt", broadcast.getCreatedAt().toString());

            messagingTemplate.convertAndSend("/topic/broadcasts", payload);
            log.debug("Broadcast published to WebSocket /topic/broadcasts");
        } catch (Exception e) {
            log.warn("Failed to publish broadcast to WebSocket: {}", e.getMessage());
        }
    }
}
