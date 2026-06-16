package com.dangeremergence.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;

/**
 * Service that communicates with the ML service for predictive analytics.
 *
 * Acts as a proxy between the backend controllers and the Python ML service.
 * All methods call the ML service's predictive endpoints via HTTP,
 * parse the JSON responses, and return structured Java Maps.
 *
 * Falls back to cached results or synthetic data if the ML service is unreachable.
 */
@Service
public class PredictiveService {

    private static final Logger log = LoggerFactory.getLogger(PredictiveService.class);

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final PredictionCacheService cacheService;
    private final SimpMessagingTemplate messagingTemplate;

    @Value("${ml.service.url:http://ml-service:8000}")
    private String mlServiceUrl;

    @Value("${ml.service.api-key:}")
    private String mlApiKey;

    @Autowired
    public PredictiveService(PredictionCacheService cacheService,
                             SimpMessagingTemplate messagingTemplate) {
        this.cacheService = cacheService;
        this.messagingTemplate = messagingTemplate;
        this.objectMapper = new ObjectMapper();
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /**
     * Build an HttpRequest with optional ML API key auth header.
     */
    private HttpRequest.Builder mlRequestBuilder(String path) {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(mlServiceUrl + path))
                .header("Content-Type", "application/json")
                .timeout(Duration.ofSeconds(15));
        if (mlApiKey != null && !mlApiKey.isBlank()) {
            builder.header("Authorization", "ApiKey " + mlApiKey);
        }
        return builder;
    }

