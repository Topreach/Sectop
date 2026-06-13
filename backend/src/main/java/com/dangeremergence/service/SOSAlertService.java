package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.SOSAlertRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class SOSAlertService {

    private final SOSAlertRepository alertRepository;
    private final UserRepository userRepository;
    private final MqttService mqttService;
    private final DroneService droneService;
    private final SimpMessagingTemplate messagingTemplate;
    private final AlertPubSubService alertPubSubService;
    private final FcmPushService fcmPushService;
    private final SmsGatewayService smsGatewayService;
    private final NigeriaLocationService nigeriaLocationService;

    @Transactional
    public SOSAlert createAlert(String userId, String alertType, String description,
                                 Double latitude, Double longitude, Double accuracy,
                                 int priority, boolean isSilent) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found: " + userId));

        // Resolve State and LGA for Nigeria
        String[] geoInfo = resolveNigeriaGeoInfo(latitude, longitude);
        String state = geoInfo[0];
        String lga = geoInfo[1];

        SOSAlert alert = SOSAlert.builder()
                .id(UUID.randomUUID().toString())
                .user(user)
                .alertType(alertType)
                .description(description)
                .latitude(latitude)
                .longitude(longitude)
                .accuracy(accuracy)
                .state(state)
                .lga(lga)
                .priority(priority)
                .silent(isSilent)
                .status(SOSAlert.AlertStatus.active)
                .meshRelayed(false)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        SOSAlert saved = alertRepository.save(alert);
        log.info("SOS alert created: {} in {}, {} (silent={})", saved.getId(), lga, state, isSilent);

        // Trigger async processing
        processNewAlert(saved);

        return saved;
    }

    @Async
    protected void processNewAlert(SOSAlert alert) {
        // 1. Notify nearby responders via MQTT (fastest) - Localized Topic
        String stateSlug = alert.getState().toLowerCase().replace(" ", "_");
        String lgaSlug = alert.getLga().toLowerCase().replace(" ", "_");
        
        String geoTopic = String.format("alerts/%s/%s", stateSlug, lgaSlug);
        mqttService.publish(geoTopic, alert);

        // Notify Community Guardians
        String guardianTopic = String.format("guardians/%s/%s", stateSlug, lgaSlug);
        mqttService.publish(guardianTopic, alert);
        
        mqttService.publishAlert(alert);
        
        // 2. Trigger Drone Relay if in high-risk area
        droneService.deployRelayIfNecessary(alert.getLga(), alert.getState(),
            alert.getLatitude(), alert.getLongitude(), alert.getPriority());

        // 3. Push via WebSocket/STOMP for real-time delivery to connected clients
        try {
            // Push to global alert topic (all connected clients)
            messagingTemplate.convertAndSend("/topic/alerts/new", alert);

            // Push to geo-specific topic for state/LGA filtering
            String geoDest = String.format("/topic/alerts/%s/%s", stateSlug, lgaSlug);
            messagingTemplate.convertAndSend(geoDest, alert);

            // Push to user-specific queue for the alert creator
            String userId = alert.getUser().getId();
            messagingTemplate.convertAndSendToUser(userId, "/queue/alerts", alert);

            log.info("WebSocket push sent for alert: {} to user: {}", alert.getId(), userId);
        } catch (Exception e) {
            log.warn("WebSocket push failed for alert {}: {}", alert.getId(), e.getMessage());
        }

        // 4. Publish to Redis pub/sub for cross-server broadcast (all instances)
        alertPubSubService.publishAlert(alert);
        alertPubSubService.publishGeoAlert(alert, stateSlug, lgaSlug);

        // 5. Send FCM push notifications to nearby users (offline delivery)
        fcmPushService.notifyAlertToNearbyUsers(alert, 10.0);

        // 6. Send SMS to the alert creator's phone as last-resort confirmation
        User alertUser = alert.getUser();
        if (alertUser.getPhone() != null && !alertUser.getPhone().isEmpty()) {
            smsGatewayService.sendAlertSms(alert, alertUser.getPhone());
        }

        log.info("Processed new alert: {} for LGA: {}", alert.getId(), alert.getLga());
    }

    /**
     * Push an alert to WebSocket/STOMP clients on this server instance.
     * Called by AlertPubSubService when an alert is received via Redis pub/sub
     * from another server instance.
     */
    public void pushAlertToWebSocket(SOSAlert alert) {
        try {
            String stateSlug = alert.getState() != null
                    ? alert.getState().toLowerCase().replace(" ", "_") : "unknown";
            String lgaSlug = alert.getLga() != null
                    ? alert.getLga().toLowerCase().replace(" ", "_") : "unknown";

            // Push to global alert topic
            messagingTemplate.convertAndSend("/topic/alerts/new", alert);

            // Push to geo-specific topic
            String geoDest = String.format("/topic/alerts/%s/%s", stateSlug, lgaSlug);
            messagingTemplate.convertAndSend(geoDest, alert);

            // Push to user-specific queue if user is available
            if (alert.getUser() != null && alert.getUser().getId() != null) {
                messagingTemplate.convertAndSendToUser(alert.getUser().getId(), "/queue/alerts", alert);
            }

            log.debug("Cross-server WebSocket push for alert: {}", alert.getId());
        } catch (Exception e) {
            log.warn("Cross-server WebSocket push failed for alert {}: {}", alert.getId(), e.getMessage());
        }
    }

    private String[] resolveNigeriaGeoInfo(Double lat, Double lng) {
        if (lat == null || lng == null) {
            return new String[]{"Unknown", "Unknown"};
        }
        return nigeriaLocationService.resolve(lat, lng);
    }

    @Transactional
    public SOSAlert acknowledgeAlert(String alertId, String responderId) {
        SOSAlert alert = alertRepository.findById(alertId)
                .orElseThrow(() -> new RuntimeException("Alert not found: " + alertId));
        alert.setStatus(SOSAlert.AlertStatus.acknowledged);
        alert.setAcknowledgedBy(responderId);
        alert.setUpdatedAt(LocalDateTime.now());
        return alertRepository.save(alert);
    }

    @Transactional
    public SOSAlert resolveAlert(String alertId) {
        SOSAlert alert = alertRepository.findById(alertId)
                .orElseThrow(() -> new RuntimeException("Alert not found: " + alertId));
        alert.setStatus(SOSAlert.AlertStatus.resolved);
        alert.setResolvedAt(LocalDateTime.now());
        alert.setUpdatedAt(LocalDateTime.now());
        return alertRepository.save(alert);
    }

    @Transactional(readOnly = true)
    public List<SOSAlert> getActiveAlerts() {
        return alertRepository.findByStatusOrderByPriorityDescCreatedAtDesc(SOSAlert.AlertStatus.active);
    }

    @Transactional(readOnly = true)
    public List<SOSAlert> getAlertsForUser(String userId) {
        return alertRepository.findByUserIdOrderByCreatedAtDesc(userId);
    }

    @Transactional(readOnly = true)
    public List<SOSAlert> getAlertsInArea(double latitude, double longitude, double radiusKm) {
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(latitude)));
        return alertRepository.findAlertsInArea(
                latitude - latDelta, latitude + latDelta,
                longitude - lonDelta, longitude + lonDelta,
                SOSAlert.AlertStatus.active
        );
    }

    @Transactional(readOnly = true)
    public List<SOSAlert> getAlertsSince(LocalDateTime since) {
        return alertRepository.findActiveAlertsSince(SOSAlert.AlertStatus.active, since);
    }

    @Transactional
    public void cleanupExpiredAlerts() {
        LocalDateTime expiryThreshold = LocalDateTime.now().minusHours(24);
        List<SOSAlert> expired = alertRepository.findExpiredAlerts(SOSAlert.AlertStatus.active, expiryThreshold);
        for (SOSAlert alert : expired) {
            alert.setStatus(SOSAlert.AlertStatus.expired);
            alert.setUpdatedAt(LocalDateTime.now());
        }
        alertRepository.saveAll(expired);
    }

    @Transactional(readOnly = true)
    public long getActiveAlertCount() {
        return alertRepository.countByStatus(SOSAlert.AlertStatus.active);
    }
}
