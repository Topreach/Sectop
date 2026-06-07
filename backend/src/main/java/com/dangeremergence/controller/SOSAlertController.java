package com.dangeremergence.controller;

import com.dangeremergence.model.SOSAlert;
import com.dangeremergence.service.SOSAlertService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

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
                (boolean) request.getOrDefault("is_silent", false)
        );
        return ResponseEntity.ok(alert);
    }

    @GetMapping("/active")
    public ResponseEntity<List<SOSAlert>> getActiveAlerts() {
        return ResponseEntity.ok(alertService.getActiveAlerts());
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<List<SOSAlert>> getAlertsForUser(@PathVariable String userId) {
        return ResponseEntity.ok(alertService.getAlertsForUser(userId));
    }

    @GetMapping("/nearby")
    public ResponseEntity<List<SOSAlert>> getAlertsInArea(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "5.0") double radiusKm) {
        return ResponseEntity.ok(alertService.getAlertsInArea(latitude, longitude, radiusKm));
    }

    @GetMapping("/sync")
    public ResponseEntity<List<SOSAlert>> getAlertsSince(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime since) {
        return ResponseEntity.ok(alertService.getAlertsSince(since));
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
        return ResponseEntity.ok(Map.of("active_count", alertService.getActiveAlertCount()));
    }
}
