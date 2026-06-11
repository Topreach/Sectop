package com.dangeremergence.service;

import com.dangeremergence.model.Evidence;
import com.dangeremergence.repository.EvidenceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Service for managing evidence files (photo/video/audio).
 *
 * Supports offline-first sync: evidence can be uploaded as base64
 * and stored directly, or referenced by URL for external storage.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class EvidenceService {

    private final EvidenceRepository evidenceRepository;

    /**
     * Store new evidence (base64 content).
     */
    @Transactional
    public Evidence storeEvidence(String parentId, String parentType,
                                   String evidenceType, String fileName,
                                   String mimeType, Long sizeBytes,
                                   String fileContent, Double latitude,
                                   Double longitude) {
        Evidence evidence = Evidence.builder()
                .id(UUID.randomUUID().toString())
                .parentId(parentId)
                .parentType(parentType)
                .evidenceType(evidenceType)
                .fileName(fileName)
                .mimeType(mimeType)
                .sizeBytes(sizeBytes)
                .fileContent(fileContent)
                .latitude(latitude)
                .longitude(longitude)
                .capturedAt(LocalDateTime.now())
                .createdAt(LocalDateTime.now())
                .build();

        Evidence saved = evidenceRepository.save(evidence);
        log.info("Evidence stored: {} (type={}) for parent: {}", saved.getId(), evidenceType, parentId);
        return saved;
    }

    /**
     * Store evidence with a file URL (external storage like S3/MinIO).
     */
    @Transactional
    public Evidence storeEvidenceWithUrl(String parentId, String parentType,
                                          String evidenceType, String fileName,
                                          String mimeType, Long sizeBytes,
                                          String fileUrl, Double latitude,
                                          Double longitude) {
        Evidence evidence = Evidence.builder()
                .id(UUID.randomUUID().toString())
                .parentId(parentId)
                .parentType(parentType)
                .evidenceType(evidenceType)
                .fileName(fileName)
                .mimeType(mimeType)
                .sizeBytes(sizeBytes)
                .fileUrl(fileUrl)
                .latitude(latitude)
                .longitude(longitude)
                .capturedAt(LocalDateTime.now())
                .createdAt(LocalDateTime.now())
                .build();

        Evidence saved = evidenceRepository.save(evidence);
        log.info("Evidence stored with URL: {} for parent: {}", saved.getId(), parentId);
        return saved;
    }

    /**
     * Get all evidence for a parent entity.
     */
    @Transactional(readOnly = true)
    public List<Evidence> getEvidenceForParent(String parentId) {
        return evidenceRepository.findByParentIdOrderByCapturedAtDesc(parentId);
    }

    /**
     * Get evidence by type.
     */
    @Transactional(readOnly = true)
    public List<Evidence> getEvidenceByType(String evidenceType) {
        return evidenceRepository.findByEvidenceTypeOrderByCapturedAtDesc(evidenceType);
    }

    /**
     * Get evidence by parent type (alert, incident, tip).
     */
    @Transactional(readOnly = true)
    public List<Evidence> getEvidenceByParentType(String parentType) {
        return evidenceRepository.findByParentTypeOrderByCapturedAtDesc(parentType);
    }

    /**
     * Get a single evidence record by ID.
     */
    @Transactional(readOnly = true)
    public Evidence getEvidence(String id) {
        return evidenceRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Evidence not found: " + id));
    }

    /**
     * Delete evidence by ID.
     */
    @Transactional
    public void deleteEvidence(String id) {
        evidenceRepository.deleteById(id);
        log.info("Evidence deleted: {}", id);
    }

    /**
     * Delete all evidence for a parent.
     */
    @Transactional
    public void deleteEvidenceForParent(String parentId) {
        evidenceRepository.deleteByParentId(parentId);
        log.info("All evidence deleted for parent: {}", parentId);
    }

    /**
     * Count evidence for a parent.
     */
    @Transactional(readOnly = true)
    public long countEvidenceForParent(String parentId) {
        return evidenceRepository.countByParentId(parentId);
    }
}
