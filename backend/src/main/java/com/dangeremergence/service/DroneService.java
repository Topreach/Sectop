package com.dangeremergence.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class DroneService {

    // In-memory drone registry
    private final Map<String, Map<String, Object>> droneRegistry = new ConcurrentHashMap<>();

    @PostConstruct
    public void init() {
        // Seed some synthetic drones
        Random rng = new Random(42);
        for (int i = 0; i < 15; i++) {
            Map<String, Object> drone = new HashMap<>();
            drone.put("id", "drone_" + i);
            drone.put("name", "Quadcopter " + (char) ('A' + i));
            drone.put("battery", 60 + rng.nextInt(40));
            drone.put("status", "idle");
            drone.put("latitude", 9.0820 + (rng.nextDouble() - 0.5) * 0.5); // Nigeria centric
            drone.put("longitude", 7.4913 + (rng.nextDouble() - 0.5) * 0.5);
            drone.put("hasLoRa", i < 10);
            drone.put("lastSeen", System.currentTimeMillis());
            droneRegistry.put("drone_" + i, drone);
        }
    }

    public List<Map<String, Object>> getAvailableDrones(double lat, double lng) {
        return droneRegistry.values().stream()
                .filter(d -> "idle".equals(d.get("status")) && (int) d.get("battery") > 20)
                .sorted((a, b) -> Double.compare(
                        calcDistance(lat, lng, (double) a.get("latitude"), (double) a.get("longitude")),
                        calcDistance(lat, lng, (double) b.get("latitude"), (double) b.get("longitude"))
                ))
                .collect(Collectors.toList());
    }

    public Map<String, Object> deployRelay(double lat, double lng, String reason) {
        List<Map<String, Object>> available = getAvailableDrones(lat, lng).stream()
                .filter(d -> (boolean) d.getOrDefault("hasLoRa", false))
                .collect(Collectors.toList());

        if (available.isEmpty()) {
            log.warn("No LoRa-enabled drones available for relay at {}, {}", lat, lng);
            return null;
        }

        Map<String, Object> drone = available.get(0);
        String droneId = (String) drone.get("id");
        
        drone.put("status", "deploying");
        drone.put("targetLat", lat);
        drone.put("targetLng", lng);
        drone.put("mission", "emergency_relay");
        drone.put("reason", reason);

        log.info("Relay drone {} deployed to {}, {} for: {}", droneId, lat, lng, reason);
        return drone;
    }

    /**
     * Automatically deploys a drone relay if the alert is in a known dead-zone
     * or is of critical priority in a high-risk state.
     */
    public void deployRelayIfNecessary(String lga, String state, double lat, double lng, int priority) {
        boolean isHighRisk = List.of("Borno", "Yobe", "Adamawa", "Kaduna", "Zamfara").contains(state);
        
        if (priority >= 3 && isHighRisk) {
            log.info("High-risk SOS detected in {}, {}. Initiating drone relay deployment.", lga, state);
            deployRelay(lat, lng, "High-risk SOS in " + lga);
        }
    }

    private double calcDistance(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                        Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371 * c;
    }
}
