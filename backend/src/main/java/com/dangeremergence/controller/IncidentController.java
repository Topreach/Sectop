package com.dangeremergence.controller;

import com.dangeremergence.model.Incident;
import com.dangeremergence.service.IncidentService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * REST controller for crowdsourced incident reporting and danger location detection.
 *
 * Endpoints:
 *   POST   /api/v1/incidents              - Report a new incident
 *   GET    /api/v1/incidents/nearby        - Get verified incidents near a location
 *   GET    /api/v1/incidents/heatmap       - Get heatmap aggregation data
 *   GET    /api/v1/incidents/{id}          - Get incident details
 *   POST   /api/v1/incidents/{id}/verify   - Verify an incident (authorities)
 *   POST   /api/v1/incidents/{id}/upvote   - Upvote an incident
 *   GET    /api/v1/incidents/stats         - Get incident statistics
 */
@RestController
@RequestMapping("/api/v1/incidents")
public class IncidentController {

    private static final Logger log = LoggerFactory.getLogger(IncidentController.class);

    @Autowired
    private IncidentService incidentService;

    /**
     * Report a new incident (kidnapping, terrorism, suspicious activity, etc.)
     * Supports anonymous reporting.
     */
    @PostMapping
    public ResponseEntity<Map<String, Object>> reportIncident(@RequestBody Map<String, Object> request) {
        try {
            String reporterId = (String) request.get("reporterId");
            String incidentType = (String) request.get("incidentType");
            String description = (String) request.get("description");
            Double latitude = request.get("latitude") != null ?
                    ((Number) request.get("latitude")).doubleValue() : null;
            Double longitude = request.get("longitude") != null ?
                    ((Number) request.get("longitude")).doubleValue() : null;
            Double accuracy = request.get("accuracy") != null ?
                    ((Number) request.get("accuracy")).doubleValue() : null;
            String occurredAtStr = (String) request.get("occurredAt");
            LocalDateTime occurredAt = occurredAtStr != null ?
                    LocalDateTime.parse(occurredAtStr) : LocalDateTime.now();
            String severity = (String) request.getOrDefault("severity", "medium");
            boolean isAnonymous = Boolean.TRUE.equals(request.get("isAnonymous"));

            if (incidentType == null || incidentType.isEmpty()) {
                return ResponseEntity.badRequest().body(Map.of("error", "incidentType is required"));
            }
            if (latitude == null || longitude == null) {
                return ResponseEntity.badRequest().body(Map.of("error", "latitude and longitude are required"));
            }

            Incident incident = incidentService.createIncident(
                    reporterId, incidentType, description,
                    latitude, longitude, accuracy,
                    occurredAt, severity, isAnonymous);

            log.info("Incident reported: {} type={} at ({}, {})",
                    incident.getId(), incidentType, latitude, longitude);

            return ResponseEntity.ok(Map.of(
                    "incident", incident,
                    "message", "Incident reported successfully"
            ));
        } catch (Exception e) {
            log.error("Failed to report incident: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get verified incidents near a location.
     */
    @GetMapping("/nearby")
    public ResponseEntity<Map<String, Object>> getNearbyIncidents(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "10") double radiusKm,
            @RequestParam(required = false) List<String> types) {
        try {
            List<Incident> incidents = incidentService.getNearbyIncidents(
                    latitude, longitude, radiusKm, types);
            return ResponseEntity.ok(Map.of(
                    "incidents", incidents,
                    "count", incidents.size()
            ));
        } catch (Exception e) {
            log.error("Failed to get nearby incidents: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get heatmap data for danger zone visualization.
     * Returns aggregated incident counts per grid cell.
     */
    @GetMapping("/heatmap")
    public ResponseEntity<Map<String, Object>> getHeatmap(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "20") double radiusKm,
            @RequestParam(required = false) String since) {
        try {
            LocalDateTime sinceTime = since != null ?
                    LocalDateTime.parse(since) : LocalDateTime.now().minusDays(7);
            List<Map<String, Object>> heatmap = incidentService.getHeatmapData(
                    latitude, longitude, radiusKm, sinceTime);
            return ResponseEntity.ok(Map.of(
                    "heatmap", heatmap,
                    "count", heatmap.size()
            ));
        } catch (Exception e) {
            log.error("Failed to get heatmap data: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get incident details by ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getIncident(@PathVariable String id) {
        try {
            // For now return a simple response; in production use repository
            return ResponseEntity.ok(Map.of(
                    "incidentId", id,
                    "message", "Incident details endpoint"
            ));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Verify an incident (mark as confirmed by authorities).
     */
    @PostMapping("/{id}/verify")
    public ResponseEntity<Map<String, Object>> verifyIncident(
            @PathVariable String id,
            @RequestBody Map<String, Object> request) {
        try {
            String verifiedBy = (String) request.get("verifiedBy");
            Incident incident = incidentService.verifyIncident(id, verifiedBy);
            return ResponseEntity.ok(Map.of(
                    "incident", incident,
                    "message", "Incident verified successfully"
            ));
        } catch (Exception e) {
            log.error("Failed to verify incident {}: {}", id, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Upvote an incident (community validation).
     */
    @PostMapping("/{id}/upvote")
    public ResponseEntity<Map<String, Object>> upvoteIncident(@PathVariable String id) {
        try {
            Incident incident = incidentService.upvoteIncident(id);
            return ResponseEntity.ok(Map.of(
                    "incident", incident,
                    "message", "Incident upvoted"
            ));
        } catch (Exception e) {
            log.error("Failed to upvote incident {}: {}", id, e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get incident statistics for dashboard.
     */
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStatistics() {
        try {
            Map<String, Object> stats = incidentService.getStatistics();
            return ResponseEntity.ok(stats);
        } catch (Exception e) {
            log.error("Failed to get incident statistics: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }
}
