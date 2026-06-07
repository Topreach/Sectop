package com.dangeremergence.controller;

import com.dangeremergence.model.Zone;
import com.dangeremergence.service.ZoneService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/predictive")
public class PredictiveController {

    private static final Logger log = LoggerFactory.getLogger(PredictiveController.class);

    @Autowired
    private ZoneService zoneService;

    @PostMapping("/forecast")
    public ResponseEntity<Map<String, Object>> forecast(@RequestBody Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        List<String> zoneIds = (List<String>) request.getOrDefault("zoneIds", List.of());
        int historyHours = (int) request.getOrDefault("historyHours", 72);
        int forecastHours = (int) request.getOrDefault("forecastHours", 6);

        if (zoneIds.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "zoneIds is required"));
        }

        List<Map<String, Object>> forecasts = new ArrayList<>();
        long now = Instant.now().toEpochMilli();

        for (String zoneId : zoneIds) {
            Optional<Zone> zoneOpt = zoneService.getZoneById(zoneId);
            if (zoneOpt.isEmpty()) continue;

            Zone zone = zoneOpt.get();
            Map<String, Object> forecast = generateForecast(zone, historyHours, forecastHours, now);
            forecasts.add(forecast);
        }

        return ResponseEntity.ok(Map.of("forecasts", forecasts));
    }

    @PostMapping("/anomaly")
    public ResponseEntity<Map<String, Object>> detectAnomaly(@RequestBody Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        List<Number> values = (List<Number>) request.getOrDefault("values", List.of());

        if (values.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "values is required"));
        }

        List<Double> doubleValues = values.stream().map(Number::doubleValue).collect(Collectors.toList());

        double mean = doubleValues.stream().mapToDouble(Double::doubleValue).average().orElse(0.0);
        double variance = doubleValues.stream()
                .mapToDouble(v -> Math.pow(v - mean, 2))
                .average()
                .orElse(0.0);
        double stdDev = Math.sqrt(variance);

        double zScoreThreshold = 3.0;
        List<Map<String, Object>> anomalies = new ArrayList<>();

        for (int i = 0; i < doubleValues.size(); i++) {
            double zScore = stdDev > 0 ? Math.abs((doubleValues.get(i) - mean) / stdDev) : 0;
            if (zScore > zScoreThreshold) {
                Map<String, Object> anomaly = new HashMap<>();
                anomaly.put("index", i);
                anomaly.put("value", doubleValues.get(i));
                anomaly.put("zScore", zScore);
                anomaly.put("severity", zScore > 5.0 ? "critical" : "warning");
                anomalies.add(anomaly);
            }
        }

        return ResponseEntity.ok(Map.of(
                "anomalies", anomalies,
                "mean", mean,
                "stdDev", stdDev,
                "threshold", zScoreThreshold
        ));
    }

    @PostMapping("/optimize-resources")
    public ResponseEntity<Map<String, Object>> optimizeResources(@RequestBody Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> zones = (List<Map<String, Object>>) request.getOrDefault("zones", List.of());
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> responders = (List<Map<String, Object>>) request.getOrDefault("responders", List.of());

        if (zones.isEmpty() || responders.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "zones and responders are required"));
        }

        // Simplified Hungarian algorithm using greedy assignment
        List<Map<String, Object>> assignments = new ArrayList<>();
        List<Map<String, Object>> availableResponders = new ArrayList<>(responders);

        // Sort zones by priority (highest first)
        List<Map<String, Object>> sortedZones = new ArrayList<>(zones);
        sortedZones.sort((a, b) -> {
            int pa = (int) a.getOrDefault("priority", 0);
            int pb = (int) b.getOrDefault("priority", 0);
            return Integer.compare(pb, pa);
        });

        for (Map<String, Object> zone : sortedZones) {
            if (availableResponders.isEmpty()) break;

            double zoneLat = ((Number) zone.getOrDefault("latitude", 0.0)).doubleValue();
            double zoneLng = ((Number) zone.getOrDefault("longitude", 0.0)).doubleValue();
            String requiredSkill = (String) zone.getOrDefault("requiredSkill", "general");

            // Find best responder (closest + matching skill)
            Map<String, Object> bestResponder = null;
            double bestCost = Double.MAX_VALUE;

            for (Map<String, Object> responder : availableResponders) {
                double respLat = ((Number) responder.getOrDefault("latitude", 0.0)).doubleValue();
                double respLng = ((Number) responder.getOrDefault("longitude", 0.0)).doubleValue();
                String skill = (String) responder.getOrDefault("skill", "general");
                int availability = (int) responder.getOrDefault("availability", 100);

                // Distance cost (Euclidean approximation)
                double distance = Math.sqrt(Math.pow(zoneLat - respLat, 2) + Math.pow(zoneLng - respLng, 2));

                // Skill match bonus
                double skillCost = skill.equals(requiredSkill) ? 0 : 2.0;

                // Availability bonus
                double availabilityCost = 1.0 - (availability / 100.0);

                double totalCost = distance + skillCost + availabilityCost;

                if (totalCost < bestCost) {
                    bestCost = totalCost;
                    bestResponder = responder;
                }
            }

            if (bestResponder != null) {
                Map<String, Object> assignment = new HashMap<>();
                assignment.put("zoneId", zone.get("id"));
                assignment.put("responderId", bestResponder.get("id"));
                assignment.put("responderName", bestResponder.get("name"));
                assignment.put("cost", bestCost);
                assignment.put("etaMinutes", (int) (bestCost * 5)); // Rough ETA estimate
                assignments.add(assignment);
                availableResponders.remove(bestResponder);
            }
        }

        return ResponseEntity.ok(Map.of(
                "assignments", assignments,
                "unassignedZones", sortedZones.size() - assignments.size(),
                "unassignedResponders", availableResponders.size()
        ));
    }

    /**
     * Generate a simple time-series forecast for a zone.
     * Uses linear regression on historical trend with seasonal decomposition.
     */
    private Map<String, Object> generateForecast(Zone zone, int historyHours, int forecastHours, long now) {
        long intervalMs = 300000L; // 5-minute intervals
        int historyPoints = (historyHours * 60) / 5;
        int forecastPoints = (forecastHours * 60) / 5;

        // Generate synthetic historical data based on zone severity
        // In production, this would query actual historical data
        List<Double> historicalValues = new ArrayList<>();
        List<Long> historicalTimestamps = new ArrayList<>();

        double baseValue = getBaseValueForSeverity(zone.getSeverity());
        Random rng = new Random(zone.getId().hashCode());

        for (int i = historyPoints; i >= 0; i--) {
            long ts = now - (i * intervalMs);
            double seasonal = Math.sin(2 * Math.PI * i / 288.0) * 0.2; // 24-hour seasonality
            double noise = (rng.nextDouble() - 0.5) * 0.3;
            double trend = 0.001 * i; // Slight upward trend
            historicalValues.add(baseValue + seasonal + noise + trend);
            historicalTimestamps.add(ts);
        }

        // Simple linear regression for forecast
        int n = historicalValues.size();
        double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
        for (int i = 0; i < n; i++) {
            sumX += i;
            sumY += historicalValues.get(i);
            sumXY += i * historicalValues.get(i);
            sumX2 += i * i;
        }

        double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
        double intercept = (sumY - slope * sumX) / n;

        // Generate forecast
        List<Double> forecastValues = new ArrayList<>();
        List<Long> forecastTimestamps = new ArrayList<>();
        for (int i = 1; i <= forecastPoints; i++) {
            long ts = now + (i * intervalMs);
            double seasonal = Math.sin(2 * Math.PI * (n + i) / 288.0) * 0.2;
            double predicted = slope * (n + i) + intercept + seasonal;
            forecastValues.add(Math.max(0, predicted));
            forecastTimestamps.add(ts);
        }

        // Detect trend direction
        String trend = slope > 0.01 ? "increasing" : slope < -0.01 ? "decreasing" : "stable";

        // Identify hotspots (peaks in forecast)
        List<Map<String, Object>> hotspots = new ArrayList<>();
        for (int i = 2; i < forecastValues.size() - 2; i++) {
            if (forecastValues.get(i) > forecastValues.get(i - 1) &&
                    forecastValues.get(i) > forecastValues.get(i - 2) &&
                    forecastValues.get(i) > forecastValues.get(i + 1) &&
                    forecastValues.get(i) > forecastValues.get(i + 2)) {
                if (forecastValues.get(i) > baseValue * 1.5) {
                    Map<String, Object> hotspot = new HashMap<>();
                    hotspot.put("time", forecastTimestamps.get(i));
                    hotspot.put("value", forecastValues.get(i));
                    hotspot.put("severity", forecastValues.get(i) > baseValue * 2.0 ? "critical" : "high");
                    hotspots.add(hotspot);
                }
            }
        }

        Map<String, Object> forecast = new HashMap<>();
        forecast.put("zoneId", zone.getId());
        forecast.put("zoneName", zone.getName());
        forecast.put("timestamps", forecastTimestamps);
        forecast.put("predictedValues", forecastValues);
        forecast.put("trend", trend);
        forecast.put("hotspots", hotspots);
        forecast.put("escalationTime", hotspots.isEmpty() ? null :
                Instant.ofEpochMilli((long) hotspots.get(0).get("time")).toString());

        return forecast;
    }

    private double getBaseValueForSeverity(String severity) {
        if (severity == null) return 1.0;
        switch (severity.toLowerCase()) {
            case "critical": return 5.0;
            case "high": return 3.0;
            case "medium": return 2.0;
            case "low": return 1.0;
            default: return 1.0;
        }
    }
}
