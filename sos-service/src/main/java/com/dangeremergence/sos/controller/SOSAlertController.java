package com.dangeremergence.sos.controller;

import com.dangeremergence.sos.model.SOSAlert;
import com.dangeremergence.sos.service.SOSAlertService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * REST controller for SOS alerts on the dedicated SOS microservice (port 8081).
 * <p>
 * All endpoints are prefixed with /api/v1/alerts.
 * Nginx routes /api/v1/alerts/* to this service.
 */
@RestController
@RequestMapping("/api/v1/alerts")
@RequiredArgsConstructor
public class SOSAlertController {

    private final SOSAlertService alertService;

    @PostMapping
    public ResponseEntity<SOSAlert> createAlert(@RequestBody Map<String, Object> request) {
        SOSAlert alert = alertService.createAlert(
                (String) request.get("user_id"),
                (String) request.get("alert_type"),
                (String) request.get("description"),
                ((Number) request.get("latitude")).doubleValue(),
                ((Number) request.get("longitude")).doubleValue(),
                request.get("accuracy") != null ? ((Number) request.get("accuracy")).doubleValue() : null,
                (int) request.getOrDefault("priority", 3),
                (boolean) request.getOrDefault("is_silent", false),
                (boolean) request.getOrDefault("is_covert", false)
        );
        return ResponseEntity.ok(alert);
    }

    @GetMapping("/active")
    public ResponseEntity<Map<String, Object>> getActiveAlerts() {
        return ResponseEntity.ok(Map.of("alerts", alertService.getActiveAlerts()));
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<Map<String, Object>> getAlertsForUser(@PathVariable String userId) {
        return ResponseEntity.ok(Map.of("alerts", alertService.getAlertsForUser(userId)));
    }

    @GetMapping("/nearby")
    public ResponseEntity<Map<String, Object>> getAlertsInArea(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "5.0") double radiusKm) {
        return ResponseEntity.ok(Map.of("alerts", alertService.getAlertsInArea(latitude, longitude, radiusKm)));
    }

    @GetMapping("/sync")
    public ResponseEntity<Map<String, Object>> getAlertsSince(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime since) {
        return ResponseEntity.ok(Map.of("alerts", alertService.getAlertsSince(since)));
    }

    @PostMapping("/{alertId}/acknowledge")
    public ResponseEntity<SOSAlert> acknowledgeAlert(
            @PathVariable String alertId,
            @RequestBody Map<String, String> request) {
        return ResponseEntity.ok(alertService.acknowledgeAlert(alertId, request.get("responder_id")));
    }

    @PostMapping("/{alertId}/resolve")
    public ResponseEntity<SOSAlert> resolveAlert(@PathVariable String alertId) {
        return ResponseEntity.ok(alertService.resolveAlert(alertId));
    }

    @GetMapping("/count")
    public ResponseEntity<Map<String, Long>> getAlertCount() {
        return ResponseEntity.ok(Map.of("count", alertService.getActiveAlertCount()));
    }
}
