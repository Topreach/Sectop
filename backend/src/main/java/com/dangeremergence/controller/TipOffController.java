package com.dangeremergence.controller;

import com.dangeremergence.model.TipOff;
import com.dangeremergence.service.TipOffService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * REST controller for Tip-off / Intelligence Channel.
 * Supports anonymous reporting with AI threat scoring on the backend.
 */
@RestController
@RequestMapping("/api/v1/tips")
@RequiredArgsConstructor
public class TipOffController {

    private final TipOffService tipOffService;

    /**
     * Submit a new tip-off. Supports anonymous reporting.
     * Anyone can submit a tip (authenticated or not).
     */
    @PostMapping
    public ResponseEntity<TipOff> submitTip(@RequestBody Map<String, Object> request) {
        TipOff tipOff = tipOffService.submitTip(
                (String) request.get("tipType"),
                (String) request.get("description"),
                request.get("latitude") != null ? ((Number) request.get("latitude")).doubleValue() : null,
                request.get("longitude") != null ? ((Number) request.get("longitude")).doubleValue() : null,
                request.get("accuracy") != null ? ((Number) request.get("accuracy")).doubleValue() : null,
                request.get("occurredAt") != null ? LocalDateTime.parse((String) request.get("occurredAt")) : null,
                (String) request.get("targetDescription"),
                (String) request.get("suspectDescription"),
                request.get("anonymous") == null || (boolean) request.get("anonymous"),
                (String) request.get("reporterId")
        );
        return ResponseEntity.ok(tipOff);
    }

    /**
     * Get pending tips for review (coordinator/responder only).
     */
    @GetMapping("/pending")
    @PreAuthorize("hasAnyAuthority('coordinator', 'responder', 'admin')")
    public ResponseEntity<List<TipOff>> getPendingTips() {
        return ResponseEntity.ok(tipOffService.getPendingTips());
    }

    /**
     * Get recent actionable/forwarded tips for Inbox display.
     * Public endpoint — all users can see tips in their Updates tab.
     */
    @GetMapping("/recent")
    public ResponseEntity<List<TipOff>> getRecentTips() {
        return ResponseEntity.ok(tipOffService.getRecentTips());
    }

    /**
     * Get tip-off by ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<TipOff> getTipById(@PathVariable String id) {
        return tipOffService.getTipById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Review a tip-off (coordinator/responder only).
     */
    @PostMapping("/{id}/review")
    @PreAuthorize("hasAnyAuthority('coordinator', 'responder', 'admin')")
    public ResponseEntity<TipOff> reviewTip(
            @PathVariable String id,
            @RequestBody Map<String, Object> request) {
        TipOff tipOff = tipOffService.reviewTip(
                id,
                (String) request.get("reviewerId"),
                (String) request.get("status"),
                (String) request.get("notes")
        );
        return ResponseEntity.ok(tipOff);
    }

    /**
     * Get tip-off statistics.
     */
    @GetMapping("/stats")
    @PreAuthorize("hasAnyAuthority('coordinator', 'responder', 'admin')")
    public ResponseEntity<Map<String, Object>> getStatistics() {
        return ResponseEntity.ok(tipOffService.getStatistics());
    }
}
