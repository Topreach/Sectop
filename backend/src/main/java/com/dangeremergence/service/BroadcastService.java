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
     * Create a new broadcast with backend validation and publish via MQTT + WebSocket.
     *
     * @throws IllegalArgumentException if validation fails
     */
    @Transactional
    public Broadcast createBroadcast(String title, String message, String severity,
                                      String broadcastType, String targetState, String targetLga,
                                      String targetRoles, Double latitude, Double longitude,
                                      Double radiusKm, String createdById, LocalDateTime expiresAt) {
        // --- Validation ---
        if (title == null || title.trim().isEmpty()) {
            throw new IllegalArgumentException("Title is required");
        }
        if (title.length() > 200) {
            throw new IllegalArgumentException("Title must be 200 characters or less");
        }
        if (message == null || message.trim().isEmpty()) {
            throw new IllegalArgumentException("Message is required");
        }
        if (message.length() > 5000) {
            throw new IllegalArgumentException("Message must be 5000 characters or less");
        }

        // Validate severity
        BroadcastSeverity sev;
        if (severity == null || severity.trim().isEmpty()) {
            throw new IllegalArgumentException("Severity is required (info, warning, urgent, critical)");
        }
        try {
            sev = BroadcastSeverity.valueOf(severity.toLowerCase());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Invalid severity: '" + severity
                    + "'. Must be one of: info, warning, urgent, critical");
        }

        // Validate broadcast type
        BroadcastType type;
        if (broadcastType == null || broadcastType.trim().isEmpty()) {
            throw new IllegalArgumentException("Broadcast type is required");
        }
        try {
            type = BroadcastType.valueOf(broadcastType.toLowerCase());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Invalid broadcast type: '" + broadcastType
                    + "'. Must be one of: general, evacuation, curfew, manhunt, school_closure, weather, security");
        }

        // Validate target state/LGA (if provided, they should be reasonable)
        if (targetState != null && targetState.trim().isEmpty()) {
            targetState = null;
        }
        if (targetLga != null && targetLga.trim().isEmpty()) {
            targetLga = null;
        }
        if (targetState != null && targetState.length() > 100) {
            throw new IllegalArgumentException("Target state name is too long");
        }
        if (targetLga != null && targetLga.length() > 100) {
            throw new IllegalArgumentException("Target LGA name is too long");
        }

        // Validate coordinates (if provided)
        if (latitude != null && (latitude < -90 || latitude > 90)) {
            throw new IllegalArgumentException("Invalid latitude: must be between -90 and 90");
        }
        if (longitude != null && (longitude < -180 || longitude > 180)) {
            throw new IllegalArgumentException("Invalid longitude: must be between -180 and 180");
        }
        if (radiusKm != null && (radiusKm < 0 || radiusKm > 1000)) {
            throw new IllegalArgumentException("Radius must be between 0 and 1000 km");
        }

        // Validate expiration
        if (expiresAt != null && expiresAt.isBefore(LocalDateTime.now())) {
            throw new IllegalArgumentException("Expiration time must be in the future");
        }

        // Resolve creator
        User creator = createdById != null ?
                userRepository.findById(createdById).orElse(null) : null;

        Broadcast broadcast = Broadcast.builder()
                .id(UUID.randomUUID().toString())
                .title(title.trim())
                .message(message.trim())
                .severity(sev)
                .broadcastType(type)
                .targetState(targetState)
                .targetLga(targetLga)
                .targetRoles(targetRoles)
                .latitude(latitude)
                .longitude(longitude)
                .radiusKm(radiusKm)
                .createdBy(creator)
                .isActive(true)
                .expiresAt(expiresAt)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        Broadcast saved = broadcastRepository.save(broadcast);
        log.info("Broadcast created: {} severity={} type={} target={}/{}",
                saved.getId(), sev, type, targetState, targetLga);

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
