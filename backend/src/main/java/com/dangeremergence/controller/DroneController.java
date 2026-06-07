package com.dangeremergence.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/drones")
public class DroneController {

    private static final Logger log = LoggerFactory.getLogger(DroneController.class);

    // In-memory drone registry (in production, use database)
    private final Map<String, Map<String, Object>> droneRegistry = new HashMap<>();

    public DroneController() {
        // Seed some synthetic drones
        Random rng = new Random(42);
        for (int i = 0; i < 10; i++) {
            Map<String, Object> drone = new HashMap<>();
            drone.put("id", "drone_" + i);
            drone.put("name", "Quadcopter " + (char) ('A' + i));
            drone.put("model", "DJI Matrice " + (300 + i * 10));
            drone.put("battery", 60 + rng.nextInt(40));
            drone.put("status", "idle");
            drone.put("latitude", 40.7128 + (rng.nextDouble() - 0.5) * 0.1);
            drone.put("longitude", -74.0060 + (rng.nextDouble() - 0.5) * 0.1);
            drone.put("altitude", 50 + rng.nextInt(100));
            drone.put("maxSpeed", 15 + rng.nextInt(10));
            drone.put("maxAltitude", 400);
            drone.put("hasLoRa", i < 5);
            drone.put("hasCamera", true);
            drone.put("lastSeen", System.currentTimeMillis());
            droneRegistry.put("drone_" + i, drone);
        }
    }

    @GetMapping("/available")
    public ResponseEntity<Map<String, Object>> getAvailableDrones(
            @RequestParam(required = false, defaultValue = "0") double latitude,
            @RequestParam(required = false, defaultValue = "0") double longitude) {

        List<Map<String, Object>> available = droneRegistry.values().stream()
                .filter(d -> {
                    int battery = (int) d.getOrDefault("battery", 0);
                    String status = (String) d.getOrDefault("status", "unknown");
                    return battery > 30 && "idle".equals(status);
                })
                .sorted((a, b) -> {
                    if (latitude == 0 && longitude == 0) return 0;
                    double distA = calcDistance(latitude, longitude,
                            (double) a.get("latitude"), (double) a.get("longitude"));
                    double distB = calcDistance(latitude, longitude,
                            (double) b.get("latitude"), (double) b.get("longitude"));
                    return Double.compare(distA, distB);
                })
                .collect(Collectors.toList());

        return ResponseEntity.ok(Map.of(
                "drones", available,
                "count", available.size()
        ));
    }

    @PostMapping("/deploy-relay")
    public ResponseEntity<Map<String, Object>> deployRelayDrone(@RequestBody Map<String, Object> request) {
        String droneId = (String) request.getOrDefault("droneId", "");
        double targetLat = ((Number) request.getOrDefault("latitude", 0.0)).doubleValue();
        double targetLng = ((Number) request.getOrDefault("longitude", 0.0)).doubleValue();

        Map<String, Object> drone = droneRegistry.get(droneId);
        if (drone == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Drone not found: " + droneId));
        }

        boolean hasLoRa = (boolean) drone.getOrDefault("hasLoRa", false);
        if (!hasLoRa) {
            return ResponseEntity.badRequest().body(Map.of("error", "Drone does not have LoRa capability"));
        }

        // Simulate deployment
        drone.put("status", "deploying");
        drone.put("targetLatitude", targetLat);
        drone.put("targetLongitude", targetLng);
        drone.put("mission", "relay_deployment");

        double distance = calcDistance(
                (double) drone.get("latitude"), (double) drone.get("longitude"),
                targetLat, targetLng
        );
        int estimatedFlightTime = (int) (distance / 15.0 * 60); // minutes at 15 m/s

        Map<String, Object> result = new HashMap<>();
        result.put("droneId", droneId);
        result.put("status", "deploying");
        result.put("targetLatitude", targetLat);
        result.put("targetLongitude", targetLng);
        result.put("estimatedFlightTimeMinutes", estimatedFlightTime);
        result.put("estimatedBatteryAtDestination", Math.max(0,
                (int) drone.get("battery") - estimatedFlightTime / 2));
        result.put("message", "LoRa relay drone deployed. Will auto-return at 20% battery.");

        return ResponseEntity.ok(result);
    }

