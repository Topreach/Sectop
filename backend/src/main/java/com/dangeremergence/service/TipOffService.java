package com.dangeremergence.service;

import com.dangeremergence.model.TipOff;
import com.dangeremergence.model.TipOff.TipStatus;
import com.dangeremergence.model.TipOff.TipType;
import com.dangeremergence.model.User;
import com.dangeremergence.repository.TipOffRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;

/**
 * Service for managing anonymous tip-offs / intelligence reports.
 * All heavy logic (AI analysis, threat scoring) runs on the backend.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class TipOffService {

    private final TipOffRepository tipOffRepository;
    private final UserRepository userRepository;
    private final MqttService mqttService;
    private final SimpMessagingTemplate messagingTemplate;
    private final NigeriaLocationService nigeriaLocationService;

    /**
     * Submit a new tip-off. Supports anonymous reporting.
     */
    @Transactional
    public TipOff submitTip(String tipType, String description,
                             Double latitude, Double longitude, Double accuracy,
                             LocalDateTime occurredAt, String targetDescription,
                             String suspectDescription, boolean isAnonymous,
                             String reporterId) {
        User reporter = null;
        if (reporterId != null && !isAnonymous) {
            reporter = userRepository.findById(reporterId).orElse(null);
        }

        TipType type;
        try {
            type = TipType.valueOf(tipType != null ? tipType : "other");
        } catch (IllegalArgumentException e) {
            type = TipType.other;
        }

        // Resolve Nigeria geo-info
        String[] geoInfo = resolveNigeriaGeoInfo(latitude, longitude);
        String state = geoInfo[0];
        String lga = geoInfo[1];

        TipOff tipOff = TipOff.builder()
                .id(UUID.randomUUID().toString())
                .tipType(type)
                .description(description)
                .latitude(latitude)
                .longitude(longitude)
                .accuracy(accuracy)
                .state(state)
                .lga(lga)
                .occurredAt(occurredAt != null ? occurredAt : LocalDateTime.now())
                .targetDescription(targetDescription)
                .suspectDescription(suspectDescription)
                .threatScore(0)
                .anonymous(isAnonymous)
                .reporter(reporter)
                .status(TipStatus.pending)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        TipOff saved = tipOffRepository.save(tipOff);
        log.info("Tip-off submitted: {} type={} anonymous={}", saved.getId(), tipType, isAnonymous);

        // Run AI threat analysis asynchronously
        analyzeThreatAsync(saved);

        // Notify coordinators/responders via MQTT (anonymized)
        publishToMqtt(saved);

        return saved;
    }

    /**
     * Get pending tips for review (coordinator/responder only).
     */
    @Transactional(readOnly = true)
    public List<TipOff> getPendingTips() {
        return tipOffRepository.findByStatusesOrderByThreatScoreDesc(
                List.of(TipStatus.pending, TipStatus.under_review));
    }
/**
 * Get recent actionable/forwarded tips for display in the Inbox.
 * Returns tips that have been reviewed as actionable or forwarded,
 * ordered by most recent first. This is a public endpoint so all
 * users can see tips in their Inbox Updates tab.
 */
@Transactional(readOnly = true)
public List<TipOff> getRecentTips() {
    return tipOffRepository.findByStatusesOrderByThreatScoreDesc(
            List.of(TipStatus.actionable, TipStatus.forwarded));
}

/**
 * Get tip-off by ID.
 */
