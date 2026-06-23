package com.dangeremergence.controller;

import com.dangeremergence.model.Zone;
import com.dangeremergence.repository.ZoneRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/digital-twin")
public class DigitalTwinController {

    private static final Logger log = LoggerFactory.getLogger(DigitalTwinController.class);

    private final ZoneRepository zoneRepository;

    public DigitalTwinController(ZoneRepository zoneRepository) {
        this.zoneRepository = zoneRepository;
    }

    // In-memory cache for city data (in production, use Redis or database)
    private final Map<String, Map<String, Object>> cityCache = new HashMap<>();

    @GetMapping("/cities/{cityId}/tileset")
    public ResponseEntity<Map<String, Object>> getCityTileset(@PathVariable String cityId) {
        Map<String, Object> tileset = getOrCreateCityData(cityId);

        Map<String, Object> response = new HashMap<>();
        response.put("cityId", cityId);
        response.put("tilesetUrl", "/api/v1/digital-twin/cities/" + cityId + "/tiles/{z}/{x}/{y}.pbf");
        response.put("center", tileset.get("center"));
        response.put("zoom", tileset.get("zoom"));
        response.put("bounds", tileset.get("bounds"));

        return ResponseEntity.ok(response);
    }

    @GetMapping("/cities/{cityId}/buildings")
    public ResponseEntity<Map<String, Object>> getBuildings(@PathVariable String cityId) {
        Map<String, Object> cityData = getOrCreateCityData(cityId);

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> buildings = (List<Map<String, Object>>) cityData.getOrDefault("buildings", List.of());

        return ResponseEntity.ok(Map.of(
                "cityId", cityId,
                "buildings", buildings,
                "count", buildings.size()
        ));
    }

    @PostMapping("/predict-propagation")
    public ResponseEntity<Map<String, Object>> predictPropagation(@RequestBody Map<String, Object> request) {
        String cityId = (String) request.getOrDefault("cityId", "default");
        String hazardType = (String) request.getOrDefault("hazardType", "fire");
        double originLat = ((Number) request.getOrDefault("originLat", 0.0)).doubleValue();
        double originLng = ((Number) request.getOrDefault("originLng", 0.0)).doubleValue();
        double windSpeed = ((Number) request.getOrDefault("windSpeed", 0.0)).doubleValue();
        double windDirection = ((Number) request.getOrDefault("windDirection", 0.0)).doubleValue();

        // Simulate hazard propagation using a simple cellular automaton
        // In production, this would use GPU-accelerated fluid dynamics
        List<Map<String, Object>> propagationCells = simulatePropagation(
                originLat, originLng, hazardType, windSpeed, windDirection
        );

        // Identify buildings at risk
        List<Map<String, Object>> buildingsAtRisk = identifyBuildingsAtRisk(cityId, propagationCells);

        // Generate evacuation plan
        Map<String, Object> evacuationPlan = generateEvacuationPlan(originLat, originLng, buildingsAtRisk);

        Map<String, Object> response = new HashMap<>();
        response.put("propagationCells", propagationCells);
        response.put("buildingsAtRisk", buildingsAtRisk);
        response.put("evacuationPlan", evacuationPlan);
        response.put("hazardType", hazardType);
        response.put("simulationTimeMs", propagationCells.size() * 50); // Estimated computation time

        return ResponseEntity.ok(response);
    }

    @PostMapping("/evacuation-plan")
    public ResponseEntity<Map<String, Object>> getEvacuationPlan(@RequestBody Map<String, Object> request) {
        double latitude = ((Number) request.getOrDefault("latitude", 0.0)).doubleValue();
        double longitude = ((Number) request.getOrDefault("longitude", 0.0)).doubleValue();

        // Find nearest safe zones
        List<Map<String, Object>> safeZones = findNearestSafeZones(latitude, longitude);

        Map<String, Object> plan = new HashMap<>();
        plan.put("originLat", latitude);
        plan.put("originLng", longitude);
        plan.put("safeZones", safeZones);
        plan.put("nearestExit", safeZones.isEmpty() ? null : safeZones.get(0));
        plan.put("evacuationFeasible", !safeZones.isEmpty());

        return ResponseEntity.ok(plan);
    }

    /**
     * Simulate hazard propagation using a simple grid-based model.
     */
    private List<Map<String, Object>> simulatePropagation(
            double originLat, double originLng, String hazardType,
            double windSpeed, double windDirection) {

        List<Map<String, Object>> cells = new ArrayList<>();
        Random rng = new Random(Objects.hash(originLat, originLng));

        double windRad = Math.toRadians(windDirection);
        double windLat = Math.cos(windRad) * windSpeed * 0.0001;
        double windLng = Math.sin(windRad) * windSpeed * 0.0001;

        // Generate propagation in concentric rings
        for (int ring = 0; ring < 10; ring++) {
            int pointsInRing = (ring + 1) * 4;
            for (int p = 0; p < pointsInRing; p++) {
                double angle = 2 * Math.PI * p / pointsInRing;
                double radius = (ring + 1) * 0.0005; // ~50m per ring

                double lat = originLat + Math.cos(angle) * radius + windLat * ring;
                double lng = originLng + Math.sin(angle) * radius + windLng * ring;

                double intensity = Math.max(0, 1.0 - (ring * 0.1)) + (rng.nextDouble() - 0.5) * 0.2;
                intensity = Math.max(0, Math.min(1, intensity));

                if (intensity > 0.1) {
                    Map<String, Object> cell = new HashMap<>();
                    cell.put("lat", Math.round(lat * 1e6) / 1e6);
                    cell.put("lng", Math.round(lng * 1e6) / 1e6);
                    cell.put("arrivalTime", ring * 60); // seconds
                    cell.put("intensity", Math.round(intensity * 100.0) / 100.0);
                    cells.add(cell);
                }
            }
        }

        return cells;
    }

