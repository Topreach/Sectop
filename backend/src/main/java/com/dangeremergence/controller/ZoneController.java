package com.dangeremergence.controller;

import com.dangeremergence.model.Zone;
import com.dangeremergence.service.ZoneService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/v1/zones")
public class ZoneController {

    private final ZoneService zoneService;

    @Autowired
    public ZoneController(ZoneService zoneService) {
        this.zoneService = zoneService;
    }

    @PostMapping
    public ResponseEntity<?> createZone(@RequestBody Zone zone) {
        Zone savedZone = zoneService.createZone(zone);
        return ResponseEntity.status(HttpStatus.CREATED).body(savedZone);
    }

    @GetMapping("/{zoneId}")
    public ResponseEntity<?> getZone(@PathVariable String zoneId) {
        Optional<Zone> zoneOpt = zoneService.getZoneById(zoneId);
        if (zoneOpt.isPresent()) {
            return ResponseEntity.ok(zoneOpt.get());
        }
        Map<String, String> error = new HashMap<>();
        error.put("error", "Zone not found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @GetMapping("/active")
    public ResponseEntity<Map<String, Object>> getActiveZones() {
        List<Zone> zones = zoneService.getActiveZones();
        return ResponseEntity.ok(Map.of("zones", zones));
    }

    @GetMapping("/danger")
    public ResponseEntity<Map<String, Object>> getDangerZones() {
        List<Zone> zones = zoneService.getDangerZones();
        return ResponseEntity.ok(Map.of("zones", zones));
    }

    @GetMapping("/restricted")
    public ResponseEntity<Map<String, Object>> getRestrictedZones() {
        List<Zone> zones = zoneService.getRestrictedZones();
        return ResponseEntity.ok(Map.of("zones", zones));
    }

    @GetMapping("/nearby")
    public ResponseEntity<Map<String, Object>> getZonesNearby(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "0.5") double radiusDegrees) {
        double north = latitude + radiusDegrees;
        double south = latitude - radiusDegrees;
        double east = longitude + radiusDegrees;
        double west = longitude - radiusDegrees;
        List<Zone> zones = zoneService.getZonesInArea(north, south, east, west);
        return ResponseEntity.ok(Map.of("zones", zones));
    }

    @GetMapping("/sync")
    public ResponseEntity<Map<String, Object>> getZonesSince(@RequestParam(required = false) String since) {
        LocalDateTime sinceTime = since != null ? LocalDateTime.parse(since) : LocalDateTime.now().minusHours(24);
        List<Zone> zones = zoneService.getZonesSince(sinceTime);
        return ResponseEntity.ok(Map.of("zones", zones));
    }

    @PutMapping("/{zoneId}")
    public ResponseEntity<?> updateZone(@PathVariable String zoneId, @RequestBody Zone zone) {
        Optional<Zone> existingOpt = zoneService.getZoneById(zoneId);
        if (existingOpt.isPresent()) {
            Zone existing = existingOpt.get();
            if (zone.getName() != null) existing.setName(zone.getName());
            if (zone.getType() != null) existing.setType(zone.getType());
            if (zone.getDescription() != null) existing.setDescription(zone.getDescription());
            if (zone.getLatitude() != null) existing.setLatitude(zone.getLatitude());
            if (zone.getLongitude() != null) existing.setLongitude(zone.getLongitude());
            if (zone.getRadius() != null) existing.setRadius(zone.getRadius());
            if (zone.getSeverity() != null) existing.setSeverity(zone.getSeverity());
            if (zone.getStatus() != null) existing.setStatus(zone.getStatus());

            Zone updated = zoneService.updateZone(existing);
            return ResponseEntity.ok(updated);
        }
        Map<String, String> error = new HashMap<>();
        error.put("error", "Zone not found");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @PostMapping("/{zoneId}/activate")
    public ResponseEntity<?> activateZone(@PathVariable String zoneId) {
        zoneService.activateZone(zoneId);
        Map<String, String> response = new HashMap<>();
        response.put("message", "Zone activated successfully");
        return ResponseEntity.ok(response);
    }

    @PostMapping("/{zoneId}/deactivate")
    public ResponseEntity<?> deactivateZone(@PathVariable String zoneId) {
        zoneService.deactivateZone(zoneId);
        Map<String, String> response = new HashMap<>();
        response.put("message", "Zone deactivated successfully");
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{zoneId}")
    public ResponseEntity<?> deleteZone(@PathVariable String zoneId) {
        zoneService.expireZone(zoneId);
        Map<String, String> response = new HashMap<>();
        response.put("message", "Zone expired successfully");
        return ResponseEntity.ok(response);
    }

    @GetMapping("/count")
    public ResponseEntity<Map<String, Long>> getZoneCount() {
        Map<String, Long> counts = new HashMap<>();
        counts.put("active", (long) zoneService.getActiveZones().size());
        counts.put("danger", (long) zoneService.getDangerZones().size());
        counts.put("restricted", (long) zoneService.getRestrictedZones().size());
        return ResponseEntity.ok(counts);
    }
}