@Transactional(readOnly = true)
public Optional<TipOff> getTipById(String id) {
    return tipOffRepository.findById(id);
}
    }

    /**
     * Review a tip-off (mark as actionable, dismissed, or forwarded).
     */
    @Transactional
    public TipOff reviewTip(String tipId, String reviewerId, String status, String notes) {
        TipOff tipOff = tipOffRepository.findById(tipId)
                .orElseThrow(() -> new RuntimeException("Tip-off not found: " + tipId));

        User reviewer = userRepository.findById(reviewerId)
                .orElseThrow(() -> new RuntimeException("Reviewer not found: " + reviewerId));

        TipStatus newStatus;
        try {
            newStatus = TipStatus.valueOf(status != null ? status.toLowerCase() : "under_review");
        } catch (IllegalArgumentException e) {
            newStatus = TipStatus.under_review;
        }

        tipOff.setStatus(newStatus);
        tipOff.setReviewedBy(reviewer);
        tipOff.setReviewNotes(notes);
        tipOff.setUpdatedAt(LocalDateTime.now());

        TipOff saved = tipOffRepository.save(tipOff);
        log.info("Tip-off {} reviewed by {}: status={}", tipId, reviewerId, status);

        // If actionable and threat score is high, escalate
        if (newStatus == TipStatus.actionable && saved.getThreatScore() >= 50) {
            escalateTip(saved);
        }

        return saved;
    }

    /**
     * Get tip-off statistics.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> getStatistics() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalPending", tipOffRepository.countByStatus(TipStatus.pending));
        stats.put("totalUnderReview", tipOffRepository.countByStatus(TipStatus.under_review));
        stats.put("totalActionable", tipOffRepository.countByStatus(TipStatus.actionable));
        stats.put("totalDismissed", tipOffRepository.countByStatus(TipStatus.dismissed));
        stats.put("totalForwarded", tipOffRepository.countByStatus(TipStatus.forwarded));

        Double avgThreat = tipOffRepository.averageThreatScore(TipStatus.actionable);
        stats.put("averageThreatScore", avgThreat != null ? Math.round(avgThreat * 10) / 10.0 : 0);

        return stats;
    }

    /**
     * Run AI threat analysis on a tip-off.
     * Uses keyword-based scoring as fallback when ML service is unavailable.
     */
    @Async
    protected void analyzeThreatAsync(TipOff tipOff) {
        try {
            int score = calculateThreatScore(tipOff);
            tipOff.setThreatScore(score);
            tipOffRepository.save(tipOff);
            log.info("Tip-off {} threat score: {}", tipOff.getId(), score);

            // Auto-escalate if threat score is very high
            if (score >= 70) {
                escalateTip(tipOff);
            }
        } catch (Exception e) {
            log.warn("Failed to analyze tip-off {}: {}", tipOff.getId(), e.getMessage());
        }
    }

    /**
     * Calculate threat score based on content analysis.
     * Keywords related to terrorism, kidnapping, weapons score higher.
     */
    private int calculateThreatScore(TipOff tipOff) {
        int score = 0;
        String text = (tipOff.getDescription() + " " +
                (tipOff.getTargetDescription() != null ? tipOff.getTargetDescription() : "") + " " +
                (tipOff.getSuspectDescription() != null ? tipOff.getSuspectDescription() : ""))
                .toLowerCase();

        // High-threat keywords (score +20 each)
        String[] highThreatKeywords = {
                "bomb", "explosive", "kidnap", "abduct", "attack", "terrorist",
                "gun", "rifle", "ak-47", "weapon", "massacre", "slaughter",
                "suicide", "ied", "ambush", "raid"
        };

        // Medium-threat keywords (score +10 each)
        String[] mediumThreatKeywords = {
                "suspicious", "stranger", "follow", "watch", "plan", "plot",
                "hide", "weapon", "machete", "knife", "threat", "danger",
                "motorcycle", "camp", "forest", "border"
        };

        // Low-threat keywords (score +5 each)
        String[] lowThreatKeywords = {
                "unusual", "different", "new people", "vehicle", "truck",
                "movement", "night", "dark", "unknown"
        };

        for (String keyword : highThreatKeywords) {
            if (text.contains(keyword)) score += 20;
        }

        for (String keyword : mediumThreatKeywords) {
            if (text.contains(keyword)) score += 10;
        }

        for (String keyword : lowThreatKeywords) {
            if (text.contains(keyword)) score += 5;
        }

        // Boost score based on tip type
        if (tipOff.getTipType() == TipType.bombing_plot ||
            tipOff.getTipType() == TipType.kidnapping_plot) {
            score += 15;
        }

        // Boost score if location is provided
        if (tipOff.getLatitude() != null && tipOff.getLongitude() != null) {
            score += 10;
        }

        // Boost score if suspect description is detailed
        if (tipOff.getSuspectDescription() != null &&
            tipOff.getSuspectDescription().length() > 50) {
            score += 10;
        }

        return Math.min(100, score);
    }

    /**
     * Escalate a high-threat tip by notifying all coordinators and responders.
     */
    private void escalateTip(TipOff tipOff) {
        try {
            Map<String, Object> alert = new HashMap<>();
            alert.put("type", "TIP_ESCALATION");
            alert.put("tipId", tipOff.getId());
            alert.put("tipType", tipOff.getTipType().name());
            alert.put("threatScore", tipOff.getThreatScore());
            alert.put("description", tipOff.getDescription());
            alert.put("latitude", tipOff.getLatitude());
            alert.put("longitude", tipOff.getLongitude());
            alert.put("state", tipOff.getState());
            alert.put("lga", tipOff.getLga());
            alert.put("timestamp", LocalDateTime.now().toString());

            // Publish to MQTT
            mqttService.publish("tips/escalated", alert);

            // Publish to WebSocket
            messagingTemplate.convertAndSend("/topic/tips/escalated", alert);

            log.info("Tip-off {} escalated with threat score {}", tipOff.getId(), tipOff.getThreatScore());
        } catch (Exception e) {
            log.warn("Failed to escalate tip-off: {}", e.getMessage());
        }
    }

    /**
     * Publish anonymized tip notification via MQTT.
     */
    private void publishToMqtt(TipOff tipOff) {
        try {
            Map<String, Object> anonymized = new HashMap<>();
            anonymized.put("id", tipOff.getId());
            anonymized.put("tipType", tipOff.getTipType().name());
            anonymized.put("description", tipOff.getDescription());
            anonymized.put("latitude", tipOff.getLatitude());
            anonymized.put("longitude", tipOff.getLongitude());
            anonymized.put("state", tipOff.getState());
            anonymized.put("lga", tipOff.getLga());
            anonymized.put("threatScore", tipOff.getThreatScore());
            anonymized.put("status", tipOff.getStatus().name());
            anonymized.put("createdAt", tipOff.getCreatedAt().toString());
            // No reporter info included

            mqttService.publish("tips/new", anonymized);
            messagingTemplate.convertAndSend("/topic/tips", anonymized);
        } catch (Exception e) {
            log.warn("Failed to publish tip-off notification: {}", e.getMessage());
        }
    }

    /**
     * Resolve Nigeria State and LGA from GPS coordinates.
     * Delegates to NigeriaLocationService for accurate state/LGA resolution.
     */
    private String[] resolveNigeriaGeoInfo(Double latitude, Double longitude) {
        if (latitude == null || longitude == null) {
            return new String[]{"Unknown", "Unknown"};
        }
        return nigeriaLocationService.resolve(latitude, longitude);
    }
}
