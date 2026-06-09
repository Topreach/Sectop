package com.dangeremergence.service;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.SOSAlertRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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

        log.info("Processed new alert: {} for LGA: {}", alert.getId(), alert.getLga());
    }

    private String[] resolveNigeriaGeoInfo(Double lat, Double lng) {
        String state = "Unknown";
        String lga = "Unknown";

        if (lat >= 9.0 && lat <= 9.2 && lng >= 7.3 && lng <= 7.6) {
            state = "FCT";
            lga = "Abuja Municipal";
        } else if (lat >= 6.4 && lat <= 6.7 && lng >= 3.2 && lng <= 3.6) {
            state = "Lagos";
            lga = "Ikeja";
        } else if (lat >= 11.8 && lat <= 12.1 && lng >= 13.1 && lng <= 13.3) {
            state = "Borno";
            lga = "Maiduguri";
        } else if (lat >= 10.4 && lat <= 10.6 && lng >= 7.3 && lng <= 7.5) {
            state = "Kaduna";
            lga = "Kaduna North";
        } else if (lat >= 4.7 && lat <= 4.9 && lng >= 6.9 && lng <= 7.1) {
            state = "Rivers";
            lga = "Port Harcourt";
        }

        return new String[]{state, lga};
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
