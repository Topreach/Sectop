package com.dangeremergence.controller;

import com.dangeremergence.model.Evidence;
import com.dangeremergence.service.EvidenceService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * REST controller for evidence management.
 *
 * Endpoints:
 *   POST   /evidence          - Upload new evidence
 *   GET    /evidence/{id}     - Get evidence by ID
 *   GET    /evidence/parent/{parentId} - Get all evidence for a parent
 *   DELETE /evidence/{id}     - Delete evidence
 *   DELETE /evidence/parent/{parentId} - Delete all evidence for a parent
 */
@RestController
@RequestMapping("/api/v1/evidence")
@RequiredArgsConstructor
public class EvidenceController {

    private final EvidenceService evidenceService;

    /**
     * Upload new evidence (base64 content).
     */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE,
                 produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Evidence> uploadEvidence(@RequestBody Map<String, Object> body) {
        String parentId = (String) body.get("parentId");
        String parentType = (String) body.get("parentType");
        String evidenceType = (String) body.get("evidenceType");
        String fileName = (String) body.get("fileName");
        String mimeType = (String) body.get("mimeType");
        Integer sizeBytes = (Integer) body.get("sizeBytes");
        String fileContent = (String) body.get("fileContent");
        Double latitude = body.get("latitude") != null
                ? ((Number) body.get("latitude")).doubleValue() : null;
        Double longitude = body.get("longitude") != null
                ? ((Number) body.get("longitude")).doubleValue() : null;

        if (parentId == null || parentType == null || evidenceType == null) {
            return ResponseEntity.badRequest().build();
        }

        Evidence evidence = evidenceService.storeEvidence(
                parentId, parentType, evidenceType, fileName,
                mimeType, sizeBytes != null ? sizeBytes.longValue() : null,
                fileContent, latitude, longitude
        );

        return ResponseEntity.status(HttpStatus.CREATED).body(evidence);
    }

    /**
     * Get evidence by ID.
     */
    @GetMapping(value = "/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Evidence> getEvidence(@PathVariable String id) {
        try {
            Evidence evidence = evidenceService.getEvidence(id);
            return ResponseEntity.ok(evidence);
        } catch (RuntimeException e) {
            return ResponseEntity.notFound().build();
        }
    }

    /**
     * Get all evidence for a parent entity.
     */
    @GetMapping(value = "/parent/{parentId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<Evidence>> getEvidenceForParent(@PathVariable String parentId) {
        List<Evidence> evidenceList = evidenceService.getEvidenceForParent(parentId);
        return ResponseEntity.ok(evidenceList);
    }

    /**
     * Delete evidence by ID.
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteEvidence(@PathVariable String id) {
        try {
            evidenceService.deleteEvidence(id);
            return ResponseEntity.noContent().build();
        } catch (RuntimeException e) {
            return ResponseEntity.notFound().build();
        }
    }

    /**
     * Delete all evidence for a parent entity.
     */
    @DeleteMapping("/parent/{parentId}")
    public ResponseEntity<Void> deleteEvidenceForParent(@PathVariable String parentId) {
        evidenceService.deleteEvidenceForParent(parentId);
        return ResponseEntity.noContent().build();
    }
}
