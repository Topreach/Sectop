package com.dangeremergence.controller;

import com.dangeremergence.model.Broadcast;
import com.dangeremergence.service.BroadcastService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * REST controller for Mass Alert / Broadcast System.
 * All heavy logic runs on the backend; frontend is a thin client.
 */
@RestController
@RequestMapping("/api/v1/broadcasts")
@RequiredArgsConstructor
public class BroadcastController {

    private final BroadcastService broadcastService;

    /**
     * Create a new broadcast.
     * Only coordinators and admins can create broadcasts.
     */
    @PostMapping
    @PreAuthorize("hasAnyAuthority('coordinator', 'admin')")
    public ResponseEntity<?> createBroadcast(@RequestBody Map<String, Object> request) {
        try {
            Broadcast broadcast = broadcastService.createBroadcast(
                    (String) request.get("title"),
                    (String) request.get("message"),
                    (String) request.get("severity"),
                    (String) request.get("broadcastType"),
                    (String) request.get("targetState"),
                    (String) request.get("targetLga"),
                    (String) request.get("targetRoles"),
                    request.get("latitude") != null ? ((Number) request.get("latitude")).doubleValue() : null,
                    request.get("longitude") != null ? ((Number) request.get("longitude")).doubleValue() : null,
                    request.get("radiusKm") != null ? ((Number) request.get("radiusKm")).doubleValue() : null,
                    (String) request.get("createdById"),
                    request.get("expiresAt") != null ? LocalDateTime.parse((String) request.get("expiresAt")) : null
            );
            return ResponseEntity.ok(broadcast);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get active broadcasts, optionally filtered by state/LGA.
     */
    @GetMapping("/active")
    public ResponseEntity<List<Broadcast>> getActiveBroadcasts(
            @RequestParam(required = false) String state,
            @RequestParam(required = false) String lga) {
        return ResponseEntity.ok(broadcastService.getActiveBroadcasts(state, lga));
    }

    /**
     * Get broadcast by ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<Broadcast> getBroadcast(@PathVariable String id) {
        return broadcastService.getBroadcastById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Expire a broadcast.
     */
    @PostMapping("/{id}/expire")
    @PreAuthorize("hasAnyAuthority('coordinator', 'admin')")
    public ResponseEntity<Void> expireBroadcast(@PathVariable String id) {
        broadcastService.expireBroadcast(id);
        return ResponseEntity.ok().build();
    }

    /**
     * Get active broadcast count.
     */
    @GetMapping("/count")
    public ResponseEntity<Map<String, Long>> getBroadcastCount() {
        return ResponseEntity.ok(Map.of("count", broadcastService.getActiveBroadcastCount()));
    }
}
