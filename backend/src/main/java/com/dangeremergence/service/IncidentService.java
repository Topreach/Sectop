package com.dangeremergence.service;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.Incident.IncidentSeverity;
import com.dangeremergence.model.Incident.IncidentStatus;
import com.dangeremergence.model.User;
import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.IncidentRepository;
import com.dangeremergence.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class IncidentService {

    private final IncidentRepository incidentRepository;
    private final UserRepository userRepository;
    private final MqttService mqttService;
    private final ZoneService zoneService;
    private final NigeriaLocationService nigeriaLocationService;

    /**
     * Create a new incident report. Supports anonymous reporting.
     */
    @Transactional
    public Incident createIncident(String reporterId, String incidentType, String description,
                                    Double latitude, Double longitude, Double accuracy,
                                    LocalDateTime occurredAt, String severity,
                                    boolean isAnonymous) {
        User reporter = null;
        if (reporterId != null && !isAnonymous) {
            reporter = userRepository.findById(reporterId)
                    .orElse(null);
        }

        // Resolve State and LGA for Nigeria
        String[] geoInfo = resolveNigeriaGeoInfo(latitude, longitude);
        String state = geoInfo[0];
        String lga = geoInfo[1];

        IncidentSeverity incidentSeverity;
        try {
            incidentSeverity = IncidentSeverity.valueOf(severity != null ? severity.toLowerCase() : "medium");
        } catch (IllegalArgumentException e) {
            incidentSeverity = IncidentSeverity.medium;
        }

        Incident incident = Incident.builder()
                .id(UUID.randomUUID().toString())
                .reporter(reporter)
                .incidentType(incidentType)
                .description(description)
                .latitude(latitude)
                .longitude(longitude)
                .accuracy(accuracy)
                .state(state)
                .lga(lga)
                .occurredAt(occurredAt != null ? occurredAt : LocalDateTime.now())
                .severity(incidentSeverity)
                .anonymous(isAnonymous)
                .verified(false)
                .status(IncidentStatus.reported)
                .upvoteCount(0)
                .witnessCount(0)
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        Incident saved = incidentRepository.save(incident);
        log.info("Incident reported: {} type={} in {}, {} (anonymous={})",
                saved.getId(), incidentType, lga, state, isAnonymous);

        // Notify via MQTT for real-time alerts
        notifyNewIncident(saved);

        return saved;
    }

    /**
     * Get verified incidents near a location within a radius.
     */
    public List<Incident> getNearbyIncidents(double latitude, double longitude,
                                              double radiusKm, List<String> types) {
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(latitude)));

        double minLat = latitude - latDelta;
        double maxLat = latitude + latDelta;
        double minLon = longitude - lonDelta;
        double maxLon = longitude + lonDelta;

        if (types != null && !types.isEmpty()) {
            return incidentRepository.findIncidentsInAreaByType(
                    minLat, maxLat, minLon, maxLon,
                    IncidentStatus.verified, types);
        }
        return incidentRepository.findIncidentsInArea(
                minLat, maxLat, minLon, maxLon,
                IncidentStatus.verified);
    }

    /**
     * Get heatmap data: aggregated incident counts per grid cell.
     * Returns list of {lat, lng, count, maxSeverity} for visualization.
     */
    public List<Map<String, Object>> getHeatmapData(double latitude, double longitude,
                                                     double radiusKm, LocalDateTime since) {
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(latitude)));

        double minLat = latitude - latDelta;
        double maxLat = latitude + latDelta;
        double minLon = longitude - lonDelta;
        double maxLon = longitude + lonDelta;

        List<Incident> incidents;
        if (since != null) {
            incidents = incidentRepository.findIncidentsSince(since, IncidentStatus.verified);
        } else {
            incidents = incidentRepository.findIncidentsInArea(
                    minLat, maxLat, minLon, maxLon,
                    IncidentStatus.verified);
        }

        // Aggregate into ~0.01 degree grid cells (~1km at equator)
        Map<String, Map<String, Object>> grid = new HashMap<>();
        double gridSize = 0.01;

        for (Incident inc : incidents) {
            double gridLat = Math.round(inc.getLatitude() / gridSize) * gridSize;
            double gridLng = Math.round(inc.getLongitude() / gridSize) * gridSize;
            String key = String.format("%.4f,%.4f", gridLat, gridLng);

            Map<String, Object> cell = grid.computeIfAbsent(key, k -> {
                Map<String, Object> c = new HashMap<>();
                c.put("latitude", gridLat);
                c.put("longitude", gridLng);
                c.put("count", 0);
                c.put("maxSeverity", 0);
                c.put("types", new HashSet<String>());
                return c;
            });

            cell.put("count", (int) cell.get("count") + 1);

            int sev = severityToInt(inc.getSeverity());
            if (sev > (int) cell.get("maxSeverity")) {
                cell.put("maxSeverity", sev);
            }

            @SuppressWarnings("unchecked")
            Set<String> types = (Set<String>) cell.get("types");
            types.add(inc.getIncidentType());
        }

        return new ArrayList<>(grid.values());
    }

    /**
     * Verify an incident (mark as confirmed by authorities).
     */
    @Transactional
    public Incident verifyIncident(String incidentId, String verifiedByUserId) {
        Incident incident = incidentRepository.findById(incidentId)
                .orElseThrow(() -> new RuntimeException("Incident not found: " + incidentId));

        incident.setVerified(true);
        incident.setVerifiedBy(verifiedByUserId);
        incident.setStatus(IncidentStatus.verified);
        incident.setUpdatedAt(LocalDateTime.now());

        Incident saved = incidentRepository.save(incident);
        log.info("Incident verified: {} by {}", incidentId, verifiedByUserId);

        // Auto-create danger zone if severity is high/critical
        if (saved.getSeverity() == IncidentSeverity.high ||
            saved.getSeverity() == IncidentSeverity.critical) {
            autoCreateDangerZone(saved);
        }

        return saved;
    }

    /**
     * Upvote an incident (community validation).
     */
    @Transactional
    public Incident upvoteIncident(String incidentId) {
        Incident incident = incidentRepository.findById(incidentId)
                .orElseThrow(() -> new RuntimeException("Incident not found: " + incidentId));
        incident.setUpvoteCount(incident.getUpvoteCount() + 1);
        return incidentRepository.save(incident);
    }

    /**
     * Get incident statistics for dashboard.
     */
    public Map<String, Object> getStatistics() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalReported", incidentRepository.countByStatus(IncidentStatus.reported));
        stats.put("totalVerified", incidentRepository.countByStatus(IncidentStatus.verified));
        stats.put("totalUnderReview", incidentRepository.countByStatus(IncidentStatus.under_review));

        // Count by severity
        List<Object[]> severityCounts = incidentRepository.countBySeverity(IncidentStatus.verified);
        Map<String, Long> bySeverity = new HashMap<>();
        for (Object[] row : severityCounts) {
            bySeverity.put(((Enum<?>) row[0]).name(), (Long) row[1]);
        }
        stats.put("bySeverity", bySeverity);

        // Count by type (top 5)
        List<Object[]> typeCounts = incidentRepository.countByType(IncidentStatus.verified);
        Map<String, Long> byType = new LinkedHashMap<>();
        for (int i = 0; i < Math.min(5, typeCounts.size()); i++) {
            Object[] row = typeCounts.get(i);
            byType.put((String) row[0], (Long) row[1]);
        }
        stats.put("byType", byType);

        return stats;
    }

    @Async
    protected void notifyNewIncident(Incident incident) {
        try {
            String stateSlug = incident.getState() != null ?
                    incident.getState().toLowerCase().replace(" ", "_") : "unknown";
            String lgaSlug = incident.getLga() != null ?
                    incident.getLga().toLowerCase().replace(" ", "_") : "unknown";

            // Publish to localized MQTT topics
            String topic = String.format("incidents/%s/%s", stateSlug, lgaSlug);
            mqttService.publish(topic, incident);

            // Also publish to general incidents topic
            mqttService.publish("incidents/new", incident);

            log.debug("Incident notification published to MQTT: {}", topic);
        } catch (Exception e) {
            log.warn("Failed to publish incident notification: {}", e.getMessage());
        }
    }

    @Async
    protected void autoCreateDangerZone(Incident incident) {
        try {
            // Determine radius based on severity
            double radiusKm;
            int expiryHours;
            switch (incident.getSeverity()) {
                case critical:
                    radiusKm = 5.0;
                    expiryHours = 48;
                    break;
                case high:
                    radiusKm = 3.0;
                    expiryHours = 24;
                    break;
                default:
                    radiusKm = 1.0;
                    expiryHours = 12;
                    break;
            }

            // Build zone name from incident type and location
            String zoneName = String.format("%s Zone - %s",
                    incident.getIncidentType().toUpperCase(),
                    incident.getState() != null ? incident.getState() : "Unknown");

            Zone zone = Zone.builder()
                    .name(zoneName)
                    .type(Zone.ZoneType.hazard)
                    .description(String.format("Auto-created from %s incident: %s (severity: %s)",
                            incident.getIncidentType(),
                            incident.getDescription() != null ? incident.getDescription() : "No description",
                            incident.getSeverity()))
                    .latitude(incident.getLatitude())
                    .longitude(incident.getLongitude())
                    .radius(radiusKm)
                    .severity(incident.getSeverity().name().toLowerCase())
                    .status(Zone.ZoneStatus.active)
                    .createdBy("system")
                    .expiresAt(LocalDateTime.now().plusHours(expiryHours))
                    .build();

            Zone created = zoneService.createZone(zone);
            log.info("Auto-created danger zone '{}' (id={}) for {} incident at ({}, {}) radius={}km expires={}",
                    created.getName(), created.getId(),
                    incident.getIncidentType(),
                    incident.getLatitude(), incident.getLongitude(),
                    radiusKm, created.getExpiresAt());

            // Publish zone creation to MQTT
            mqttService.publish("zones/new", created);
        } catch (Exception e) {
            log.warn("Failed to auto-create danger zone for incident {}: {}",
                    incident.getId(), e.getMessage());
        }
    }

    /**
     * Resolve Nigeria State and LGA from GPS coordinates using reverse geocoding.
     * Delegates to NigeriaLocationService for accurate state/LGA resolution.
     */
    private String[] resolveNigeriaGeoInfo(double latitude, double longitude) {
        return nigeriaLocationService.resolve(latitude, longitude);
    }

    private int severityToInt(IncidentSeverity severity) {
        switch (severity) {
            case low: return 1;
            case medium: return 2;
            case high: return 3;
            case critical: return 4;
            default: return 0;
        }
    }
}
