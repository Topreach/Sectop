package com.dangeremergence.controller;

import com.dangeremergence.service.RouteService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * REST controller for Safe Route Planning.
 * All heavy computation (danger scoring, waypoint generation) runs on the backend.
 */
@RestController
@RequestMapping("/api/v1/routes")
@RequiredArgsConstructor
public class RouteController {

    private final RouteService routeService;

    /**
     * Plan a safe route between two points, avoiding danger zones and incidents.
     */
    @PostMapping("/plan")
    public ResponseEntity<Map<String, Object>> planSafeRoute(@RequestBody Map<String, Object> request) {
        double fromLat = ((Number) request.get("fromLat")).doubleValue();
        double fromLng = ((Number) request.get("fromLng")).doubleValue();
        double toLat = ((Number) request.get("toLat")).doubleValue();
        double toLng = ((Number) request.get("toLng")).doubleValue();
        boolean avoidHighways = request.get("avoidHighways") != null && (boolean) request.get("avoidHighways");
        boolean preferLitRoads = request.get("preferLitRoads") != null && (boolean) request.get("preferLitRoads");

        Map<String, Object> route = routeService.planSafeRoute(
                fromLat, fromLng, toLat, toLng, avoidHighways, preferLitRoads);
        return ResponseEntity.ok(route);
    }

    /**
     * Get danger score for a specific location.
     */
    @GetMapping("/danger-score")
    public ResponseEntity<Map<String, Object>> getDangerScore(
            @RequestParam double latitude,
            @RequestParam double longitude,
            @RequestParam(defaultValue = "5") double radiusKm) {
        return ResponseEntity.ok(routeService.getDangerScore(latitude, longitude, radiusKm));
    }
}
