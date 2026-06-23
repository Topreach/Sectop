package com.dangeremergence.controller;

import com.dangeremergence.model.RadioBroadcast;
import com.dangeremergence.service.RadioBroadcastService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * REST controller for Emergency Broadcast Radio Integration.
 * When internet is cut, radio is the only way to reach rural communities.
 */
@RestController
@RequestMapping("/api/v1/radio")
@RequiredArgsConstructor
public class RadioController {

    private final RadioBroadcastService radioBroadcastService;

    /**
     * Create a new radio broadcast.
     * Only coordinators and admins can broadcast over radio.
     */
    @PostMapping("/broadcast")
    @PreAuthorize("hasAnyAuthority('coordinator', 'admin')")
    public ResponseEntity<?> createRadioBroadcast(@RequestBody Map<String, Object> request) {
        try {
            RadioBroadcast broadcast = radioBroadcastService.createRadioBroadcast(
                    (String) request.get("title"),
                    (String) request.get("message"),
                    (String) request.get("language"),
                    (String) request.get("severity"),
                    (String) request.get("broadcastType"),
                    request.get("targetFrequency") != null ? ((Number) request.get("targetFrequency")).doubleValue() : null,
                    (String) request.get("targetState"),
                    (String) request.get("targetLga"),
                    (String) request.get("ttsVoice"),
                    request.get("anonymous") == null || (boolean) request.get("anonymous"),
                    (String) request.get("createdById")
            );
            return ResponseEntity.ok(broadcast);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get broadcast history.
     */
    @GetMapping("/broadcasts")
    public ResponseEntity<List<RadioBroadcast>> getBroadcastHistory() {
        return ResponseEntity.ok(radioBroadcastService.getBroadcastHistory());
    }

    /**
     * Get broadcast by ID.
     */
    @GetMapping("/broadcasts/{id}")
    public ResponseEntity<RadioBroadcast> getBroadcastById(@PathVariable String id) {
        return radioBroadcastService.getBroadcastById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Retry a failed broadcast.
     */
    @PostMapping("/broadcasts/{id}/retry")
    @PreAuthorize("hasAnyAuthority('coordinator', 'admin')")
    public ResponseEntity<RadioBroadcast> retryBroadcast(@PathVariable String id) {
        return ResponseEntity.ok(radioBroadcastService.retryBroadcast(id));
    }
}
