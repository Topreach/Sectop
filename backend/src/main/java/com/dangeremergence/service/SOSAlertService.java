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

    @Transactional
    public SOSAlert createAlert(String userId, String alertType, String description,
                                 Double latitude, Double longitude, Double accuracy, int priority) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found: " + userId));

        SOSAlert alert = SOSAlert.builder()
                .id(UUID.randomUUID().toString())
                .user(user)
                .alertType(alertType)
                .description(description)
                .latitude(latitude)
                .longitude(longitude)
                .accuracy(accuracy)
                .priority(priority)
                .status(SOSAlert.AlertStatus.active)
                .meshRelayed(false)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        SOSAlert saved = alertRepository.save(alert);
        log.info("SOS alert created: {} (type={}, priority={})", saved.getId(), alertType, priority);

        // Trigger async processing
        processNewAlert(saved);

        return saved;
    }

    @Async
    protected void processNewAlert(SOSAlert alert) {
        // 1. Notify nearby responders
        // 2. Broadcast via WebSocket to subscribed clients
        // 3. Trigger push notifications
        // 4. Log for analytics
        log.info("Processing new alert: {}", alert.getId());
    }

    @Transactional
    public SOSAlert acknowledgeAlert(String alertId, String responderId) {
        SOSAlert alert = alertRepository.findById(alertId)
                .orElseThrow(() -> new RuntimeException("Alert not found: " + alertId));

        alert.setStatus(SOSAlert.AlertStatus.acknowledged);
        alert.setAcknowledgedBy(responderId);
        alert.setUpdatedAt(LocalDateTime.now());

        SOSAlert saved = alertRepository.save(alert);
        log.info("Alert {} acknowledged by {}", alertId, responderId);
        return saved;
    }

    @Transactional
    public SOSAlert resolveAlert(String alertId) {
        SOSAlert alert = alertRepository.findById(alertId)
                .orElseThrow(() -> new RuntimeException("Alert not found: " + alertId));

        alert.setStatus(SOSAlert.AlertStatus.resolved);
        alert.setResolvedAt(LocalDateTime.now());
        alert.setUpdatedAt(LocalDateTime.now());

        SOSAlert saved = alertRepository.save(alert);
        log.info("Alert {} resolved", alertId);
        return saved;
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
        List<SOSAlert> expired = alertRepository.findExpiredAlerts(
                SOSAlert.AlertStatus.active, expiryThreshold);
        
        for (SOSAlert alert : expired) {
            alert.setStatus(SOSAlert.AlertStatus.expired);
            alert.setUpdatedAt(LocalDateTime.now());
        }
        
        alertRepository.saveAll(expired);
        log.info("Expired {} alerts", expired.size());
    }

    @Transactional(readOnly = true)
    public long getActiveAlertCount() {
        return alertRepository.countByStatus(SOSAlert.AlertStatus.active);
    }
}