    /**
     * Get a forecast for a specific geographic area.
     *
     * @param latitude  Center latitude
     * @param longitude Center longitude
     * @param radiusKm  Search radius in kilometers
     * @param hours     Forecast horizon in hours
     * @return Forecast response with time series and hotspots
     */
    public Map<String, Object> getForecast(double latitude, double longitude, double radiusKm, int hours) {
        String cacheKey = cacheService.buildAreaCacheKey(latitude, longitude, radiusKm, hours);

        // Try cache first
        Optional<Map<String, Object>> cached = cacheService.getCachedForecast(cacheKey);
        if (cached.isPresent()) {
            return cached.get();
        }

        try {
            ObjectNode body = objectMapper.createObjectNode();
            body.put("latitude", latitude);
            body.put("longitude", longitude);
            body.put("radius_km", radiusKm);
            body.put("hours", hours);

            HttpRequest request = mlRequestBuilder("/api/v1/predictive/forecast")
                    .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body)))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                cacheService.cacheForecast(cacheKey, result);
                return result;
            } else {
                log.warn("ML service returned {} for forecast: {}", response.statusCode(), response.body());
                return fallbackForecast(latitude, longitude, hours);
            }
        } catch (Exception e) {
            log.error("Failed to call ML service for forecast: {}", e.getMessage());
            return fallbackForecast(latitude, longitude, hours);
        }
    }

    /**
     * Get batch forecasts for multiple areas.
     *
     * @param areas List of {latitude, longitude, radius_km, hours} maps
     * @return Batch forecast response
     */
    public Map<String, Object> getBatchForecast(List<Map<String, Object>> areas) {
        String cacheKey = "batch_" + Integer.toHexString(areas.hashCode());

        Optional<Map<String, Object>> cached = cacheService.getCachedBatchForecast(cacheKey);
        if (cached.isPresent()) {
            return cached.get();
        }

        try {
            ArrayNode areasArray = objectMapper.createArrayNode();
            for (Map<String, Object> area : areas) {
                ObjectNode areaNode = objectMapper.createObjectNode();
                areaNode.put("latitude", ((Number) area.getOrDefault("latitude", 0.0)).doubleValue());
                areaNode.put("longitude", ((Number) area.getOrDefault("longitude", 0.0)).doubleValue());
                areaNode.put("radius_km", ((Number) area.getOrDefault("radius_km", 50.0)).doubleValue());
                areaNode.put("hours", ((Number) area.getOrDefault("hours", 48)).intValue());
                areasArray.add(areaNode);
            }

            ObjectNode body = objectMapper.createObjectNode();
            body.set("areas", areasArray);

            HttpRequest request = mlRequestBuilder("/api/v1/predictive/forecast/batch")
                    .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body)))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                cacheService.cacheBatchForecast(cacheKey, result);
                return result;
            } else {
                log.warn("ML service returned {} for batch forecast", response.statusCode());
                return Map.of("forecasts", List.of(), "error", "ML service unavailable");
            }
        } catch (Exception e) {
            log.error("Failed to call ML service for batch forecast: {}", e.getMessage());
            return Map.of("forecasts", List.of(), "error", e.getMessage());
        }
    }

    /**
     * Detect hotspots (high-risk areas) within a geographic region.
     *
     * @param latitude  Center latitude
     * @param longitude Center longitude
     * @param radiusKm  Search radius in kilometers
     * @return Hotspot response with list of hotspot predictions
     */
    public Map<String, Object> detectHotspots(double latitude, double longitude, double radiusKm) {
        String cacheKey = cacheService.buildAreaCacheKey(latitude, longitude, radiusKm, 24);

        Optional<List<Map<String, Object>>> cachedHotspots = cacheService.getCachedHotspots(cacheKey);
        if (cachedHotspots.isPresent()) {
            return Map.of("hotspots", cachedHotspots.get(), "cached", true);
        }

        try {
            ObjectNode body = objectMapper.createObjectNode();
            body.put("latitude", latitude);
            body.put("longitude", longitude);
            body.put("radius_km", radiusKm);

            HttpRequest request = mlRequestBuilder("/api/v1/predictive/hotspots")
                    .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body)))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> hotspots = (List<Map<String, Object>>) result.getOrDefault("hotspots", List.of());
                cacheService.cacheHotspots(cacheKey, hotspots);

                // Publish hotspot predictions via WebSocket for real-time delivery
                publishHotspotsToWebSocket(hotspots, latitude, longitude, radiusKm);

                return result;
            } else {
                log.warn("ML service returned {} for hotspots", response.statusCode());
                return Map.of("hotspots", List.of(), "error", "ML service unavailable");
            }
        } catch (Exception e) {
            log.error("Failed to call ML service for hotspots: {}", e.getMessage());
            return Map.of("hotspots", List.of(), "error", e.getMessage());
        }
    }

    /**
     * Trigger model training on the ML service.
     *
     * @param forceRetrain If true, forces retraining even if models exist
     * @return Training response with status
     */
    public Map<String, Object> triggerTraining(boolean forceRetrain) {
        try {
            ObjectNode body = objectMapper.createObjectNode();
            body.put("force_retrain", forceRetrain);

            HttpRequest request = mlRequestBuilder("/api/v1/predictive/train")
                    .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body)))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                // Evict all caches since models have changed
                cacheService.evictAll();
                return result;
            } else {
                log.warn("ML service returned {} for training", response.statusCode());
                return Map.of("status", "failed", "error", "ML service unavailable");
            }
        } catch (Exception e) {
            log.error("Failed to trigger training: {}", e.getMessage());
            return Map.of("status", "failed", "error", e.getMessage());
        }
    }

    /**
     * Get the current training status from the ML service.
     */
    public Map<String, Object> getTrainingStatus() {
        try {
            HttpRequest request = mlRequestBuilder("/api/v1/predictive/training-status")
                    .GET()
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                return result;
            }
        } catch (Exception e) {
            log.warn("Failed to get training status: {}", e.getMessage());
        }
        return Map.of("is_training", false, "status", "unknown");
    }

    /**
     * Get model information (version, metrics, feature importance).
     */
    public Map<String, Object> getModelInfo() {
        try {
            HttpRequest request = mlRequestBuilder("/api/v1/predictive/model-info")
                    .GET()
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                return result;
            }
        } catch (Exception e) {
            log.warn("Failed to get model info: {}", e.getMessage());
        }
        return Map.of("status", "unavailable", "error", "ML service not reachable");
    }

    /**
     * Get forecast for all 36 Nigerian states + FCT.
     */
    public Map<String, Object> getAllStatesForecast() {
        Optional<Map<String, Object>> cached = cacheService.getCachedAllStatesForecast();
        if (cached.isPresent()) {
            return cached.get();
        }

        try {
            HttpRequest request = mlRequestBuilder("/api/v1/predictive/forecast/all-states")
                    .POST(HttpRequest.BodyPublishers.noBody())
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                cacheService.cacheAllStatesForecast(result);
                return result;
            }
        } catch (Exception e) {
            log.warn("Failed to get all-states forecast: {}", e.getMessage());
        }
        return Map.of("forecasts", List.of(), "error", "ML service not reachable");
    }

    /**
     * Check if the ML service is healthy and the predictive model is loaded.
     */
    public Map<String, Object> healthCheck() {
        try {
            HttpRequest request = mlRequestBuilder("/api/v1/predictive/health")
                    .GET()
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() == 200) {
                @SuppressWarnings("unchecked")
                Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);
                return result;
            }
        } catch (Exception e) {
            log.warn("Predictive health check failed: {}", e.getMessage());
        }
        return Map.of("status", "unavailable", "model_loaded", false);
    }

    /**
     * Fallback forecast when ML service is unreachable.
     * Returns a simple synthetic forecast based on the area coordinates.
     */
    private Map<String, Object> fallbackForecast(double latitude, double longitude, int hours) {
        List<Map<String, Object>> forecastPoints = new ArrayList<>();
        long now = System.currentTimeMillis();
        long intervalMs = 3600000L; // 1-hour intervals

        double baseRisk = calculateBaseRisk(latitude, longitude);

        for (int i = 0; i < hours; i++) {
            long ts = now + (i * intervalMs);
            double seasonal = Math.sin(2 * Math.PI * i / 24.0) * 0.1;
            double noise = (new Random().nextDouble() - 0.5) * 0.05;
            double riskScore = Math.max(0.0, Math.min(1.0, baseRisk + seasonal + noise));

            Map<String, Object> point = new HashMap<>();
            point.put("timestamp", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
                    .format(new java.util.Date(ts)));
            point.put("risk_score", riskScore);
            point.put("alert_level", getAlertLevel(riskScore));
            forecastPoints.add(point);
        }

        return Map.of(
                "latitude", latitude,
                "longitude", longitude,
                "forecast", forecastPoints,
                "source", "fallback"
        );
    }

    /**
     * Calculate a base risk score from geographic coordinates.
     * Higher risk near known conflict zones in Nigeria.
     */
    private double calculateBaseRisk(double latitude, double longitude) {
        // Known high-risk areas in Nigeria (Borno, Yobe, Adamawa, Kaduna, Plateau)
        double[][] highRiskZones = {
                {11.8, 13.2},  // Maiduguri, Borno
                {12.0, 11.5},  // Yobe
                {10.3, 12.4},  // Adamawa
                {10.5, 7.4},   // Kaduna
                {9.9, 8.9},    // Jos, Plateau
                {9.1, 7.5},    // Abuja (FCT)
                {6.5, 7.5},    // Enugu
                {4.8, 7.0},    // Port Harcourt
                {6.4, 7.5},    // Anambra
                {12.5, 4.5}    // Sokoto
        };

        double minDistance = Double.MAX_VALUE;
        for (double[] zone : highRiskZones) {
            double dist = haversine(latitude, longitude, zone[0], zone[1]);
            if (dist < minDistance) minDistance = dist;
        }

        // Risk decays with distance from known zones
        double risk = Math.max(0.1, 0.7 - (minDistance / 500.0));
        return Math.min(0.9, risk);
    }

    private String getAlertLevel(double riskScore) {
        if (riskScore >= 0.8) return "Critical";
        if (riskScore >= 0.6) return "Severe";
        if (riskScore >= 0.4) return "High";
        if (riskScore >= 0.2) return "Elevated";
        return "Normal";
    }

    private double haversine(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371.0; // Earth radius in km
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                   Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    /**
     * Publish hotspot predictions to WebSocket topics for real-time delivery.
     * Subscribers (frontend ThreatAwarenessService) receive these instantly.
     */
    private void publishHotspotsToWebSocket(
            List<Map<String, Object>> hotspots, double latitude, double longitude, double radiusKm) {
        try {
            Map<String, Object> message = new HashMap<>();
            message.put("type", "HOTSPOT_UPDATE");
            message.put("latitude", latitude);
            message.put("longitude", longitude);
            message.put("radius_km", radiusKm);
            message.put("hotspots", hotspots);
            message.put("timestamp", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
                    .format(new java.util.Date()));
            message.put("count", hotspots.size());

            // Publish to global prediction topic
            messagingTemplate.convertAndSend("/topic/predictions/hotspots", message);

            // Publish to general prediction updates topic
            messagingTemplate.convertAndSend("/topic/predictions/updates", Map.of(
                    "type", "HOTSPOT_UPDATE",
                    "count", hotspots.size(),
                    "timestamp", message.get("timestamp")
            ));

            log.info("Published {} hotspot predictions to WebSocket", hotspots.size());
        } catch (Exception e) {
            log.warn("Failed to publish hotspots to WebSocket: {}", e.getMessage());
        }
    }

    /**
     * Publish a general prediction update notification to WebSocket.
     * Called after training completes or new forecast data is available.
     */
    public void publishPredictionUpdate(String updateType, Map<String, Object> data) {
        try {
            Map<String, Object> message = new HashMap<>(data);
            message.put("type", updateType);
            message.put("timestamp", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
                    .format(new java.util.Date()));

            messagingTemplate.convertAndSend("/topic/predictions/updates", message);
            log.debug("Published prediction update '{}' to WebSocket", updateType);
        } catch (Exception e) {
            log.warn("Failed to publish prediction update: {}", e.getMessage());
        }
    }
}