    /**
     * Identify buildings at risk from propagation cells.
     */
    private List<Map<String, Object>> identifyBuildingsAtRisk(String cityId, List<Map<String, Object>> propagationCells) {
        Map<String, Object> cityData = getOrCreateCityData(cityId);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> buildings = (List<Map<String, Object>>) cityData.getOrDefault("buildings", List.of());

        List<Map<String, Object>> atRisk = new ArrayList<>();

        for (Map<String, Object> building : buildings) {
            double bLat = ((Number) building.getOrDefault("latitude", 0.0)).doubleValue();
            double bLng = ((Number) building.getOrDefault("longitude", 0.0)).doubleValue();

            for (Map<String, Object> cell : propagationCells) {
                double cLat = ((Number) cell.get("lat")).doubleValue();
                double cLng = ((Number) cell.get("lng")).doubleValue();

                double dist = Math.sqrt(Math.pow(bLat - cLat, 2) + Math.pow(bLng - cLng, 2));
                if (dist < 0.001) { // ~100m
                    Map<String, Object> risk = new HashMap<>(building);
                    risk.put("arrivalTime", cell.get("arrivalTime"));
                    risk.put("intensity", cell.get("intensity"));
                    atRisk.add(risk);
                    break;
                }
            }
        }

        atRisk.sort((a, b) -> Integer.compare(
                (int) a.getOrDefault("arrivalTime", Integer.MAX_VALUE),
                (int) b.getOrDefault("arrivalTime", Integer.MAX_VALUE)
        ));

        return atRisk;
    }

    /**
     * Generate evacuation plan based on hazard location.
     */
    private Map<String, Object> generateEvacuationPlan(
            double hazardLat, double hazardLng, List<Map<String, Object>> buildingsAtRisk) {

        List<Map<String, Object>> safeZones = findNearestSafeZones(hazardLat, hazardLng);

        Map<String, Object> plan = new HashMap<>();
        plan.put("hazardLocation", Map.of("lat", hazardLat, "lng", hazardLng));
        plan.put("safeZones", safeZones);
        plan.put("nearestSafeCorridor", safeZones.isEmpty() ? null : safeZones.get(0));
        plan.put("buildingsToEvacuate", buildingsAtRisk.size());
        plan.put("evacuationFeasible", !safeZones.isEmpty());

        return plan;
    }

    /**
     * Find nearest safe zones to a location by querying the database.
     */
    private List<Map<String, Object>> findNearestSafeZones(double lat, double lng) {
        List<Map<String, Object>> result = new ArrayList<>();

        // Query the database for active safety-type zones
        List<Zone> dbZones = zoneRepository.findByTypeAndStatus(
                Zone.ZoneType.safety.name(), Zone.ZoneStatus.active);

        if (dbZones.isEmpty()) {
            log.warn("No safe zones found in database for location ({}, {})", lat, lng);
            return result;
        }

        // Calculate distance for each zone and sort by proximity
        for (Zone zone : dbZones) {
            double distanceKm = Math.round(
                    haversineDistance(lat, lng, zone.getLatitude(), zone.getLongitude()) * 10.0
            ) / 10.0;

            Map<String, Object> z = new HashMap<>();
            z.put("name", zone.getName());
            z.put("latitude", zone.getLatitude());
            z.put("longitude", zone.getLongitude());
            z.put("capacity", 500); // default capacity
            z.put("distanceKm", distanceKm);
            z.put("zoneId", zone.getId());
            z.put("description", zone.getDescription() != null ? zone.getDescription() : "");
            result.add(z);
        }

        result.sort(Comparator.comparingDouble(z -> (double) z.get("distanceKm")));
        return result;
    }

    /**
     * Calculate Haversine distance between two coordinates in km.
     */
    private double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
        final double R = 6371.0; // Earth radius in km
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    /**
     * Get or create cached city data.
     */
    private Map<String, Object> getOrCreateCityData(String cityId) {
        return cityCache.computeIfAbsent(cityId, id -> {
            Map<String, Object> data = new HashMap<>();
            data.put("center", Map.of("lat", 40.7128, "lng", -74.0060));
            data.put("zoom", 14);
            data.put("bounds", Map.of(
                    "minLat", 40.7000, "maxLat", 40.7300,
                    "minLng", -74.0200, "maxLng", -73.9900
            ));

            // Generate synthetic buildings
            List<Map<String, Object>> buildings = new ArrayList<>();
            Random rng = new Random(cityId.hashCode());
            double baseLat = 40.7128;
            double baseLng = -74.0060;

            for (int i = 0; i < 50; i++) {
                Map<String, Object> building = new HashMap<>();
                building.put("id", "bldg_" + i);
                building.put("name", "Building " + (i + 1));
                building.put("latitude", baseLat + (rng.nextDouble() - 0.5) * 0.02);
                building.put("longitude", baseLng + (rng.nextDouble() - 0.5) * 0.02);
                building.put("floors", 1 + rng.nextInt(20));
                building.put("type", rng.nextDouble() > 0.7 ? "residential" : "commercial");
                building.put("occupancy", 10 + rng.nextInt(200));
                buildings.add(building);
            }
            data.put("buildings", buildings);

            return data;
        });
    }
}
