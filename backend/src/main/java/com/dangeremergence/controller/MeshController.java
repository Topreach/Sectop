package com.dangeremergence.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/mesh")
public class MeshController {

    private static final Logger log = LoggerFactory.getLogger(MeshController.class);

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    private static final String MESH_PEER_KEY = "mesh:peers";
    private static final String ROUTING_TABLE_KEY = "mesh:routing";

    @PostMapping("/route")
    public ResponseEntity<Map<String, Object>> findRoute(@RequestBody Map<String, Object> request) {
        String sourceDeviceId = (String) request.getOrDefault("sourceDeviceId", "");
        String targetDeviceId = (String) request.getOrDefault("targetDeviceId", "");

        if (sourceDeviceId.isBlank() || targetDeviceId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "sourceDeviceId and targetDeviceId are required"));
        }

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> neighborMetrics =
                (List<Map<String, Object>>) request.getOrDefault("neighborMetrics", List.of());

        // Update peer registry in Redis with neighbor metrics
        for (Map<String, Object> neighbor : neighborMetrics) {
            String deviceId = (String) neighbor.get("deviceId");
            if (deviceId != null) {
                redisTemplate.opsForHash().put(MESH_PEER_KEY, deviceId, neighbor);
            }
        }
        redisTemplate.expire(MESH_PEER_KEY, Duration.ofHours(24));

        // B.A.T.M.A.N. + AODV hybrid path finding
        List<String> path = findOptimalPath(sourceDeviceId, targetDeviceId, neighborMetrics);

        if (path.isEmpty()) {
            return ResponseEntity.ok(Map.of(
                    "path", List.of(),
                    "totalCost", Double.MAX_VALUE,
                    "estimatedHops", 0,
                    "strategy", "aodv",
                    "message", "No route found to target"
            ));
        }

        double totalCost = calculatePathCost(path, neighborMetrics);

        Map<String, Object> result = new HashMap<>();
        result.put("path", path);
        result.put("totalCost", Math.round(totalCost * 100.0) / 100.0);
        result.put("estimatedHops", path.size() - 1);
        result.put("strategy", path.size() > 3 ? "batman_adv" : "aodv");

        return ResponseEntity.ok(result);
    }

    @PostMapping("/broadcast")
    public ResponseEntity<Map<String, Object>> broadcastMessage(@RequestBody Map<String, Object> request) {
        String sourceDeviceId = (String) request.getOrDefault("sourceDeviceId", "");
        String messageType = (String) request.getOrDefault("messageType", "text");
        int priority = (int) request.getOrDefault("priority", 0);

        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) request.getOrDefault("payload", Map.of());

        if (sourceDeviceId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "sourceDeviceId is required"));
        }

        // Simulate mesh broadcast
        long peerCount = redisTemplate.opsForHash().size(MESH_PEER_KEY);
        int estimatedReach = (int) Math.min(peerCount, 10L + (long) priority * 5);
        
        Set<Object> peerIds = redisTemplate.opsForHash().keys(MESH_PEER_KEY);
        List<String> relayedTo = peerIds.stream()
                .map(Object::toString)
                .limit(estimatedReach)
                .collect(Collectors.toList());

        Map<String, Object> result = new HashMap<>();
        result.put("messageId", UUID.randomUUID().toString());
        result.put("sourceDeviceId", sourceDeviceId);
        result.put("messageType", messageType);
        result.put("priority", priority);
        result.put("relayedTo", relayedTo);
        result.put("estimatedReach", estimatedReach);
        result.put("hops", Math.min(relayedTo.size(), 5));

        return ResponseEntity.ok(result);
    }

    @GetMapping("/peers")
    public ResponseEntity<Map<String, Object>> getPeers() {
        Map<Object, Object> peerMap = redisTemplate.opsForHash().entries(MESH_PEER_KEY);
        List<Object> peers = new ArrayList<>(peerMap.values());

        return ResponseEntity.ok(Map.of(
                "peers", peers,
                "count", peers.size()
        ));
    }

    @PostMapping("/stats")
    public ResponseEntity<Map<String, Object>> reportStats(@RequestBody Map<String, Object> request) {
        String deviceId = (String) request.getOrDefault("deviceId", "");
        if (deviceId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "deviceId is required"));
        }

        // Update peer stats in Redis
        Map<String, Object> peerStats = (Map<String, Object>) redisTemplate.opsForHash().get(MESH_PEER_KEY, deviceId);
        if (peerStats == null) {
            peerStats = new HashMap<>();
        }
        peerStats.putAll(request);
        peerStats.put("lastSeen", System.currentTimeMillis());
        
        redisTemplate.opsForHash().put(MESH_PEER_KEY, deviceId, peerStats);

        return ResponseEntity.ok(Map.of("status", "recorded", "deviceId", deviceId));
    }

    /**
     * Find optimal path using B.A.T.M.A.N. + AODV hybrid approach.
     */
    private List<String> findOptimalPath(String source, String target,
                                          List<Map<String, Object>> neighborMetrics) {
        if (source.equals(target)) {
            return List.of(source);
        }

        // BFS with link quality weighting (simplified B.A.T.M.A.N.)
        Set<String> visited = new HashSet<>();
        Queue<List<String>> queue = new LinkedList<>();
        queue.add(List.of(source));
        visited.add(source);

        List<String> bestPath = new ArrayList<>();
        double bestCost = Double.MAX_VALUE;

        while (!queue.isEmpty()) {
            List<String> currentPath = queue.poll();
            String currentNode = currentPath.get(currentPath.size() - 1);

            if (currentNode.equals(target)) {
                double cost = calculatePathCost(currentPath, neighborMetrics);
                if (cost < bestCost) {
                    bestCost = cost;
                    bestPath = new ArrayList<>(currentPath);
                }
                continue;
            }

            if (currentPath.size() > 10) continue; // Max hops

            // Find neighbors of current node from neighbors metrics
            for (Map<String, Object> neighbor : neighborMetrics) {
                String neighborId = (String) neighbor.get("deviceId");
                if (neighborId != null && !visited.contains(neighborId)) {
                    visited.add(neighborId);
                    List<String> newPath = new ArrayList<>(currentPath);
                    newPath.add(neighborId);
                    queue.add(newPath);
                }
            }

            // Also check routing table in Redis for known paths
            Map<Object, Object> knownRoutesMap = redisTemplate.opsForHash().entries(ROUTING_TABLE_KEY + ":" + currentNode);
            if (knownRoutesMap != null && !knownRoutesMap.isEmpty()) {
                for (Object routeObj : knownRoutesMap.values()) {
                    if (routeObj instanceof Map) {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> route = (Map<String, Object>) routeObj;
                        String nextHop = (String) route.get("nextHop");
                        if (nextHop != null && !visited.contains(nextHop)) {
                            visited.add(nextHop);
                            List<String> newPath = new ArrayList<>(currentPath);
                            newPath.add(nextHop);
                            queue.add(newPath);
                        }
                    }
                }
            }
        }

        return bestPath;
    }

    /**
     * Calculate path cost using ETX-style metric.
     */
    private double calculatePathCost(List<String> path, List<Map<String, Object>> neighborMetrics) {
        double totalCost = 0;

        for (int i = 0; i < path.size() - 1; i++) {
            String from = path.get(i);
            String to = path.get(i + 1);

            // Find link metrics
            double linkCost = 1.0; // Default cost per hop
            for (Map<String, Object> metric : neighborMetrics) {
                if (to.equals(metric.get("deviceId"))) {
                    double rssi = ((Number) metric.getOrDefault("rssi", -90.0)).doubleValue();
                    double battery = ((Number) metric.getOrDefault("battery", 50.0)).doubleValue();
                    double linkQuality = ((Number) metric.getOrDefault("linkQuality", 0.5)).doubleValue();

                    // ETX-style cost calculation
                    double rssiCost = Math.max(0, (-50 - rssi) / 30.0);
                    double batteryCost = Math.max(0, (100 - battery) / 100.0);
                    double qualityCost = 1.0 / Math.max(0.1, linkQuality);

                    linkCost = rssiCost + batteryCost + qualityCost;
                    break;
                }
            }
            totalCost += linkCost;
        }

        return totalCost;
    }
}