    @PostMapping("/assess-damage")
    public ResponseEntity<Map<String, Object>> assessDamage(@RequestBody Map<String, Object> request) {
        String zoneId = (String) request.getOrDefault("zoneId", "unknown");
        double centerLat = ((Number) request.getOrDefault("centerLat", 0.0)).doubleValue();
        double centerLng = ((Number) request.getOrDefault("centerLng", 0.0)).doubleValue();
        double radiusKm = ((Number) request.getOrDefault("radiusKm", 1.0)).doubleValue();

        Random rng = new Random(zoneId.hashCode());

        // Generate simulated damage assessment
        List<Map<String, Object>> damagedBuildings = new ArrayList<>();
        int buildingCount = 5 + rng.nextInt(15);
        for (int i = 0; i < buildingCount; i++) {
            Map<String, Object> building = new HashMap<>();
            building.put("id", "bldg_damaged_" + i);
            building.put("latitude", centerLat + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            building.put("longitude", centerLng + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            building.put("damageLevel", rng.nextDouble() > 0.7 ? "total" :
                    rng.nextDouble() > 0.5 ? "severe" : "partial");
            building.put("type", rng.nextDouble() > 0.6 ? "residential" : "commercial");
            damagedBuildings.add(building);
        }

        List<Map<String, Object>> fireHotspots = new ArrayList<>();
        int fireCount = 2 + rng.nextInt(8);
        for (int i = 0; i < fireCount; i++) {
            Map<String, Object> hotspot = new HashMap<>();
            hotspot.put("id", "fire_" + i);
            hotspot.put("latitude", centerLat + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            hotspot.put("longitude", centerLng + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            hotspot.put("intensity", 0.3 + rng.nextDouble() * 0.7);
            hotspot.put("area", 10 + rng.nextInt(500));
            fireHotspots.add(hotspot);
        }

        List<Map<String, Object>> blockedRoads = new ArrayList<>();
        int roadCount = 3 + rng.nextInt(10);
        for (int i = 0; i < roadCount; i++) {
            Map<String, Object> road = new HashMap<>();
            road.put("id", "road_" + i);
            road.put("startLat", centerLat + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            road.put("startLng", centerLng + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            road.put("endLat", centerLat + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            road.put("endLng", centerLng + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            road.put("blockageType", rng.nextDouble() > 0.5 ? "debris" : "flooding");
            blockedRoads.add(road);
        }

        List<Map<String, Object>> casualties = new ArrayList<>();
        int casualtyCount = rng.nextInt(20);
        for (int i = 0; i < casualtyCount; i++) {
            Map<String, Object> casualty = new HashMap<>();
            casualty.put("id", "casualty_" + i);
            casualty.put("latitude", centerLat + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            casualty.put("longitude", centerLng + (rng.nextDouble() - 0.5) * radiusKm * 0.02);
            casualty.put("severity", rng.nextDouble() > 0.8 ? "critical" :
                    rng.nextDouble() > 0.5 ? "moderate" : "minor");
            casualties.add(casualty);
        }

        Map<String, Object> result = new HashMap<>();
        result.put("zoneId", zoneId);
        result.put("damagedBuildings", damagedBuildings);
        result.put("fireHotspots", fireHotspots);
        result.put("blockedRoads", blockedRoads);
        result.put("casualties", casualties);
        result.put("assessmentComplete", true);
        result.put("estimatedCasualties", casualtyCount);

        return ResponseEntity.ok(result);
    }

    @PostMapping("/deploy-swarm")
    public ResponseEntity<Map<String, Object>> deploySwarmMesh(@RequestBody Map<String, Object> request) {
        String zoneId = (String) request.getOrDefault("zoneId", "unknown");
        double centerLat = ((Number) request.getOrDefault("centerLat", 0.0)).doubleValue();
        double centerLng = ((Number) request.getOrDefault("centerLng", 0.0)).doubleValue();
        double radiusKm = ((Number) request.getOrDefault("radiusKm", 1.0)).doubleValue();

        // Find available drones with LoRa
        List<Map<String, Object>> availableWithLoRa = droneRegistry.values().stream()
                .filter(d -> {
                    int battery = (int) d.getOrDefault("battery", 0);
                    String status = (String) d.getOrDefault("status", "idle");
                    boolean hasLoRa = (boolean) d.getOrDefault("hasLoRa", false);
                    return battery > 30 && "idle".equals(status) && hasLoRa;
                })
                .collect(Collectors.toList());

        int droneCount = Math.min(availableWithLoRa.size(), 6); // Max 6 drones in swarm

        // Position drones around the zone perimeter
        List<Map<String, Object>> deployedDrones = new ArrayList<>();
        for (int i = 0; i < droneCount; i++) {
            double angle = 2 * Math.PI * i / droneCount;
            double offsetLat = Math.cos(angle) * radiusKm * 0.01;
            double offsetLng = Math.sin(angle) * radiusKm * 0.01;

            Map<String, Object> drone = new HashMap<>(availableWithLoRa.get(i));
            drone.put("deployedLatitude", centerLat + offsetLat);
            drone.put("deployedLongitude", centerLng + offsetLng);
            drone.put("altitude", 100 + i * 20);
            drone.put("status", "deployed");

            int battery = (int) drone.get("battery");
            int estimatedUptimeMinutes = battery * 2; // Rough estimate
            drone.put("estimatedUptimeMinutes", estimatedUptimeMinutes);

            deployedDrones.add(drone);
        }

        // Estimate coverage
        double coverageRadius = droneCount * 0.5; // km
        double signalStrength = Math.min(1.0, droneCount / 6.0);

        Map<String, Object> result = new HashMap<>();
        result.put("zoneId", zoneId);
        result.put("deployedDrones", deployedDrones);
        result.put("coverageRadiusKm", coverageRadius);
        result.put("estimatedSignalStrength", Math.round(signalStrength * 100.0) / 100.0);
        result.put("meshEstablished", droneCount >= 2);

        return ResponseEntity.ok(result);
    }

    private double calcDistance(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                        Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371 * c; // km
    }
}
