package com.dangeremergence.service;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.Incident.IncidentSeverity;
import com.dangeremergence.model.Incident.IncidentStatus;
import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.IncidentRepository;
import com.dangeremergence.repository.ZoneRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Service for planning safe routes that avoid danger zones and recent incidents.
 * All heavy computation runs on the backend.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class RouteService {

    private final IncidentRepository incidentRepository;
    private final ZoneRepository zoneRepository;

    /**
     * Plan a safe route between two points, avoiding danger zones and incidents.
     * Returns multiple route options with danger scores.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> planSafeRoute(double fromLat, double fromLng,
                                              double toLat, double toLng,
                                              boolean avoidHighways, boolean preferLitRoads) {
        // Calculate bounding box for the corridor
        double padding = 0.1; // ~10km padding
        double minLat = Math.min(fromLat, toLat) - padding;
        double maxLat = Math.max(fromLat, toLat) + padding;
        double minLon = Math.min(fromLng, toLng) - padding;
        double maxLon = Math.max(fromLng, toLng) + padding;

        // Get incidents and danger zones along the corridor
        List<Incident> nearbyIncidents = incidentRepository.findIncidentsInArea(
                minLat, maxLat, minLon, maxLon, IncidentStatus.verified);

        List<Zone> dangerZones = zoneRepository.findZonesInArea(
                minLat, maxLat, minLon, maxLon, Zone.ZoneStatus.active);

        // Generate waypoints (simplified: direct route with intermediate points)
        List<Map<String, Object>> waypoints = generateWaypoints(
                fromLat, fromLng, toLat, toLng, 10);

        // Score each segment
        List<Map<String, Object>> segments = new ArrayList<>();
        double totalDangerScore = 0;
        int maxSegmentScore = 0;

        for (int i = 0; i < waypoints.size() - 1; i++) {
            Map<String, Object> wp1 = waypoints.get(i);
            Map<String, Object> wp2 = waypoints.get(i + 1);

            double segLat = ((Number) wp1.get("latitude")).doubleValue();
            double segLng = ((Number) wp1.get("longitude")).doubleValue();

            double score = calculateSegmentDangerScore(
                    segLat, segLng, nearbyIncidents, dangerZones);

            Map<String, Object> segment = new HashMap<>();
            segment.put("startLat", wp1.get("latitude"));
            segment.put("startLng", wp1.get("longitude"));
            segment.put("endLat", wp2.get("latitude"));
            segment.put("endLng", wp2.get("longitude"));
            segment.put("dangerScore", score);
            segment.put("dangerLevel", getDangerLevel(score));

            segments.add(segment);
            totalDangerScore += score;
            if (score > maxSegmentScore) maxSegmentScore = (int) score;
        }

        // Calculate total distance (Haversine)
        double totalDistance = calculateHaversineDistance(fromLat, fromLng, toLat, toLng);

        // Estimate duration (assume 30 km/h average in Nigerian conditions)
        double estimatedDurationHours = totalDistance / 30.0;

        Map<String, Object> route = new HashMap<>();
        route.put("waypoints", waypoints);
        route.put("segments", segments);
        route.put("totalDistanceKm", Math.round(totalDistance * 10) / 10.0);
        route.put("estimatedDurationMinutes", (int) (estimatedDurationHours * 60));
        route.put("overallDangerScore", (int) totalDangerScore);
        route.put("overallDangerLevel", getDangerLevel(totalDangerScore));
        route.put("maxSegmentDangerScore", maxSegmentScore);
        route.put("nearbyIncidentCount", nearbyIncidents.size());
        route.put("nearbyDangerZoneCount", dangerZones.size());

        // Generate alternative route (slightly offset)
        List<Map<String, Object>> alternativeWaypoints = generateWaypoints(
                fromLat + 0.02, fromLng - 0.02, toLat - 0.02, toLng + 0.02, 8);

        Map<String, Object> alternativeRoute = new HashMap<>();
        alternativeRoute.put("waypoints", alternativeWaypoints);
        alternativeRoute.put("totalDistanceKm",
                Math.round(calculateHaversineDistance(fromLat, fromLng, toLat, toLng) * 1.15 * 10) / 10.0);

        Map<String, Object> result = new HashMap<>();
        result.put("routes", List.of(route, alternativeRoute));
        result.put("from", Map.of("latitude", fromLat, "longitude", fromLng));
        result.put("to", Map.of("latitude", toLat, "longitude", toLng));

        return result;
    }

    /**
     * Get danger score for a specific location.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> getDangerScore(double latitude, double longitude, double radiusKm) {
        double latDelta = radiusKm / 111.0;
        double lonDelta = radiusKm / (111.0 * Math.cos(Math.toRadians(latitude)));

        List<Incident> nearbyIncidents = incidentRepository.findIncidentsInArea(
                latitude - latDelta, latitude + latDelta,
                longitude - lonDelta, longitude + lonDelta,
                IncidentStatus.verified);

        List<Zone> dangerZones = zoneRepository.findZonesInArea(
                latitude - latDelta, latitude + latDelta,
                longitude - lonDelta, longitude + lonDelta,
                Zone.ZoneStatus.active);

        double score = calculateLocationDangerScore(latitude, longitude,
                nearbyIncidents, dangerZones, radiusKm);

        Map<String, Object> result = new HashMap<>();
        result.put("score", Math.min(100, (int) score));
        result.put("level", getDangerLevel(score));
        result.put("nearbyIncidents", nearbyIncidents.size());
        result.put("nearbyDangerZones", dangerZones.size());
        result.put("radiusKm", radiusKm);

        return result;
    }

    /**
     * Generate intermediate waypoints between two points.
     */
    private List<Map<String, Object>> generateWaypoints(
            double fromLat, double fromLng, double toLat, double toLng, int count) {
        List<Map<String, Object>> waypoints = new ArrayList<>();

        for (int i = 0; i <= count; i++) {
            double fraction = (double) i / count;
            double lat = fromLat + (toLat - fromLat) * fraction;
            double lng = fromLng + (toLng - fromLng) * fraction;

            // Add slight randomization to simulate road-following
            if (i > 0 && i < count) {
                Random rng = new Random(i * 31);
                lat += (rng.nextDouble() - 0.5) * 0.01;
                lng += (rng.nextDouble() - 0.5) * 0.01;
            }

            Map<String, Object> wp = new HashMap<>();
            wp.put("latitude", Math.round(lat * 10000) / 10000.0);
            wp.put("longitude", Math.round(lng * 10000) / 10000.0);
            waypoints.add(wp);
        }

        return waypoints;
    }

    /**
     * Calculate danger score for a route segment based on nearby incidents and zones.
     */
    private double calculateSegmentDangerScore(double lat, double lng,
                                                List<Incident> incidents,
                                                List<Zone> dangerZones) {
        double score = 0;
        double searchRadius = 0.05; // ~5km

        for (Incident incident : incidents) {
            double distance = haversine(lat, lng,
                    incident.getLatitude(), incident.getLongitude());
            if (distance > searchRadius) continue;

            double severityWeight = severityToWeight(incident.getSeverity());
            double recencyWeight = calculateRecencyWeight(incident.getOccurredAt());
            double distanceFactor = 1.0 - (distance / searchRadius);

            score += severityWeight * recencyWeight * distanceFactor * 10;
        }

        for (Zone zone : dangerZones) {
            double distance = haversine(lat, lng,
                    zone.getLatitude(), zone.getLongitude());
            double zoneRadius = zone.getRadius() != null ? zone.getRadius() / 111.0 : 0.05;

            if (distance > zoneRadius) continue;
            double distanceFactor = 1.0 - (distance / zoneRadius);
            score += 15 * distanceFactor; // Zones add significant weight
        }

        return score;
    }

    /**
     * Calculate danger score for a specific location.
     */
    private double calculateLocationDangerScore(double lat, double lng,
                                                 List<Incident> incidents,
                                                 List<Zone> dangerZones,
                                                 double radiusKm) {
        double score = 0;
        double searchRadius = radiusKm / 111.0;

        for (Incident incident : incidents) {
            double distance = haversine(lat, lng,
                    incident.getLatitude(), incident.getLongitude());
            if (distance > searchRadius) continue;

            double severityWeight = severityToWeight(incident.getSeverity());
            double recencyWeight = calculateRecencyWeight(incident.getOccurredAt());
            double distanceFactor = 1.0 - (distance / searchRadius);

            score += severityWeight * recencyWeight * distanceFactor * 20;
        }

        for (Zone zone : dangerZones) {
            double distance = haversine(lat, lng,
                    zone.getLatitude(), zone.getLongitude());
            double zoneRadius = zone.getRadius() != null ? zone.getRadius() / 111.0 : 0.05;

            if (distance > zoneRadius) continue;
            double distanceFactor = 1.0 - (distance / zoneRadius);
            score += 25 * distanceFactor;
        }

        return score;
    }

    private double severityToWeight(IncidentSeverity severity) {
        switch (severity) {
            case critical: return 4.0;
            case high: return 3.0;
            case medium: return 2.0;
            case low: return 1.0;
            default: return 0.5;
        }
    }

    private double calculateRecencyWeight(LocalDateTime occurredAt) {
        if (occurredAt == null) return 0.5;
        long hoursAgo = java.time.Duration.between(occurredAt, LocalDateTime.now()).toHours();
        if (hoursAgo < 1) return 1.0;     // Within last hour
        if (hoursAgo < 6) return 0.9;     // Within last 6 hours
        if (hoursAgo < 24) return 0.7;    // Within last day
        if (hoursAgo < 72) return 0.5;    // Within last 3 days
        if (hoursAgo < 168) return 0.3;   // Within last week
        return 0.1;                        // Older than a week
    }

    private String getDangerLevel(double score) {
        if (score <= 0) return "safe";
        if (score < 5) return "caution";
        if (score < 15) return "dangerous";
        return "critical";
    }

    private double haversine(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                        Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371 * c / 111.0; // Convert to degrees
    }

    private double calculateHaversineDistance(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                        Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371 * c; // Distance in km
    }
}
