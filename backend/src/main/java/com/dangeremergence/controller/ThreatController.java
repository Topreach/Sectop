package com.dangeremergence.controller;

import com.dangeremergence.model.Incident;
import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.model.Zone;
import com.dangeremergence.service.IncidentService;
import com.dangeremergence.service.PredictiveService;
import com.dangeremergence.service.SOSAlertService;
import com.dangeremergence.service.ZoneService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Consolidated threat awareness controller.
 *
 * All threat detection, analysis, and alerting logic that was previously
 * duplicated in the frontend ThreatAwarenessService has been moved here.
 * The frontend now acts as a thin API client that calls these endpoints.
 *
 * Endpoints:
 *   POST /api/v1/threat/analyze-text   — Keyword + ML text analysis
 *   GET  /api/v1/threat/level           — Computed threat level for location
 *   GET  /api/v1/threat/alerts          — Pre-formatted threat alerts for location
 *   POST /api/v1/threat/audio-result    — Receive ambient audio analysis result
 */
@RestController
@RequestMapping("/api/v1/threat")
public class ThreatController {

    private static final Logger log = LoggerFactory.getLogger(ThreatController.class);

    @Autowired
    private IncidentService incidentService;

    @Autowired
    private ZoneService zoneService;

    @Autowired
    private SOSAlertService sosAlertService;

    @Autowired
    private PredictiveService predictiveService;

    // ---------------------------------------------------------------------------
    // Threat Keyword Analysis (replaces frontend _localKeywordAnalysis)
    // ---------------------------------------------------------------------------

    /**
     * Analyze text for threat keywords and return a structured threat result.
     * Consolidates keyword analysis from AIController.ruleBasedAnalysis() and
     * TipOffService.calculateThreatScore() into a single endpoint that returns
     * pre-formatted alert data ready for the frontend to display.
     *
     * Request body:
     *   { "text": "string", "latitude": double (optional), "longitude": double (optional) }
     *
     * Response:
     *   {
     *     "hasThreat": boolean,
     *     "severity": "low"|"medium"|"high"|"critical",
     *     "confidence": double,
     *     "label": "string",
     *     "title": "string",
     *     "description": "string",
     *     "matchedKeywords": ["string", ...],
     *     "method": "rule_based"|"ml_service"
     *   }
     */
    @PostMapping("/analyze-text")
    public ResponseEntity<Map<String, Object>> analyzeText(@RequestBody Map<String, Object> request) {
        String text = (String) request.getOrDefault("text", "");
        Double latitude = (Double) request.get("latitude");
        Double longitude = (Double) request.get("longitude");

        if (text == null || text.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "text is required"));
        }

        Map<String, Object> result = performKeywordAnalysis(text);
        return ResponseEntity.ok(result);
    }

    /**
     * Performs the keyword-based threat analysis that was previously in
     * ThreatAwarenessService._localKeywordAnalysis().
     * Includes Nigerian context keywords (kidnap, terrorist, bandit, herdsmen, etc.)
     * and returns pre-formatted alert data.
     */
    private Map<String, Object> performKeywordAnalysis(String text) {
        String lower = text.toLowerCase();

        // Threat keywords with severity, label, and confidence
        // Matches the frontend's _localKeywordAnalysis() keyword map
        Map<String, Map<String, Object>> threatKeywords = new LinkedHashMap<>();
        threatKeywords.put("kidnap", Map.of("severity", "critical", "label", "kidnapping", "confidence", 0.7));
        threatKeywords.put("kidnapped", Map.of("severity", "critical", "label", "kidnapping", "confidence", 0.8));
        threatKeywords.put("abduction", Map.of("severity", "critical", "label", "kidnapping", "confidence", 0.7));
        threatKeywords.put("abducted", Map.of("severity", "critical", "label", "kidnapping", "confidence", 0.8));
        threatKeywords.put("ransom", Map.of("severity", "critical", "label", "kidnapping", "confidence", 0.6));
        threatKeywords.put("terrorist", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.7));
        threatKeywords.put("terrorism", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.8));
        threatKeywords.put("bomb", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.7));
        threatKeywords.put("bombing", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.8));
        threatKeywords.put("explosion", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.7));
        threatKeywords.put("suicide attack", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.8));
        threatKeywords.put("ied", Map.of("severity", "critical", "label", "terrorism", "confidence", 0.7));
        threatKeywords.put("bandit", Map.of("severity", "high", "label", "banditry", "confidence", 0.7));
        threatKeywords.put("banditry", Map.of("severity", "high", "label", "banditry", "confidence", 0.8));
        threatKeywords.put("armed robbery", Map.of("severity", "high", "label", "armed_robbery", "confidence", 0.7));
        threatKeywords.put("gunmen", Map.of("severity", "high", "label", "banditry", "confidence", 0.6));
        threatKeywords.put("gunshot", Map.of("severity", "high", "label", "banditry", "confidence", 0.7));
        threatKeywords.put("herdsmen", Map.of("severity", "high", "label", "herdsmen_attack", "confidence", 0.6));
        threatKeywords.put("fulani herdsmen", Map.of("severity", "high", "label", "herdsmen_attack", "confidence", 0.7));
        threatKeywords.put("cult", Map.of("severity", "high", "label", "cult_violence", "confidence", 0.6));
        threatKeywords.put("ritual", Map.of("severity", "high", "label", "ritual_killings", "confidence", 0.6));
        threatKeywords.put("ritual killing", Map.of("severity", "critical", "label", "ritual_killings", "confidence", 0.7));
        threatKeywords.put("help", Map.of("severity", "high", "label", "distress", "confidence", 0.5));
        threatKeywords.put("emergency", Map.of("severity", "high", "label", "distress", "confidence", 0.5));
        threatKeywords.put("danger", Map.of("severity", "high", "label", "distress", "confidence", 0.5));
        threatKeywords.put("attack", Map.of("severity", "high", "label", "distress", "confidence", 0.5));
        threatKeywords.put("kill", Map.of("severity", "high", "label", "violence", "confidence", 0.5));
        threatKeywords.put("murder", Map.of("severity", "critical", "label", "violence", "confidence", 0.6));
        threatKeywords.put("political violence", Map.of("severity", "high", "label", "political_violence", "confidence", 0.6));
        threatKeywords.put("communal clash", Map.of("severity", "high", "label", "communal_clash", "confidence", 0.7));
        threatKeywords.put("ethnic clash", Map.of("severity", "high", "label", "communal_clash", "confidence", 0.7));
        threatKeywords.put("suspicious", Map.of("severity", "medium", "label", "suspicious_activity", "confidence", 0.5));
        threatKeywords.put("surveillance", Map.of("severity", "medium", "label", "suspicious_activity", "confidence", 0.5));
        threatKeywords.put("following me", Map.of("severity", "high", "label", "suspicious_activity", "confidence", 0.6));

        // Match keywords
        List<Map<String, Object>> matched = new ArrayList<>();
        for (Map.Entry<String, Map<String, Object>> entry : threatKeywords.entrySet()) {
            if (lower.contains(entry.getKey())) {
                matched.add(entry.getValue());
            }
        }

        if (matched.isEmpty()) {
            Map<String, Object> result = new HashMap<>();
            result.put("hasThreat", false);
            result.put("severity", "low");
            result.put("confidence", 0.0);
            result.put("label", "normal");
            result.put("title", "No Threat Detected");
            result.put("description", "No threat keywords found in text");
            result.put("matchedKeywords", List.of());
            result.put("method", "rule_based");
            return result;
        }

        // Sort by severity (critical > high > medium > low)
        Map<String, Integer> severityOrder = Map.of(
            "critical", 4, "high", 3, "medium", 2, "low", 1
        );
        matched.sort((a, b) -> {
            int aOrder = severityOrder.getOrDefault(a.get("severity"), 0);
            int bOrder = severityOrder.getOrDefault(b.get("severity"), 0);
            return Integer.compare(bOrder, aOrder);
        });

        Map<String, Object> best = matched.get(0);
        String severity = (String) best.get("severity");
        String label = (String) best.get("label");
        double confidence = (double) best.get("confidence");

        // Only alert for high+ severity (matches frontend behavior)
        boolean hasThreat = severity.equals("high") || severity.equals("critical");

        String typeLabel = getIncidentTypeLabel(label);
        Set<String> matchedLabels = matched.stream()
                .map(m -> (String) m.get("label"))
                .collect(Collectors.toSet());
        String matchedKeywordsStr = matchedLabels.stream()
                .map(this::getIncidentTypeLabel)
                .collect(Collectors.joining(", "));

        Map<String, Object> result = new HashMap<>();
        result.put("hasThreat", hasThreat);
        result.put("severity", severity);
        result.put("confidence", confidence);
        result.put("label", label);
        result.put("title", hasThreat ? "⚠️ " + typeLabel + " Suspected" : "No Threat");
        result.put("description", hasThreat
                ? "Message contains keywords related to: " + matchedKeywordsStr
                : "No significant threat detected");
        result.put("matchedKeywords", new ArrayList<>(matchedLabels));
        result.put("method", "rule_based");
        return result;
    }

    // ---------------------------------------------------------------------------
    // Threat Level Calculation (replaces frontend _calculateThreatLevel)
    // ---------------------------------------------------------------------------

    /**
     * Compute the current threat level for a location based on nearby incidents,
     * danger zones, active SOS alerts, and ML-predicted hotspots.
     *
     * Query params:
     *   latitude  — User's current latitude
     *   longitude — User's current longitude
     *   radiusKm  — Search radius (default: 20)
     *
     * Response:
     *   {
     *     "threatLevel": 0.0-1.0,
     *     "incidentCount": int,
     *     "dangerZoneCount": int,
     *     "activeAlertCount": int,
     *     "predictedHotspotCount": int,
     *     "hasCritical": boolean,
     *     "levelLabel": "low"|"medium"|"high"|"critical"
     *   }
     */
    @GetMapping("/level")
    public ResponseEntity<Map<String, Object>> getThreatLevel(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "20") double radiusKm) {

        // Fetch nearby incidents
        List<Incident> incidents = incidentService.getNearbyIncidents(latitude, longitude, radiusKm, null);

        // Fetch nearby danger zones
        List<Zone> zones = zoneService.getDangerZones();

        // Fetch active SOS alerts nearby
        List<SOSAlert> activeAlerts = sosAlertService.getAlertsInArea(latitude, longitude, radiusKm);

        // Fetch ML hotspot predictions (with fallback if ML service is unavailable)
        List<Map<String, Object>> hotspots = List.of();
        try {
            Map<String, Object> hotspotsResult = predictiveService.detectHotspots(latitude, longitude, radiusKm);
            hotspots = (List<Map<String, Object>>) hotspotsResult.getOrDefault("hotspots", List.of());
        } catch (Exception e) {
            log.warn("ThreatController: Failed to fetch hotspot predictions, using empty list: {}", e.getMessage());
        }

        // Calculate threat level (matches frontend _calculateThreatLevel logic)
        double level = 0.0;

        if (incidents.size() > 10) level += 0.4;
        else if (incidents.size() > 5) level += 0.3;
        else if (incidents.size() > 2) level += 0.2;
        else if (!incidents.isEmpty()) level += 0.1;

        if (zones.size() > 5) level += 0.3;
        else if (zones.size() > 2) level += 0.2;
        else if (!zones.isEmpty()) level += 0.1;

        if (activeAlerts.size() > 3) level += 0.3;
        else if (!activeAlerts.isEmpty()) level += 0.15;

        boolean hasCritical = incidents.stream().anyMatch(i ->
                i.getSeverity() != null && i.getSeverity().name().equals("critical")) ||
                zones.stream().anyMatch(z ->
                z.getSeverity() != null && z.getSeverity().equals("critical"));
        if (hasCritical) level += 0.2;

        int predictedHotspotCount = hotspots.size();
        if (predictedHotspotCount > 10) level += 0.35;
        else if (predictedHotspotCount > 5) level += 0.25;
        else if (predictedHotspotCount > 2) level += 0.15;
        else if (predictedHotspotCount > 0) level += 0.08;

        level = Math.max(0.0, Math.min(1.0, level));

        String levelLabel;
        if (level >= 0.7) levelLabel = "critical";
        else if (level >= 0.4) levelLabel = "high";
        else if (level >= 0.2) levelLabel = "medium";
        else levelLabel = "low";

        Map<String, Object> result = new HashMap<>();
        result.put("threatLevel", level);
        result.put("incidentCount", incidents.size());
        result.put("dangerZoneCount", zones.size());
        result.put("activeAlertCount", activeAlerts.size());
        result.put("predictedHotspotCount", predictedHotspotCount);
        result.put("hasCritical", hasCritical);
        result.put("levelLabel", levelLabel);

        return ResponseEntity.ok(result);
    }

    // ---------------------------------------------------------------------------
    // Threat Alerts (replaces frontend _processIncidents / _processDangerZones / _processActiveAlerts)
    // ---------------------------------------------------------------------------

    /**
     * Get pre-formatted threat alerts for a location.
     * Returns alerts already structured as ThreatAlert JSON, so the frontend
     * does not need to parse raw incidents/zones/alerts into alerts.
     *
     * Query params:
     *   latitude  — User's current latitude
     *   longitude — User's current longitude
     *   radiusKm  — Search radius (default: 20)
     *
     * Response:
     *   {
     *     "alerts": [ { id, type, title, description, latitude, longitude, severity, confidence, timestamp, sourceData }, ... ],
     *     "totalCount": int,
     *     "unreadCount": int
     *   }
     */
    @GetMapping("/alerts")
    public ResponseEntity<Map<String, Object>> getThreatAlerts(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "20") double radiusKm) {

        List<Map<String, Object>> alerts = new ArrayList<>();

        // Process incidents into threat alerts
        List<Incident> incidents = incidentService.getNearbyIncidents(latitude, longitude, radiusKm, null);
        for (Incident incident : incidents) {
            String severity = incident.getSeverity() != null ? incident.getSeverity().name().toLowerCase() : "medium";
            if (!severity.equals("high") && !severity.equals("critical")) continue;

            String typeLabel = getIncidentTypeLabel(incident.getIncidentType());
            Map<String, Object> alert = new HashMap<>();
            alert.put("id", "inc_" + incident.getId());
            alert.put("type", "incident");
            alert.put("title", typeLabel + " Reported Nearby");
            alert.put("description", incident.getDescription() != null && !incident.getDescription().isEmpty()
                    ? incident.getDescription()
                    : "A " + typeLabel + " incident has been reported in your area");
            alert.put("latitude", incident.getLatitude());
            alert.put("longitude", incident.getLongitude());
            alert.put("severity", severity);
            alert.put("confidence", 0.85);
            alert.put("timestamp", incident.getCreatedAt() != null
                    ? incident.getCreatedAt().toString()
                    : LocalDateTime.now().toString());
            alert.put("sourceData", Map.of(
                "incidentId", incident.getId(),
                "incidentType", incident.getIncidentType()
            ));
            alerts.add(alert);
        }

        // Process danger zones into threat alerts
        List<Zone> zones = zoneService.getDangerZones();
        for (Zone zone : zones) {
            String severity = zone.getSeverity() != null ? zone.getSeverity() : "medium";
            if (!severity.equals("high") && !severity.equals("critical")) continue;

            Map<String, Object> alert = new HashMap<>();
            alert.put("id", "zone_" + zone.getId());
            alert.put("type", "danger_zone");
            alert.put("title", "Danger Zone: " + (zone.getName() != null ? zone.getName() : "Unknown Zone"));
            alert.put("description", "A " + severity + "-severity danger zone is active in your area");
            alert.put("latitude", zone.getLatitude());
            alert.put("longitude", zone.getLongitude());
            alert.put("severity", severity);
            alert.put("confidence", 0.9);
            alert.put("timestamp", LocalDateTime.now().toString());
            alert.put("sourceData", Map.of(
                "zoneId", zone.getId(),
                "zoneName", zone.getName() != null ? zone.getName() : "Unknown"
            ));
            alerts.add(alert);
        }

        // Process active SOS alerts into threat alerts
        List<SOSAlert> activeAlerts = sosAlertService.getAlertsInArea(latitude, longitude, radiusKm);
        for (SOSAlert sosAlert : activeAlerts) {
            Map<String, Object> alert = new HashMap<>();
            alert.put("id", "alert_" + sosAlert.getId());
            alert.put("type", "sos_alert");
            alert.put("title", "SOS Alert in Your Area");
            alert.put("description", sosAlert.getDescription() != null
                    ? sosAlert.getDescription()
                    : "An emergency alert has been issued nearby");
            alert.put("latitude", sosAlert.getLatitude());
            alert.put("longitude", sosAlert.getLongitude());
            alert.put("severity", "high");
            alert.put("confidence", 0.95);
            alert.put("timestamp", sosAlert.getCreatedAt() != null
                    ? sosAlert.getCreatedAt().toString()
                    : LocalDateTime.now().toString());
            alert.put("sourceData", Map.of(
                "alertId", sosAlert.getId(),
                "alertType", sosAlert.getAlertType() != null ? sosAlert.getAlertType() : "sos"
            ));
            alerts.add(alert);
        }

        // Sort by severity (critical first), then by timestamp (newest first)
        Map<String, Integer> severityOrder = Map.of(
            "critical", 4, "high", 3, "medium", 2, "low", 1
        );
        alerts.sort((a, b) -> {
            int aSev = severityOrder.getOrDefault(a.get("severity"), 0);
            int bSev = severityOrder.getOrDefault(b.get("severity"), 0);
            if (aSev != bSev) return Integer.compare(bSev, aSev);
            String aTs = (String) a.getOrDefault("timestamp", "");
            String bTs = (String) b.getOrDefault("timestamp", "");
            return bTs.compareTo(aTs);
        });

        Map<String, Object> result = new HashMap<>();
        result.put("alerts", alerts);
        result.put("totalCount", alerts.size());
        result.put("unreadCount", alerts.size()); // All new alerts are unread

        return ResponseEntity.ok(result);
    }

    // ---------------------------------------------------------------------------
    // Ambient Audio Result (replaces frontend _handleThreatDetection in AmbientAudioMonitor)
    // ---------------------------------------------------------------------------

    /**
     * Receive an ambient audio analysis result from the frontend and create
     * a threat alert on the server side.
     *
     * The frontend captures audio locally (hardware requirement) and sends
     * the analysis result here for server-side alert creation and persistence.
     *
     * Request body:
     *   {
     *     "hasDistress": boolean,
     *     "threatLevel": "low"|"medium"|"high"|"critical",
     *     "confidence": double,
     *     "method": "string"
     *   }
     *
     * Response:
     *   {
     *     "alertId": "string",
     *     "created": boolean,
     *     "alert": { ... threat alert object ... }
     *   }
     */
    @PostMapping("/audio-result")
    public ResponseEntity<Map<String, Object>> receiveAudioResult(@RequestBody Map<String, Object> request) {
        boolean hasDistress = (boolean) request.getOrDefault("hasDistress", false);
        String threatLevel = (String) request.getOrDefault("threatLevel", "low");
        double confidence = ((Number) request.getOrDefault("confidence", 0.0)).doubleValue();
        String method = (String) request.getOrDefault("method", "ambient_audio_monitor");

        if (!hasDistress) {
            return ResponseEntity.ok(Map.of(
                "created", false,
                "message", "No distress detected — no alert created"
            ));
        }

        String severity;
        switch (threatLevel.toLowerCase()) {
            case "critical":
                severity = "critical";
                break;
            case "high":
                severity = "high";
                break;
            default:
                severity = "medium";
                break;
        }

        String alertId = "ambient_" + System.currentTimeMillis();

        Map<String, Object> alert = new HashMap<>();
        alert.put("id", alertId);
        alert.put("type", "ambient_audio");
        alert.put("title", "⚠️ Suspicious Audio Detected");
        alert.put("description", hasDistress
                ? "Distress audio detected (" + threatLevel + " threat level)"
                : "Suspicious audio detected in your environment");
        alert.put("severity", severity);
        alert.put("confidence", confidence);
        alert.put("timestamp", LocalDateTime.now().toString());
        alert.put("sourceData", Map.of(
            "hasDistress", String.valueOf(hasDistress),
            "threatLevel", threatLevel,
            "confidence", String.valueOf(confidence),
            "method", method
        ));

        Map<String, Object> result = new HashMap<>();
        result.put("alertId", alertId);
        result.put("created", true);
        result.put("alert", alert);

        log.info("Audio threat alert created: id={} severity={} confidence={}",
                alertId, severity, confidence);

        return ResponseEntity.ok(result);
    }

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    /**
     * Map incident type label to a human-readable display string.
     * Matches the frontend's _getIncidentTypeLabel() method.
     */
    private String getIncidentTypeLabel(String type) {
        if (type == null) return "Unknown";
        switch (type) {
            case "kidnapping": return "Kidnapping";
            case "terrorism": return "Terrorism";
            case "banditry": return "Banditry";
            case "armed_robbery": return "Armed Robbery";
            case "suspicious_activity": return "Suspicious Activity";
            case "herdsmen_attack": return "Herdsmen Attack";
            case "cult_violence": return "Cult Violence";
            case "ritual_killings": return "Ritual Killings";
            case "political_violence": return "Political Violence";
            case "communal_clash": return "Communal Clash";
            case "predicted_hotspot": return "Predicted Hotspot";
            case "distress": return "Distress";
            case "violence": return "Violence";
            default:
                if (type.isEmpty()) return "Unknown";
                return type.substring(0, 1).toUpperCase() + type.substring(1);
        }
    }
}
